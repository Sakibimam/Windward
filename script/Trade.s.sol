// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {WindwardHook} from "../src/WindwardHook.sol";

/// @notice Trades the live Windward pool so the fee moves on chain, and prints it before/after.
///
/// **Run this repeatedly, not once.** `Volatility.update` treats `dt == 0` as an identity, so
/// every swap sharing a block contributes nothing — that is exactly what closes the dust-swap
/// suppression attack (W-01). Unichain produces one block per second, so each separate broadcast
/// lands in a later block and the estimator finally has elapsed time to divide by.
///
///     export WINDWARD_TOKEN0=0x...   # printed by SeedPool
///     export WINDWARD_TOKEN1=0x...
///
///     FOUNDRY_PROFILE=deploy forge script script/Trade.s.sol:Trade \
///       --rpc-url https://sepolia.unichain.org \
///       --account windward-deployer \
///       --sender 0x30c7eE328B80ce1dc15AC8F75e1FfAf51B9bB9Fb \
///       --broadcast
///
/// Set WINDWARD_SIZE to change the trade size (default 200e18 — large enough to move the tick).
/// Run it three or four times a few seconds apart and watch `fee after` climb, then stop trading
/// and re-read `currentFee` a minute later to watch it decay.
contract Trade is Script {
    using PoolIdLibrary for PoolKey;

    PoolSwapTest constant SWAP_ROUTER = PoolSwapTest(0x9140a78c1A137c7fF1c151EC8231272aF78a99A4);
    WindwardHook constant HOOK = WindwardHook(0x609634584d5BD12Ba4216116528e364d385Ad0C0);
    int24 constant TICK_SPACING = 60;

    function run() external {
        require(block.chainid == 1301, "Trade: Unichain Sepolia only");

        address t0 = vm.envAddress("WINDWARD_TOKEN0");
        address t1 = vm.envAddress("WINDWARD_TOKEN1");
        require(t0 < t1, "Trade: TOKEN0 must sort below TOKEN1");
        uint256 size = vm.envOr("WINDWARD_SIZE", uint256(200e18));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(t0),
            currency1: Currency.wrap(t1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(HOOK))
        });
        PoolId id = key.toId();

        uint24 before = HOOK.currentFee(id);
        console2.log("fee before  ", before);
        console2.log("sigmaWad    ", HOOK.currentSigmaWad(id));

        vm.startBroadcast();
        IERC20Minimal(t0).approve(address(SWAP_ROUTER), type(uint256).max);
        IERC20Minimal(t1).approve(address(SWAP_ROUTER), type(uint256).max);

        SWAP_ROUTER.swap(
            key,
            SwapParams({
                zeroForOne: true,
                // forge-lint: disable-next-line(unsafe-typecast)
                amountSpecified: -int256(size), // negative == exact input
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        vm.stopBroadcast();

        uint24 nowFee = HOOK.currentFee(id);
        console2.log("fee after   ", nowFee);
        console2.log("sigmaWad    ", HOOK.currentSigmaWad(id));
        if (nowFee == before) {
            console2.log("");
            console2.log("Unchanged. Either this swap shared a block with the last one (dt == 0,");
            console2.log("so the estimator ignored it by design) or the tick did not move. Wait a");
            console2.log("few seconds and run again, or raise WINDWARD_SIZE.");
        }
    }
}
