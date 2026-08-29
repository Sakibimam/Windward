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
/// **Why not the obvious signals.** A 7-day, 426,807-swap study of live Unichain v4 flow ruled
/// out every contention-based signal. Figures are the CORRECTED ones from `data/stats.json`;
/// an earlier 50-minute sample produced larger numbers that are retracted in `DECISIONS.md`
/// D-0020 and must not be requoted:
///   - priority fee: retail (Universal Router) pays MORE than arbitrage-classified flow —
///     a 17.4x median ratio under the broad classifier (n=619). A priority-keyed fee would
///     tax retail. The conservative classifier has n=9 and cannot support a magnitude.
///   - first-of-block position: 82.7% of swaps are already the FIRST swap for their pool in
///     their block, leaving too thin a base to key a mechanism on.
///   - JIT: 19 events in 7 days across 232 pools. The design was also already covered by
///     OpenZeppelin's `LiquidityPenaltyHook`.
/// Windward therefore depends on none of them. Tick history is written by the PoolManager, is
/// available on every chain, and needs no oracle and no external call.
///
/// **Security posture: this hook cannot move funds. It can only price them.**
///   - `beforeSwap` returns `BeforeSwapDeltaLibrary.ZERO_DELTA`; `afterSwap` returns `0`;
///   - the deployed address has all four `*_RETURNS_DELTA_FLAG` bits (address bits 0-3) clear,
///     so v4 never even parses a returned delta (`Hooks.sol:266`, `:301`;
///     `PoolManager.sol:181`, `:224`). Protocol-enforced, not a matter of our discipline;
///   - the constructor calls `Hooks.validateHookPermissions` with the full 14-flag set;
///   - no owner, no pause, no upgrade path, no setters. Every parameter is `immutable`.
///
/// What is NOT claimed: the fee override IS an accounting-affecting lever (`Pool.sol:303-307`)
/// and this hook steers it between `feeMin` and `feeMax`. "Never touches accounting" was the
/// property of an earlier, abandoned design and is FALSE here. The dominant harm is a fee high
/// enough to price honest flow out of the pool. See `SECURITY.md` and `THREAT_MODEL.md`.
///
/// The claim that this improves LP outcomes is UNVALIDATED (`DECISIONS.md` D-0019). This is a
/// heuristic motivated by the loss-versus-rebalancing literature, not an implementation of any
/// optimal policy from it.
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
    ///
    /// Decay is by elapsed TIME rather than by observation count, which is what stops same-block
    /// dust swaps from washing the estimate out.
    ///
    /// KNOWN LIMITATION (H-1, `THREAT_MODEL.md` §6): decay is applied in `afterSwap`, not on
    /// read, so a quiet pool does NOT release its ceiling on its own — it releases only once a
    /// trade occurs, and that trade pays the un-decayed fee.
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
    /// @dev Decays the stored estimate forward to `block.timestamp` before pricing, so a quiet
    /// pool quotes a falling fee rather than the fee it last traded at. See `_varianceNow`.
    function currentFee(PoolId poolId) public view returns (uint24) {
        return _feeFor(_varianceNow(_state[poolId]));
    }

    /// @notice Current volatility estimate, WAD-scaled, in ticks per sqrt(second).
    /// @dev Also decayed to `block.timestamp`, so it agrees with `currentFee`.
    function currentSigmaWad(PoolId poolId) external view returns (uint256) {
        return Volatility.sigmaWad(_varianceNow(_state[poolId]));
    }

    /// @dev The stored variance decayed forward for the time elapsed since it was last written.
    ///
    /// **Why this exists (finding H-1).** `afterSwap` applies decay only when a swap happens, so
    /// reading `varianceWad` raw prices the pool as though no time had passed since the last
    /// trade. A pool driven to the 1% ceiling and then left alone still quoted 1% seven days
    /// later, and the trader who broke the silence paid it in full — a 20x overcharge that was
    /// also self-reinforcing, because a fee that deters flow prevents the very trade that would
    /// have decayed it.
    ///
    /// Decaying on READ makes elapsed time lower the fee without requiring anyone to transact.
    /// It is a pure function of state and the block timestamp: it writes nothing, so the
    /// estimator's update path and its dt == 0 anchor semantics are unchanged.
    ///
    /// An uninitialised pool has `lastTimestamp == 0`, so `dt` saturates at MAX_DT and the
    /// decay factor is zero — the view reports the floor, which is the correct answer for a
    /// pool this hook knows nothing about.
    function _varianceNow(PoolState storage st) internal view returns (uint256) {
        // block.timestamp is monotonic and lastTimestamp derives from it, so no underflow.
        uint256 dt = block.timestamp - st.lastTimestamp;
        if (dt == 0) return st.varianceWad;
        if (dt > Volatility.MAX_DT) dt = Volatility.MAX_DT;
        // Rounds DOWN, favouring the swapper: a truncated decay can only make the fee lower.
        return (Volatility.decayFactor(dt, halfLife) * st.varianceWad) / Volatility.WAD;
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

    /// @dev Prices the swap from the volatility estimate accumulated so far, decayed forward for
    /// the time elapsed since the last update. The estimate is NOT written here: updating before
    /// the swap would let a swapper pay a fee computed from their own price impact, which is the
    /// wrong direction. The write happens in `afterSwap`.
    function beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        external
        view
        override
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Decayed to NOW, not to the last trade: see `_varianceNow` (finding H-1).
        uint24 fee = _feeFor(_varianceNow(_state[key.toId()]));
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
