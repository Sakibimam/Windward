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

/// @notice Findings from the 2026-08-29 security and protocol reviews, pinned as executable tests
/// per the standing rule that every finding gets a named test — written BEFORE any fix,
/// while they still failed.
///
///   H-1  FIXED. The charged fee was read from UNDECAYED state. These two tests were originally
///        written to demonstrate the defect and have been INVERTED to assert the fix, which is
///        `_varianceNow` in WindwardHook.sol. Both fail if decay-on-read is removed.
///
///   C-1  OPEN, ACCEPTED. A same-block round trip strands the tick anchor at a price that never
///        survived the block. Its test still passes by DEMONSTRATING the defect. See
///        `THREAT_MODEL.md` §6 for why it is accepted rather than fixed.
contract WindwardOpenFindingsTest is Test, Deployers {
    using StateLibrary for IPoolManager;

    WindwardHook internal hook;
    PoolKey internal key_;

    uint24 constant FEE_MIN = 500;
    uint24 constant FEE_MAX = 10_000;

    uint160 constant FLAGS = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        address a = address(uint160(type(uint160).max & clearAllHookPermissionsMask) | FLAGS);
        deployCodeTo(
            "WindwardHook.sol:WindwardHook",
            abi.encode(IPoolManager(address(manager)), FEE_MIN, FEE_MAX, uint256(200), uint256(300)),
            a
        );
        hook = WindwardHook(a);
        (key_,) = initPool(currency0, currency1, IHooks(a), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(
            key_,
            ModifyLiquidityParams({tickLower: -60000, tickUpper: 60000, liquidityDelta: 100e18, salt: bytes32(0)}),
            ""
        );
    }

    // ===================================================================================
    // H-1 — the fee charged is read from state that has NOT been decayed for elapsed time
    // ===================================================================================

    /// @notice REGRESSION for H-1. `beforeSwap` and `currentFee` now decay the stored estimate
    /// forward to `block.timestamp` before pricing (`_varianceNow`), so elapsed time alone
    /// releases the fee — no trade required.
    ///
    /// Before the fix this pool quoted the 1% ceiling after a full week of silence, and whoever
    /// broke the silence paid it. That was also self-reinforcing: the elevated fee deterred the
    /// flow whose arrival was the only thing that could have decayed it.
    ///
    /// `THREAT_MODEL.md` V2 claimed "the ceiling releases with no trading required". That claim
    /// was FALSE when written; this test is what makes it true.
    function test_H1_feeDecaysWithElapsedTimeAlone() public {
        for (uint256 i = 0; i < 20; i++) {
            vm.warp(block.timestamp + 1);
            swap(key_, i % 2 == 0, -2e18, "");
        }
        uint24 hot = hook.currentFee(key_.toId());
        assertEq(hot, FEE_MAX, "precondition: pinned at the ceiling");

        // One hour is 12 half-lives. NOTHING trades in between.
        vm.warp(block.timestamp + 1 hours);
        uint24 afterAnHour = hook.currentFee(key_.toId());
        assertLt(afterAnHour, hot, "H-1: an hour of silence must lower the fee, with no trade");

        vm.warp(block.timestamp + 7 days);
        assertEq(hook.currentFee(key_.toId()), FEE_MIN, "H-1: a week of silence returns to the floor");

        // And the trader who breaks the silence is charged the decayed fee, not the stale one.
        swap(key_, true, -1e12, "");
        assertLe(hook.currentFee(key_.toId()), FEE_MIN + 50, "the silence-breaker is not overcharged");
    }

    /// @notice REGRESSION for H-1 through the integrator-facing view. An off-chain quoter reading
    /// `currentFee` after a quiet period used to overstate the fee by up to 20x. The view and the
    /// charged fee must agree, and both must reflect elapsed time.
    function test_H1_currentFeeViewDecaysToo() public {
        vm.warp(block.timestamp + 1);
        swap(key_, true, -3e18, "");
        uint24 quoted = hook.currentFee(key_.toId());
        assertGt(quoted, FEE_MIN, "precondition: elevated");

        vm.warp(block.timestamp + 30 days);
        assertEq(hook.currentFee(key_.toId()), FEE_MIN, "H-1: the view decays to the floor as well");
        assertEq(hook.currentSigmaWad(key_.toId()), 0, "and sigma agrees with it");
    }

    // ===================================================================================
    // C-1 — a same-block round trip strands the anchor at a phantom price
    // ===================================================================================

    /// @notice The `dt == 0` anchor hold (which closes W-01's dust-swap suppression) has a second
    /// edge. A trader who is first-of-block can displace the price, have that displaced tick
    /// recorded as the anchor, then revert the displacement in the SAME block. The revert takes
    /// the `dt == 0` path, so the anchor is left at a price that never survived the block — and
    /// the NEXT swap measures the reversal as a second, equally large move.
    ///
    /// The attacker pays real fees for both legs, so this is a griefing primitive rather than a
    /// profit one. It cannot move funds: the returns-delta bits are clear. But it lets a third
    /// party raise the fee that honest traders pay.
    function test_OPEN_C1_sameBlockRoundTripStrandsTheAnchor() public {
        // NOTE: still an OPEN finding. This test passes by demonstrating the defect.
        vm.warp(block.timestamp + 1);

        // leg 1: displace. dt > 0, so the anchor advances to the displaced tick.
        swap(key_, true, -3e18, "");
        WindwardHook.PoolState memory afterLeg1 = hook.getPoolState(key_.toId());
        (, int24 tickAfterLeg1,,) = manager.getSlot0(key_.toId());
        assertEq(afterLeg1.lastTick, tickAfterLeg1, "anchor tracks the displaced tick");

        // leg 2: SAME BLOCK, revert the displacement. dt == 0, so the anchor is held.
        swap(key_, false, -3e18, "");
        WindwardHook.PoolState memory afterLeg2 = hook.getPoolState(key_.toId());
        (, int24 tickAfterLeg2,,) = manager.getSlot0(key_.toId());

        emit log_named_int("anchor (stranded at the phantom price)", afterLeg2.lastTick);
        emit log_named_int("actual tick (reverted)", tickAfterLeg2);

        assertEq(afterLeg2.lastTick, afterLeg1.lastTick, "C-1 OPEN: anchor held at the phantom price");
        assertTrue(afterLeg2.lastTick != tickAfterLeg2, "C-1 OPEN: anchor is stranded away from the real price");

        // The next honest swap measures anchor -> real as a second phantom move.
        uint24 feeBefore = hook.currentFee(key_.toId());
        vm.warp(block.timestamp + 1);
        swap(key_, true, -1e12, ""); // a dust swap by an honest user
        uint24 feeAfter = hook.currentFee(key_.toId());

        emit log_named_uint("fee before the honest dust swap", feeBefore);
        emit log_named_uint("fee after it (phantom move charged)", feeAfter);

        assertGt(feeAfter, feeBefore, "C-1 OPEN: an honest dust swap is charged for a phantom move");
    }
}
