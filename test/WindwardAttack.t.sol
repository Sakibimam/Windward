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
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {WindwardHook} from "../src/WindwardHook.sol";

/// @notice Regression tests for the findings raised in the 2026-08-28 security and protocol
/// reviews. Each of these previously passed by DEMONSTRATING the attack; each now passes by
/// demonstrating the attack is CLOSED. They exist so the defects cannot silently return.
///
///   W-01  dust-swap fee suppression   (was: 20x, fee 10000 -> 500 within one block)
///   W-02  ceiling pinned indefinitely (was: still at the ceiling seven days later)
///   W-03  200-pip fee ladder          (was: 1 distinct fee across 40 escalating swaps)
///   W-06  feeMax == MAX_LP_FEE        (was: every exact-output swap reverts in v4)
///   F-1   permission bits unenforced  (was: a fee-free pool forever if a flag was missing)
contract WindwardAttackTest is Test, Deployers {
    using StateLibrary for IPoolManager;

    WindwardHook internal hook;
    PoolKey internal key_;

    uint24 internal constant FEE_MIN = 500;
    uint24 internal constant FEE_MAX = 10_000;
    uint256 internal constant FEE_PER_SIGMA = 200;
    uint256 internal constant HALF_LIFE = 300;

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

        (key_,) = initPool(currency0, currency1, IHooks(hookAddr), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(key_, LIQUIDITY_PARAMS, "");
        modifyLiquidityRouter.modifyLiquidity(
            key_,
            ModifyLiquidityParams({tickLower: -60000, tickUpper: 60000, liquidityDelta: 50e18, salt: bytes32(0)}),
            ""
        );
    }

    // ===================================================================================
    // W-01 — dust-swap suppression is closed
    // ===================================================================================

    /// @notice Same-block swaps must not move the estimate at all, because no time has
    /// elapsed. Before the fix, 30 dust swaps in one block dropped the fee 10000 -> 500.
    function test_W01_dustSwapsCannotSuppressTheFee() public {
        vm.warp(block.timestamp + 1);
        swap(key_, true, -5e17, "");
        uint24 feeBefore = hook.currentFee(key_.toId());
        assertGt(feeBefore, FEE_MIN, "precondition: a real move must raise the fee");

        for (uint256 i = 0; i < 30; i++) {
            swap(key_, i % 2 == 0, -1, ""); // same block: no time passes
        }

        assertEq(hook.currentFee(key_.toId()), feeBefore, "W-01 CLOSED: same-block swaps cannot move the fee");
    }

    /// @notice The anchor must not advance on a dt==0 swap, so a move split into same-block
    /// slices is measured in full against the next timestamped observation rather than erased.
    function test_W01_sameBlockSlicingCannotHideAMove() public {
        uint24 feeStart = hook.currentFee(key_.toId());

        for (uint256 i = 0; i < 10; i++) {
            swap(key_, true, -5e16, ""); // one large move, executed as same-block slices
        }
        vm.warp(block.timestamp + 1);
        swap(key_, true, -1e12, ""); // the next timestamped observation measures it

        assertGt(hook.currentFee(key_.toId()), feeStart, "W-01 CLOSED: sliced moves are still measured");
    }

    // ===================================================================================
    // W-02 — the ceiling releases with elapsed time
    // ===================================================================================

    function test_W02_feeDecaysWithWallClockTimeNotSwapCount() public {
        vm.warp(block.timestamp + 1);
        swap(key_, true, -1e18, "");
        uint24 hot = hook.currentFee(key_.toId());
        assertGt(hot, FEE_MIN, "precondition: fee elevated");

        vm.warp(block.timestamp + 1 hours); // only time passes
        swap(key_, false, -1e12, "");

        uint24 cooled = hook.currentFee(key_.toId());
        emit log_named_uint("fee immediately after the move", hot);
        emit log_named_uint("fee one hour later", cooled);
        assertLt(cooled, hot, "W-02 CLOSED: the ceiling releases as time passes");
    }

    function test_W02_oneLargeSwapDoesNotPinTheCeiling() public {
        vm.warp(block.timestamp + 1);
        swap(key_, true, -5e17, "");
        assertLt(hook.currentFee(key_.toId()), FEE_MAX, "W-02 CLOSED: one ordinary swap must not pin the ceiling");
    }

    // ===================================================================================
    // W-03 — the fee is a curve, not a ladder
    // ===================================================================================

    function test_W03_feeHasFineResolution() public {
        uint256[] memory seen = new uint256[](64);
        uint256 n;
        for (uint256 i = 0; i < 40; i++) {
            vm.warp(block.timestamp + 1);
            swap(key_, i % 2 == 0, -int256(1e14 * (i + 1)), "");
            uint24 f = hook.currentFee(key_.toId());
            bool found;
            for (uint256 j = 0; j < n; j++) {
                if (seen[j] == f) found = true;
            }
            if (!found && n < 64) seen[n++] = f;
        }
        emit log_named_uint("distinct fee values across 40 escalating swaps", n);
        assertGt(n, 10, "W-03 CLOSED: the fee must take many distinct values, not sit on a ladder");

        bool offLadder;
        for (uint256 j = 0; j < n; j++) {
            if ((seen[j] - FEE_MIN) % FEE_PER_SIGMA != 0) offLadder = true;
        }
        assertTrue(offLadder, "W-03 CLOSED: fee resolves below the old 200-pip rung");
    }

    // ===================================================================================
    // F-1 / W-06 — construction-time validation
    // ===================================================================================

    /// @notice Deploying at an address missing BEFORE_SWAP_FLAG previously produced a pool
    /// whose every swap was fee-free forever, silently. It must now revert at construction.
    function test_F1_deploymentRevertsWithoutBeforeSwapFlag() public {
        uint160 bad = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG);
        address addr = address(uint160(type(uint160).max & clearAllHookPermissionsMask) | bad);
        vm.expectRevert();
        deployCodeTo(
            "WindwardHook.sol:WindwardHook",
            abi.encode(IPoolManager(address(manager)), FEE_MIN, FEE_MAX, FEE_PER_SIGMA, HALF_LIFE),
            addr
        );
    }

    /// @notice An EXTRA action flag routes v4 into a reverting stub and bricks the pool.
    function test_F1_deploymentRevertsWithExtraFlag() public {
        uint160 bad = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
        );
        address addr = address(uint160(type(uint160).max & clearAllHookPermissionsMask) | bad);
        vm.expectRevert();
        deployCodeTo(
            "WindwardHook.sol:WindwardHook",
            abi.encode(IPoolManager(address(manager)), FEE_MIN, FEE_MAX, FEE_PER_SIGMA, HALF_LIFE),
            addr
        );
    }

    /// @notice W-06: feeMax == MAX_LP_FEE makes every exact-output swap revert inside v4.
    function test_W06_constructorRejectsFeeMaxAtMaxLpFee() public {
        address addr = address(uint160(type(uint160).max & clearAllHookPermissionsMask) | FLAGS);
        vm.expectRevert();
        deployCodeTo(
            "WindwardHook.sol:WindwardHook",
            abi.encode(IPoolManager(address(manager)), FEE_MIN, LPFeeLibrary.MAX_LP_FEE, FEE_PER_SIGMA, HALF_LIFE),
            addr
        );
    }
}
