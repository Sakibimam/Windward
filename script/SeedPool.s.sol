// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {WindwardHook} from "../src/WindwardHook.sol";

/// @notice Creates a LIVE pool against the deployed WindwardHook and trades it, so the fee can be
/// read from chain instead of only simulated.
///
/// The hook was deployed without a pool. That is fine for a hook — pools are permissionless — but
/// it means nothing on-chain exercises it. This script closes that gap: it mints two test tokens,
/// initialises a dynamic-fee pool wired to the hook, and adds full-range liquidity.
///
/// Trading is deliberately NOT done here. `Volatility.update` treats `dt == 0` as an identity, so
/// swaps that share a block cannot move the estimate — that is what closes the dust-swap
/// suppression attack (W-01). A `forge script` simulates every call at one timestamp, so a
/// single script can never show the fee responding. Use `script/Trade.s.sol`, run repeatedly.
///
///     FOUNDRY_PROFILE=deploy forge script script/SeedPool.s.sol:SeedPool \
///       --rpc-url https://sepolia.unichain.org \
///       --account windward-deployer \
///       --sender 0x30c7eE328B80ce1dc15AC8F75e1FfAf51B9bB9Fb \
///       --broadcast
///
/// Drop `--broadcast` for a dry run. Everything here is testnet-only and uses throwaway tokens.
contract SeedPool is Script {
    using PoolIdLibrary for PoolKey;

    // Verified live on Unichain Sepolia (chain 1301) — see docs/RECON.md §6.
    IPoolManager constant MANAGER = IPoolManager(0x00B036B58a818B1BC34d502D3fE730Db729e62AC);
    WindwardHook constant HOOK = WindwardHook(0x609634584d5BD12Ba4216116528e364d385Ad0C0);

    int24 constant TICK_SPACING = 60;
    // Full range for the given spacing, so no swap in this script can run out of liquidity.
    int24 constant LOWER = -887220;
    int24 constant UPPER = 887220;

    function run() external {
        require(block.chainid == 1301, "SeedPool: Unichain Sepolia only");
        require(address(HOOK).code.length > 0, "SeedPool: hook not deployed");

        vm.startBroadcast();

        // 1. Two throwaway tokens. Sorted, because v4 requires currency0 < currency1.
        MockERC20 a = new MockERC20("Windward Test A", "WTA", 18);
        MockERC20 b = new MockERC20("Windward Test B", "WTB", 18);
        (MockERC20 t0, MockERC20 t1) = address(a) < address(b) ? (a, b) : (b, a);
        t0.mint(msg.sender, 1_000_000e18);
        t1.mint(msg.sender, 1_000_000e18);

        // 2. A liquidity router. PoolSwapTest is already deployed; this one is not.
        PoolModifyLiquidityTest liqRouter = new PoolModifyLiquidityTest(MANAGER);

        t0.approve(address(liqRouter), type(uint256).max);
        t1.approve(address(liqRouter), type(uint256).max);

        // 3. The pool. DYNAMIC_FEE_FLAG is mandatory — afterInitialize reverts without it.
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(t0)),
            currency1: Currency.wrap(address(t1)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(HOOK))
        });
        MANAGER.initialize(key, TickMath.getSqrtPriceAtTick(0));

        PoolId id = key.toId();
        console2.log("=== Windward live pool ===");
        console2.log("token0     ", address(t0));
        console2.log("token1     ", address(t1));
        console2.log("liqRouter  ", address(liqRouter));
        console2.logBytes32(PoolId.unwrap(id));
        console2.log("fee at init", HOOK.currentFee(id));

        // 4. Liquidity.
        liqRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: LOWER, tickUpper: UPPER, liquidityDelta: 50_000e18, salt: bytes32(0)}),
            ""
        );
        console2.log("fee after liquidity", HOOK.currentFee(id));

        console2.log("");
        console2.log("Pool is live. Trade it with script/Trade.s.sol, which must run as its OWN");
        console2.log("broadcast: the estimator ignores same-block swaps (dt == 0), so swaps have");
        console2.log("to land in different blocks before the fee can respond at all.");
        console2.log("");
        console2.log("  export WINDWARD_TOKEN0=%s", address(t0));
        console2.log("  export WINDWARD_TOKEN1=%s", address(t1));

        vm.stopBroadcast();
    }
}
