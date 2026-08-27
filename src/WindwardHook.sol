// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Volatility} from "./lib/Volatility.sol";

/// @title WindwardHook
/// @notice A volatility-adaptive LP fee for Uniswap v4, computed entirely from the pool's own
/// tick history.
///
/// @dev **Why volatility.** Loss-versus-rebalancing — the structural cost passive LPs pay to
/// arbitrageurs — grows with the variance of the pool price. A static fee therefore overcharges
/// swappers when the market is calm and undercharges when it is moving, which is exactly when
/// LPs are being picked off. Windward scales the fee with realised volatility so that the fee
/// tracks the adverse-selection cost it is meant to compensate.
///
/// **Why not the obvious signals.** Measurements of live Unichain v4 flow (`data/`, and the
/// study in `docs/`) ruled out every contention-based signal:
///   - priority fee: retail pays ~301x the median arbitrage transaction, so a priority-keyed
///     fee would tax retail and subsidise arbitrage;
///   - first-of-block position: 95.4% of swaps are already first-of-block for their pool;
///   - JIT races and intra-block ordering: not observed at all in the sampled window.
/// Windward therefore depends on none of them. Tick history is written by the PoolManager, is
/// available on every chain, and needs no oracle and no external call.
///
/// **Security posture.** This hook observes and prices. It never touches accounting:
///   - `beforeSwap` returns `BeforeSwapDeltaLibrary.ZERO_DELTA`;
///   - `afterSwap` returns `0`;
///   - the deployed address MUST have all four `*_RETURNS_DELTA_FLAG` bits (address bits 0-3)
///     clear, which makes the property protocol-enforced rather than a matter of our discipline:
///     with those bits clear v4 never even parses a returned delta
///     (`Hooks.sol:301`, `PoolManager.sol:224`). Asserted by test.
/// There is no owner, no upgrade path, and no pause. Every parameter is immutable.
contract WindwardHook is IHooks {
    using LPFeeLibrary for uint24;
    using StateLibrary for IPoolManager;

    /// @dev Per-pool volatility state. Packs into a single slot after the variance word.
    struct PoolState {
        uint256 varianceWad; // EWMA of tick^2 per second, WAD-scaled
        int24 lastTick; // tick at the previous observation
        uint32 lastTimestamp; // block.timestamp at the previous TIMESTAMPED observation
        bool initialized;
    }

    error NotPoolManager();
    error PoolMustUseDynamicFee();
    error InvalidFeeBounds();
    error InvalidHalfLife();
    error InvalidFeePerSigma();
    error NotInitialized();
    error HookAddressMustNotReturnDeltas();

    /// @notice Emitted whenever the volatility estimate is updated.
    event VolatilityUpdated(PoolId indexed poolId, uint256 varianceWad, uint256 sigma, uint24 feeApplied);

    IPoolManager public immutable poolManager;

    /// @notice Fee floor in pips (1e6 = 100%). Charged when the pool is perfectly calm.
    uint24 public immutable feeMin;

    /// @notice Fee ceiling in pips. The fee is clamped here no matter how violent the market is,
    /// so the hook can never price flow out of the pool entirely.
    uint24 public immutable feeMax;

    /// @notice Pips of fee added per unit of sigma (ticks per sqrt(second)).
    uint256 public immutable feePerSigma;

    /// @notice Seconds over which an old variance estimate loses half its weight.
    /// Decay is by elapsed TIME, so a quiet pool releases its fee ceiling on its own and
    /// same-block dust swaps cannot wash the estimate out.
    uint256 public immutable halfLife;

    mapping(PoolId => PoolState) private _state;

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _poolManager, uint24 _feeMin, uint24 _feeMax, uint256 _feePerSigma, uint256 _halfLife) {
        // Enforce the FULL permission set against the deployed address, not just the four
        // returns-delta bits. Checking only those left three silent failure modes: deployed
        // without BEFORE_SWAP_FLAG a dynamic-fee pool falls back to slot0.lpFee, which v4
        // seeds to 0, so every swap would be fee-free forever; without AFTER_SWAP_FLAG the
        // estimator never updates; and any EXTRA action flag routes v4 into one of the
        // reverting stubs below, bricking every modifyLiquidity and donate on the pool.
        Hooks.validateHookPermissions(
            IHooks(address(this)),
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            })
        );

        // feeMax must stay STRICTLY below MAX_LP_FEE. At exactly 100%, Pool.sol reverts
        // InvalidFeeForExactOut on every exact-output swap — the Universal Router's "buy
        // exactly N" path, i.e. ordinary retail — until the estimate decays.
        if (_feeMin > _feeMax || _feeMax >= LPFeeLibrary.MAX_LP_FEE) revert InvalidFeeBounds();
        if (_halfLife == 0 || _halfLife > Volatility.MAX_DT) revert InvalidHalfLife();
        // Bound the premium so `sigmaWad * feePerSigma` cannot overflow and permanently
        // brick the swap path. sigmaWad <= sqrt(MAX_OBSERVATION*WAD*WAD) = 1e22.
        if (_feePerSigma > type(uint128).max) revert InvalidFeePerSigma();

        poolManager = _poolManager;
        feeMin = _feeMin;
        feeMax = _feeMax;
        feePerSigma = _feePerSigma;
        halfLife = _halfLife;
    }

    /// @notice The current fee this hook would charge the given pool, in pips.
    /// @dev View helper for the demo and for integrators. Pure function of stored state.
    function currentFee(PoolId poolId) public view returns (uint24) {
        return _feeFor(_state[poolId].varianceWad);
    }

    /// @notice Current volatility estimate, WAD-scaled, in ticks per sqrt(second).
    function currentSigmaWad(PoolId poolId) external view returns (uint256) {
        return Volatility.sigmaWad(_state[poolId].varianceWad);
    }

    function getPoolState(PoolId poolId) external view returns (PoolState memory) {
        return _state[poolId];
    }

    /// @dev fee = clamp(feeMin + sigma * feePerSigma, feeMin, feeMax).
    /// Rounds DOWN, so a truncated estimate always favours the swapper rather than the LP. A fee
    /// that is slightly too low costs LPs revenue; a fee that is too high can push honest flow
    /// out of the pool, which is the worse failure.
    function _feeFor(uint256 varianceWad) internal view returns (uint24) {
        // sigma is carried WAD-scaled so the premium keeps its fractional part. Computing
        // sqrt(varianceWad / WAD) instead truncated twice and quantised the fee onto a
        // 200-pip ladder whose first rung was 40% of the entire fee floor.
        uint256 s = Volatility.sigmaWad(varianceWad);

        // sigmaWad <= 1e22 and feePerSigma <= uint128.max (constructor), so the product is
        // at most ~3.4e60 — no overflow. The clamp below bounds the result regardless.
        uint256 premium = (s * feePerSigma) / Volatility.WAD;
        uint256 fee = uint256(feeMin) + premium;
        if (fee > feeMax) fee = feeMax;
        // casting to 'uint24' is safe because fee is clamped above to feeMax, and the
        // constructor rejects feeMax >= LPFeeLibrary.MAX_LP_FEE (1e6), which is < 2^24.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint24(fee);
    }

    // -------------------------------------------------------------------------------------
    // Hook callbacks
    // -------------------------------------------------------------------------------------

    /// @dev Seeds the volatility state and enforces that the pool actually honours our fee.
    /// A pool without the dynamic-fee flag silently ignores a returned override
    /// (`Hooks.sol:263`), which would leave the hook installed but inert — a footgun worth
    /// reverting on.
    function afterInitialize(address, PoolKey calldata key, uint160, int24 tick)
        external
        override
        onlyPoolManager
        returns (bytes4)
    {
        if (!key.fee.isDynamicFee()) revert PoolMustUseDynamicFee();

        PoolId id = key.toId();
        _state[id] =
            PoolState({varianceWad: 0, lastTick: tick, lastTimestamp: uint32(block.timestamp), initialized: true});
        return IHooks.afterInitialize.selector;
    }

    /// @dev Prices the swap from the volatility estimate accumulated so far. The estimate is NOT
    /// updated here: updating before the swap would let a swapper pay a fee computed from their
    /// own price impact, which is the wrong direction. The update happens in `afterSwap`.
    function beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        external
        view
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 fee = _feeFor(_state[key.toId()].varianceWad);
        // OVERRIDE_FEE_FLAG tells v4 to use this fee for this swap only
        // (`Pool.sol:303-304`). ZERO_DELTA: this hook never alters accounting.
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    /// @dev Folds the realised tick move into the EWMA. Reads the post-swap tick straight from
    /// PoolManager storage, so the observation is written by the protocol and cannot be forged
    /// by the caller.
    function afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        onlyPoolManager
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        PoolState storage st = _state[id];
        // afterInitialize always runs before any swap (AFTER_INITIALIZE_FLAG is enforced in
        // the constructor and Pool.initialize cannot run twice), so this should be
        // unreachable. It is asserted rather than assumed because the alternative is
        // folding the gap from tick 0 into the estimator as if it were a real return.
        if (!st.initialized) revert NotInitialized();

        // block.timestamp is monotonic and lastTimestamp is derived from it, so no underflow.
        uint256 dt = block.timestamp - st.lastTimestamp;

        // dt == 0: no time has elapsed, so there is no variance-per-unit-time to measure.
        // Return WITHOUT advancing lastTick/lastTimestamp. The anchor stays put, so a price
        // move split across same-block slices is not erased — it is measured in full against
        // the next observation that does have elapsed time. This is what closes the
        // dust-swap suppression attack: same-block swaps cannot move the estimate at all.
        if (dt == 0) return (IHooks.afterSwap.selector, int128(0));

        (, int24 tickNow,,) = poolManager.getSlot0(id);

        uint256 newVariance = Volatility.update(st.varianceWad, st.lastTick, tickNow, dt, halfLife);

        st.varianceWad = newVariance;
        st.lastTick = tickNow;
        st.lastTimestamp = uint32(block.timestamp);

        // Compute the fee once and reuse it; sqrt is not cheap and an earlier version ran it
        // three times per swap purely to populate this event.
        uint24 feeNow = _feeFor(newVariance);
        emit VolatilityUpdated(id, newVariance, Volatility.sigmaWad(newVariance), feeNow);

        // Zero: this hook never takes a delta.
        return (IHooks.afterSwap.selector, int128(0));
    }

    // -------------------------------------------------------------------------------------
    // Unused callbacks. The address flags mean v4 never calls these, but IHooks requires them.
    // -------------------------------------------------------------------------------------

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    error HookNotImplemented();
}
