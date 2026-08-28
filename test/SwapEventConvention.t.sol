// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

/// @notice Pins the v4 `Swap` event's sign convention against the PROTOCOL, not against
/// anyone's reading of the natspec.
///
/// This exists because of D-0017 E-1. The natspec at
/// `lib/v4-core/src/interfaces/IPoolManager.sol:85` documents `amount0` as "the delta of the
/// currency0 balance of **the pool**". That is misleading: `PoolManager.sol:241-250` emits
/// `delta.amount0()`, which is the **caller's** delta. An analysis built on the natspec's
/// wording inverted every direction-conditional statistic in the study and produced a spurious
/// "mean reversion" result.
///
/// `analysis/common.py::caller_bought_token0` encodes the convention for the offline pipeline;
/// this test proves that convention is the one the deployed protocol actually uses.
contract SwapEventConventionTest is Test, Deployers {
    using StateLibrary for IPoolManager;

    // Must match IPoolManager.Swap exactly.
    bytes32 internal constant SWAP_TOPIC =
        keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        (key,) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, "");
    }

    /// @dev Pulls (amount0, amount1) out of the first Swap event in the recorded logs.
    function _lastSwapAmounts() internal returns (int128 amount0, int128 amount1) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == SWAP_TOPIC) {
                (amount0, amount1,,,,) = abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                return (amount0, amount1);
            }
        }
        revert("no Swap event found");
    }

    /// @notice zeroForOne = selling token0. The caller PAYS token0, so amount0 must be NEGATIVE
    /// and amount1 POSITIVE. If this ever flips, `caller_bought_token0` in the Python pipeline
    /// is wrong and every direction-conditional statistic in the study is inverted.
    function test_sellingToken0_yieldsNegativeAmount0() public {
        uint256 balBefore = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        vm.recordLogs();
        swap(key, true, -1e15, ""); // zeroForOne, exact input: sell token0
        (int128 a0, int128 a1) = _lastSwapAmounts();

        uint256 balAfter = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        assertLt(a0, 0, "selling token0 must report amount0 < 0 (caller pays token0)");
        assertGt(a1, 0, "selling token0 must report amount1 > 0 (caller receives token1)");
        assertLt(balAfter, balBefore, "and the caller's token0 balance must actually fall");
    }

    /// @notice oneForZero = buying token0. The caller RECEIVES token0, so amount0 must be
    /// POSITIVE. This is the case the inverted convention got wrong.
    function test_buyingToken0_yieldsPositiveAmount0() public {
        uint256 balBefore = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        vm.recordLogs();
        swap(key, false, -1e15, ""); // oneForZero, exact input: buy token0
        (int128 a0, int128 a1) = _lastSwapAmounts();

        uint256 balAfter = MockERC20(Currency.unwrap(currency0)).balanceOf(address(this));

        assertGt(a0, 0, "buying token0 must report amount0 > 0 (caller receives token0)");
        assertLt(a1, 0, "buying token0 must report amount1 < 0 (caller pays token1)");
        assertGt(balAfter, balBefore, "and the caller's token0 balance must actually rise");
    }

    /// @notice The two directions must never be confusable — the assertion that would have
    /// caught D-0017 E-1 immediately.
    function test_buyAndSellHaveOppositeAmount0Signs() public {
        vm.recordLogs();
        swap(key, true, -1e15, "");
        (int128 sellA0,) = _lastSwapAmounts();

        vm.recordLogs();
        swap(key, false, -1e15, "");
        (int128 buyA0,) = _lastSwapAmounts();

        assertTrue(sellA0 < 0 && buyA0 > 0, "buy and sell must have opposite amount0 signs");
    }

    /// @notice A buy of token0 raises token0's price, so the tick must rise. This pins the
    /// direction->price relationship the study's momentum/reversion statistics depend on.
    function test_buyingToken0_raisesTheTick() public {
        (, int24 tickBefore,,) = manager.getSlot0(key.toId());
        swap(key, false, -1e16, ""); // buy token0
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());
        assertGt(tickAfter, tickBefore, "buying token0 must raise the tick");
    }

    function test_sellingToken0_lowersTheTick() public {
        (, int24 tickBefore,,) = manager.getSlot0(key.toId());
        swap(key, true, -1e16, ""); // sell token0
        (, int24 tickAfter,,) = manager.getSlot0(key.toId());
        assertLt(tickAfter, tickBefore, "selling token0 must lower the tick");
    }
}
