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
    uint256 internal constant ALPHA = 3e17; // 0.3

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
            abi.encode(IPoolManager(address(manager)), FEE_MIN, FEE_MAX, FEE_PER_SIGMA, ALPHA),
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
        assertEq(hook.currentSigma(dynKey.toId()), 0, "sigma starts at zero");
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
    // THE HEADLINE: identical flow through a static-fee pool and a Windward pool
    // ===================================================================================

    /// @notice Fee growth per unit of liquidity is directly comparable because both pools are
    /// seeded with identical liquidity over an identical range at an identical starting price.
    function test_windwardEarnsMoreThanStaticFeeOnVolatileFlow() public {
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

        assertGt(dyn0 + dyn1, sta0 + sta1, "Windward must out-earn a static fee on volatile flow");
    }

    /// @notice The other half of the claim, and the one that is easy to get wrong: on calm flow
    /// Windward must NOT overcharge relative to the same static fee.
    function test_windwardDoesNotOverchargeOnCalmFlow() public {
        for (uint256 i = 0; i < 8; i++) {
            vm.warp(block.timestamp + 3600);
            swap(dynKey, i % 2 == 0, -1e12, "");
            swap(staticKey, i % 2 == 0, -1e12, "");
        }

        assertEq(hook.currentFee(dynKey.toId()), FEE_MIN, "a calm pool must sit at the floor, not above the static fee");
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
        assertEq(Volatility.update(0, 100, 100, 10, 3e17), 0, "no move => no variance");
    }

    function test_updateGrowsWithLargerMove() public pure {
        uint256 small = Volatility.update(0, 0, 10, 1, 1e18);
        uint256 large = Volatility.update(0, 0, 100, 1, 1e18);
        assertGt(large, small, "a bigger tick move must produce more variance");
    }

    /// @notice A same-timestamp burst must not produce an unbounded spike; MIN_DT clamps it.
    function test_updateHandlesZeroElapsedTime() public pure {
        uint256 v = Volatility.update(0, 0, 50, 0, 1e18);
        assertEq(v, Volatility.update(0, 0, 50, 1, 1e18), "dt=0 must clamp to MIN_DT");
    }

    function test_observationIsCapped() public pure {
        uint256 huge = Volatility.update(0, type(int24).min, type(int24).max, 1, 1e18);
        assertLe(huge / Volatility.WAD, Volatility.MAX_OBSERVATION, "observation cap must hold");
    }

    function testFuzz_varianceNeverExceedsCap(uint256 v0, int24 a, int24 b, uint256 dt, uint256 alpha) public pure {
        v0 = bound(v0, 0, Volatility.MAX_OBSERVATION * Volatility.WAD);
        dt = bound(dt, 0, 1e6);
        alpha = bound(alpha, 1, Volatility.WAD);
        uint256 v1 = Volatility.update(v0, a, b, dt, alpha);
        assertLe(v1 / Volatility.WAD, Volatility.MAX_OBSERVATION, "EWMA must stay under the cap");
    }
}
