// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {WindwardHook} from "../src/WindwardHook.sol";
import {Volatility} from "../src/lib/Volatility.sol";

contract WindwardHookTest is Test, Deployers {
    using StateLibrary for IPoolManager;

    WindwardHook internal hook;
    PoolKey internal dynKey; // dynamic-fee pool, Windward installed
    PoolKey internal staticKey; // identical pool, static fee, no hook

    uint24 internal constant FEE_MIN = 500; // 0.05%
    uint24 internal constant FEE_MAX = 10_000; // 1.00%
    uint256 internal constant FEE_PER_SIGMA = 200; // pips of fee per tick/sqrt(s)
    uint256 internal constant HALF_LIFE = 300; // seconds

    uint24 internal constant STATIC_FEE = 500; // matches FEE_MIN for a fair baseline

    /// @dev afterInitialize | beforeSwap | afterSwap. All four returns-delta bits deliberately clear.
    uint160 internal constant FLAGS =
        uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        address hookAddr = address(uint160(type(uint160).max & clearAllHookPermissionsMask) | FLAGS);
        deployCodeTo(
            "WindwardHook.sol:WindwardHook",
            abi.encode(IPoolManager(address(manager)), FEE_MIN, FEE_MAX, FEE_PER_SIGMA, HALF_LIFE),
            hookAddr
        );
        hook = WindwardHook(hookAddr);

        (dynKey,) = initPool(currency0, currency1, IHooks(hookAddr), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);
        (staticKey,) = initPool(currency0, currency1, IHooks(address(0)), STATIC_FEE, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(dynKey, LIQUIDITY_PARAMS, "");
        modifyLiquidityRouter.modifyLiquidity(staticKey, LIQUIDITY_PARAMS, "");

        // A wide band as well, so a run of same-direction swaps cannot walk the price out of
        // range and revert with PriceLimitAlreadyExceeded before the test has finished.
        ModifyLiquidityParams memory wide =
            ModifyLiquidityParams({tickLower: -60000, tickUpper: 60000, liquidityDelta: 50e18, salt: bytes32(0)});
        modifyLiquidityRouter.modifyLiquidity(dynKey, wide, "");
        modifyLiquidityRouter.modifyLiquidity(staticKey, wide, "");
    }

    // ===================================================================================
    // Security properties — these are the ones that must never regress
    // ===================================================================================

    function test_returnsDeltaBitsAreClear() public view {
        uint160 a = uint160(address(hook));
        assertEq(a & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG, 0, "beforeSwap returns-delta must be clear");
        assertEq(a & Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG, 0, "afterSwap returns-delta must be clear");
        assertEq(a & Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG, 0, "afterAdd returns-delta must be clear");
        assertEq(a & Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG, 0, "afterRemove returns-delta must be clear");
    }

    /// @notice The hook must never end up holding value, under any sequence.
    function test_hookHoldsNoTokens() public {
        for (uint256 i = 0; i < 8; i++) {
            vm.warp(block.timestamp + 12);
            swap(dynKey, i % 2 == 0, -1e15, "");
        }
        assertEq(MockERC20(Currency.unwrap(currency0)).balanceOf(address(hook)), 0, "hook holds currency0");
        assertEq(MockERC20(Currency.unwrap(currency1)).balanceOf(address(hook)), 0, "hook holds currency1");
        assertEq(address(hook).balance, 0, "hook holds native");
    }

    function test_revert_callbacksAreOnlyCallableByPoolManager() public {
        vm.expectRevert(WindwardHook.NotPoolManager.selector);
        hook.beforeSwap(address(this), dynKey, SwapParams(true, -1, 0), "");

        vm.expectRevert(WindwardHook.NotPoolManager.selector);
        hook.afterInitialize(address(this), dynKey, SQRT_PRICE_1_1, 0);
    }

    /// @notice A static-fee pool silently ignores our override, leaving the hook inert.
    /// Refusing to initialise is much safer than appearing to work.
    function test_revert_staticFeePoolIsRejected() public {
        vm.expectRevert();
        initPool(currency0, currency1, IHooks(address(hook)), 3000, SQRT_PRICE_1_1);
    }

    // ===================================================================================
    // Fee behaviour
    // ===================================================================================

    function test_calmPoolChargesFeeMin() public view {
        assertEq(hook.currentFee(dynKey.toId()), FEE_MIN, "an untouched pool must charge the floor");
        assertEq(hook.currentSigmaWad(dynKey.toId()), 0, "sigma starts at zero");
    }

    function test_feeRisesWithRealisedVolatility() public {
        uint24 feeBefore = hook.currentFee(dynKey.toId());

        // A sequence of large, same-direction swaps in quick succession: a big price move in
        // little time, i.e. high realised volatility.
        for (uint256 i = 0; i < 6; i++) {
            vm.warp(block.timestamp + 1);
            swap(dynKey, i % 2 == 0, -5e17, "");
        }

        uint24 feeAfter = hook.currentFee(dynKey.toId());
        assertGt(feeAfter, feeBefore, "fee must rise after a violent move");
        assertGe(feeAfter, FEE_MIN, "never below the floor");
        assertLe(feeAfter, FEE_MAX, "never above the ceiling");
    }

    function test_feeDecaysBackWhenPoolCalms() public {
        for (uint256 i = 0; i < 6; i++) {
            vm.warp(block.timestamp + 1);
            swap(dynKey, i % 2 == 0, -5e17, "");
        }
        uint24 volatileFee = hook.currentFee(dynKey.toId());

        // Now tiny swaps spaced far apart: almost no price movement per unit time.
        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 600);
            swap(dynKey, i % 2 == 0, -1e12, "");
        }
        uint24 calmFee = hook.currentFee(dynKey.toId());

        assertLt(calmFee, volatileFee, "fee must decay once the market calms");
    }

    function test_feeIsClampedAtMax() public {
        // Drive the estimator hard, then confirm the ceiling holds.
        for (uint256 i = 0; i < 20; i++) {
            vm.warp(block.timestamp + 1);
            swap(dynKey, i % 2 == 0, -1e18, "");
        }
        assertLe(hook.currentFee(dynKey.toId()), FEE_MAX, "ceiling must hold under any sequence");
    }

    // ===================================================================================
    // SANITY CHECK - NOT EVIDENCE.
    //
    // This forces IDENTICAL volume through both pools and then observes that the pool
    // charging a higher fee collected more fees. That is arithmetic, not a finding: it
    // proves 10000 > 500. It models no demand elasticity, no LP PnL, and no counterfactual
    // for the flow that would have left at the higher fee. It must never be presented as
    // evidence that Windward improves LP outcomes. See docs/WINDWARD_DESIGN.md, Limitations.
    // ===================================================================================

    function test_sanity_higherFeeOnIdenticalVolumeCollectsMoreFees() public {
        int256[8] memory sizes = [int256(-5e17), -4e17, -6e17, -5e17, int256(-5e17), -4e17, -6e17, -5e17];

        for (uint256 i = 0; i < sizes.length; i++) {
            vm.warp(block.timestamp + 1);
            swap(dynKey, i % 2 == 0, sizes[i], "");
            swap(staticKey, i % 2 == 0, sizes[i], "");
        }

        (uint256 dyn0, uint256 dyn1) = manager.getFeeGrowthGlobals(dynKey.toId());
        (uint256 sta0, uint256 sta1) = manager.getFeeGrowthGlobals(staticKey.toId());

        emit log_named_uint("windward feeGrowth0", dyn0);
        emit log_named_uint("static   feeGrowth0", sta0);
        emit log_named_uint("windward feeGrowth1", dyn1);
        emit log_named_uint("static   feeGrowth1", sta1);
        emit log_named_uint("final windward fee (pips)", hook.currentFee(dynKey.toId()));
        emit log_named_uint("static fee (pips)", STATIC_FEE);

        assertGt(dyn0 + dyn1, sta0 + sta1, "sanity: a higher fee on identical forced volume collects more");
    }

    /// @notice The other half of the claim, and the one that is easy to get wrong: on calm flow
    /// Windward must NOT overcharge relative to the same static fee.
    /// @notice Calm flow must not be meaningfully more expensive than the matched static pool.
    ///
    /// @dev This assertion used to be `assertEq(fee, FEE_MIN)`, and that exact equality was an
    /// ARTEFACT OF FINDING H-1, not a property of the design. Before decay-on-read, the second
    /// iteration was charged a stale 503 pips computed from an hour-old observation; those extra
    /// 3 pips were just enough that the 1e12 dust swap could no longer cross back over the tick
    /// boundary. The price stuck at -1, no further movement was ever observed, and the estimate
    /// decayed to zero — so the pool read as perfectly calm because the stale fee had suppressed
    /// the very flow that would have revealed it moving. H-1's self-reinforcing pathology,
    /// reproduced inside a test that was reading as a pass.
    ///
    /// With decay-on-read the second swap is charged the floor, crosses back, and the pool
    /// oscillates 0 / -1 once an hour. That is genuine movement, so sigma is genuinely non-zero
    /// and the fee genuinely sits a few pips above the floor. The mechanism is working.
    ///
    /// So the test now asserts what it always meant: on calm flow Windward stays within a few
    /// pips of its floor. It does not assert an exact equality that only held while a bug was
    /// silencing the pool. (`DECISIONS.md` D-0022.)
    function test_windwardDoesNotOverchargeOnCalmFlow() public {
        for (uint256 i = 0; i < 8; i++) {
            vm.warp(block.timestamp + 3600);
            swap(dynKey, i % 2 == 0, -1e12, "");
            swap(staticKey, i % 2 == 0, -1e12, "");
        }

        uint24 fee = hook.currentFee(dynKey.toId());
        assertGe(fee, FEE_MIN, "never below the floor");
        // 10 pips = 2% of the 500-pip floor = 0.001% of notional. A one-tick-per-hour pool is
        // calm by any economic definition, and must be priced as such.
        assertLe(fee, FEE_MIN + 10, "calm flow must stay within a few pips of the floor");
    }
}

contract VolatilityLibTest is Test {
    function test_sqrtKnownValues() public pure {
        assertEq(Volatility.sqrt(0), 0);
        assertEq(Volatility.sqrt(1), 1);
        assertEq(Volatility.sqrt(4), 2);
        assertEq(Volatility.sqrt(8), 2);
        assertEq(Volatility.sqrt(9), 3);
        assertEq(Volatility.sqrt(1e18), 1e9);
    }

    /// @notice floor(sqrt(x)) is the unique y with y^2 <= x < (y+1)^2.
    function testFuzz_sqrtIsFloorOfSquareRoot(uint256 x) public pure {
        x = bound(x, 0, type(uint128).max);
        uint256 y = Volatility.sqrt(x);
        assertLe(y * y, x, "y^2 must not exceed x");
        assertGt((y + 1) * (y + 1), x, "(y+1)^2 must exceed x");
    }

    function test_updateIsZeroForNoPriceMove() public pure {
        assertEq(Volatility.update(0, 100, 100, 10, 300), 0, "no move => no variance");
    }

    function test_updateGrowsWithLargerMove() public pure {
        uint256 small = Volatility.update(0, 0, 10, 1, 1);
        uint256 large = Volatility.update(0, 0, 100, 1, 1);
        assertGt(large, small, "a bigger tick move must produce more variance");
    }

    /// @notice W-01's fix, at the library level: dt == 0 carries no information about
    /// variance per unit time, so the estimate must be returned unchanged.
    function test_updateIsAnIdentityWhenNoTimeElapsed() public pure {
        assertEq(Volatility.update(12345e18, 0, 5000, 0, 300), 12345e18, "dt==0 must not change the estimate");
        assertEq(Volatility.update(0, 0, 5000, 0, 300), 0, "dt==0 must not change the estimate");
    }

    /// @notice W-03's fix: the observation must survive when dTick^2 < dt, which is the
    /// common case on real Unichain flow (1-6 tick moves over 1-13 seconds).
    function test_smallMovesOverLongGapsSurvive() public pure {
        // dTick=2, dt=25 -> integer (dTick^2)/dt would be 0. WAD scaling must preserve it.
        uint256 v = Volatility.update(0, 0, 2, 25, 300);
        assertGt(v, 0, "W-03 CLOSED: a 2-tick move over 25s must not round to zero");
        assertGt(Volatility.sigmaWad(v), 0, "and sigma must be non-zero");
    }

    function test_decayFactorIsMonotoneAndHalves() public pure {
        assertEq(Volatility.decayFactor(0, 300), Volatility.WAD, "dt=0 retains everything");
        assertEq(Volatility.decayFactor(300, 300), Volatility.WAD / 2, "one half-life halves it");
        assertEq(Volatility.decayFactor(600, 300), Volatility.WAD / 4, "two half-lives quarter it");
        assertEq(Volatility.decayFactor(300 * 64, 300), 0, "64 half-lives is zero at WAD precision");
        assertEq(Volatility.decayFactor(100, 0), 0, "a zero half-life decays instantly");
    }

    function testFuzz_decayFactorIsMonotoneNonIncreasing(uint256 dt1, uint256 dt2, uint256 hl) public pure {
        hl = bound(hl, 1, 7 days);
        dt1 = bound(dt1, 0, 7 days);
        dt2 = bound(dt2, dt1, 7 days);
        assertGe(Volatility.decayFactor(dt1, hl), Volatility.decayFactor(dt2, hl), "longer gap must never retain more");
    }

    function testFuzz_decayFactorIsBounded(uint256 dt, uint256 hl) public pure {
        hl = bound(hl, 1, 7 days);
        dt = bound(dt, 0, 30 days);
        assertLe(Volatility.decayFactor(dt, hl), Volatility.WAD, "decay factor cannot exceed 1");
    }

    function test_observationIsCapped() public pure {
        uint256 huge = Volatility.update(0, type(int24).min, type(int24).max, 1, 300);
        assertLe(huge / Volatility.WAD, Volatility.MAX_OBSERVATION, "observation cap must hold");
    }

    function testFuzz_varianceNeverExceedsCap(uint256 v0, int24 a, int24 b, uint256 dt, uint256 hl) public pure {
        v0 = bound(v0, 0, Volatility.MAX_OBSERVATION * Volatility.WAD);
        dt = bound(dt, 0, 1e6);
        hl = bound(hl, 1, 7 days);
        uint256 v1 = Volatility.update(v0, a, b, dt, hl);
        assertLe(v1 / Volatility.WAD, Volatility.MAX_OBSERVATION, "EWMA must stay under the cap");
    }
}
