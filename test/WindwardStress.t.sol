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

/// @notice Stress and behavioural tests beyond the closed-finding regressions in
/// WindwardAttack.t.sol. These cover the cases the security review flagged as untested:
/// exact-output swaps, the reactive-fee ordering, oscillation, zero-movement swaps, and
/// initialisation state.
///
/// Several of these are CHARACTERISATION tests: they assert what the mechanism actually does,
/// including where that is unflattering. A test that documents a weakness is worth more than
/// one that hides it.
contract WindwardStressTest is Test, Deployers {
    using StateLibrary for IPoolManager;

    WindwardHook internal hook;
    PoolKey internal key_;

    uint24 constant FEE_MIN = 500;
    uint24 constant FEE_MAX = 10_000;
    uint256 constant FEE_PER_SIGMA = 200;
    uint256 constant HALF_LIFE = 300;

    uint160 constant FLAGS = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

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
    // Exact-output swaps — previously untested end to end
    // ===================================================================================

    /// @notice A positive amountSpecified is exact-output. Nothing in the fee path may assume
    /// exact input. v4 reverts InvalidFeeForExactOut only at a 100% fee, which the constructor
    /// forbids, so exact-output must work at every reachable fee including the ceiling.
    function test_exactOutputSwapSucceeds() public {
        vm.warp(block.timestamp + 1);
        swap(key_, true, 1e14, ""); // positive => exact output
        assertGe(hook.currentFee(key_.toId()), FEE_MIN, "fee stays in band after exact-output");
    }

    function test_exactOutputSucceedsAtTheFeeCeiling() public {
        // Drive the estimator all the way to the ceiling. Six moderate swaps only reach
        // ~4400 pips; reaching 10000 needs sustained large moves in consecutive seconds.
        for (uint256 i = 0; i < 20; i++) {
            vm.warp(block.timestamp + 1);
            swap(key_, i % 2 == 0, -2e18, "");
        }
        assertEq(hook.currentFee(key_.toId()), FEE_MAX, "precondition: at ceiling");

        // The retail "buy exactly N" path must still work at 1%.
        vm.warp(block.timestamp + 1);
        swap(key_, true, 1e14, "");
        assertLe(hook.currentFee(key_.toId()), FEE_MAX, "exact-output must not revert at the ceiling");
    }

    function test_exactInputAndExactOutputAreBothPriced() public {
        vm.warp(block.timestamp + 1);
        swap(key_, true, -1e15, ""); // exact input
        uint24 afterIn = hook.currentFee(key_.toId());

        vm.warp(block.timestamp + 1);
        swap(key_, false, 1e14, ""); // exact output, other direction
        uint24 afterOut = hook.currentFee(key_.toId());

        assertGe(afterIn, FEE_MIN, "exact-input priced");
        assertGe(afterOut, FEE_MIN, "exact-output priced");
    }

    // ===================================================================================
    // The reactive-fee ordering — characterisation, not a pass/fail on the mechanism
    // ===================================================================================

    /// @notice THE central economic weakness, asserted rather than described. The trader who
    /// moves the price pays the PRE-move fee; the next trader pays the elevated one.
    ///
    /// This test passes by DEMONSTRATING the weakness. If it ever fails, the ordering changed
    /// and the README's Limitations section must be rewritten.
    function test_CHARACTERISATION_moverPaysOldFeeNextTraderPaysNew() public {
        uint24 feeBeforeMove = hook.currentFee(key_.toId());
        assertEq(feeBeforeMove, FEE_MIN, "calm pool starts at the floor");

        // A large swap. The fee IT pays is the one read before it executed: the floor.
        vm.warp(block.timestamp + 1);
        swap(key_, true, -5e17, "");

        uint24 feeAfterMove = hook.currentFee(key_.toId());

        emit log_named_uint("fee the MOVER paid", feeBeforeMove);
        emit log_named_uint("fee the NEXT trader pays", feeAfterMove);
        emit log_named_uint("ratio", feeAfterMove / feeBeforeMove);

        assertGt(feeAfterMove, feeBeforeMove, "the mover's own impact lands on the next trader");
    }

    /// @notice The corollary that limits the attack: pumping volatility does NOT give the pumper
    /// a cheaper trade afterwards — it makes their own next trade more expensive too. So the
    /// manipulation is a griefing tool, not a profit tool.
    function test_pumpingVolatilityDoesNotCheapenTheAttackersNextTrade() public {
        vm.warp(block.timestamp + 1);
        swap(key_, true, -5e17, ""); // attacker pumps
        uint24 feeForAttackersNextTrade = hook.currentFee(key_.toId());

        assertGt(feeForAttackersNextTrade, FEE_MIN, "the pumper faces the raised fee themselves");
    }

    // ===================================================================================
    // Oscillation, zero movement, initialisation
    // ===================================================================================

    /// @notice Alternating swaps that return the price to where it started still register as
    /// volatility, because the estimator measures absolute movement, not net displacement.
    /// That is intended - a round trip genuinely is movement - but it is worth pinning.
    function test_oscillationRegistersDespiteZeroNetMovement() public {
        (, int24 t0,,) = manager.getSlot0(key_.toId());

        for (uint256 i = 0; i < 8; i++) {
            vm.warp(block.timestamp + 1);
            swap(key_, i % 2 == 0, -2e17, "");
        }

        (, int24 t1,,) = manager.getSlot0(key_.toId());
        emit log_named_int("tick before", t0);
        emit log_named_int("tick after", t1);
        emit log_named_uint("fee after oscillation", hook.currentFee(key_.toId()));

        assertGt(hook.currentFee(key_.toId()), FEE_MIN, "round trips are movement and are priced");
    }

    /// @notice A swap too small to move the tick contributes no variance. The fee should decay,
    /// not rise, across a run of them.
    function test_zeroMovementSwapsDoNotRaiseTheFee() public {
        vm.warp(block.timestamp + 1);
        swap(key_, true, -5e17, "");
        uint24 hot = hook.currentFee(key_.toId());

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 30);
            swap(key_, i % 2 == 0, -1, ""); // dust: no tick movement
        }

        assertLt(hook.currentFee(key_.toId()), hot, "dust swaps must let the estimate decay, not raise it");
    }

    /// @notice A brand-new pool prices its very first swap at the floor: the estimator is seeded
    /// at initialisation and has observed nothing yet.
    function test_firstSwapOnAFreshPoolPaysTheFloor() public {
        assertEq(hook.currentFee(key_.toId()), FEE_MIN, "fresh pool is at the floor");
        assertEq(hook.currentSigmaWad(key_.toId()), 0, "and has zero sigma");
    }

    /// @notice The fee never leaves its band under any sequence, including violent ones.
    function testFuzz_feeAlwaysWithinBand(int64 a, int64 b, uint16 gap) public {
        int256 amtA = int256(bound(a, -5e17, -1e12));
        int256 amtB = int256(bound(b, -5e17, -1e12));
        uint256 g = bound(gap, 0, 3600);

        vm.warp(block.timestamp + 1);
        swap(key_, true, amtA, "");
        vm.warp(block.timestamp + g);
        swap(key_, false, amtB, "");

        uint24 f = hook.currentFee(key_.toId());
        assertGe(f, FEE_MIN, "never below the floor");
        assertLe(f, FEE_MAX, "never above the ceiling");
    }
}
