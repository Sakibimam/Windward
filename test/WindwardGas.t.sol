// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {WindwardHook} from "../src/WindwardHook.sol";

/// @notice Measures Windward's gas overhead per swap against an identical unhooked pool.
/// `THREAT_MODEL.md` V12 required this to be measured rather than estimated.
contract WindwardGasTest is Test, Deployers {
    WindwardHook internal hook;
    PoolKey internal hooked;
    PoolKey internal plain;

    uint160 internal constant FLAGS =
        uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        address hookAddr = address(uint160(type(uint160).max & clearAllHookPermissionsMask) | FLAGS);
        deployCodeTo(
            "WindwardHook.sol:WindwardHook",
            abi.encode(IPoolManager(address(manager)), uint24(500), uint24(10_000), uint256(200), uint256(300)),
            hookAddr
        );
        hook = WindwardHook(hookAddr);

        (hooked,) = initPool(currency0, currency1, IHooks(hookAddr), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);
        (plain,) = initPool(currency0, currency1, IHooks(address(0)), 500, SQRT_PRICE_1_1);

        ModifyLiquidityParams memory wide =
            ModifyLiquidityParams({tickLower: -60000, tickUpper: 60000, liquidityDelta: 50e18, salt: bytes32(0)});
        modifyLiquidityRouter.modifyLiquidity(hooked, wide, "");
        modifyLiquidityRouter.modifyLiquidity(plain, wide, "");

        // Warm both pools thoroughly. A single warmup is not enough: the first swaps pay
        // cold-SLOAD and first-write costs in the router, the manager and the tick bitmap,
        // and those dominate the hook's own overhead. Measuring too early produced a
        // NEGATIVE overhead (the hooked pool appeared cheaper), which is an artefact of
        // storage warmth, not a real result.
        for (uint256 i = 0; i < 4; i++) {
            vm.warp(block.timestamp + 12);
            swap(hooked, i % 2 == 0, -1e15, "");
            swap(plain, i % 2 == 0, -1e15, "");
        }
    }

    /// @dev Averages several measurements in an interleaved order, so neither pool
    /// systematically benefits from being measured first.
    function test_gas_overheadPerSwap() public {
        uint256 nPlain;
        uint256 nHooked;
        uint256 runs = 5;

        for (uint256 i = 0; i < runs; i++) {
            vm.warp(block.timestamp + 12);
            uint256 g0 = gasleft();
            swap(plain, i % 2 == 0, -1e15, "");
            nPlain += g0 - gasleft();

            vm.warp(block.timestamp + 12);
            g0 = gasleft();
            swap(hooked, i % 2 == 0, -1e15, "");
            nHooked += g0 - gasleft();
        }

        uint256 plainAvg = nPlain / runs;
        uint256 hookedAvg = nHooked / runs;

        emit log_named_uint("gas: unhooked static-fee pool (avg)", plainAvg);
        emit log_named_uint("gas: Windward pool (avg)", hookedAvg);
        assertGt(hookedAvg, plainAvg, "the hook must cost something; if not, the measurement is wrong");
        emit log_named_uint("gas: Windward overhead per swap", hookedAvg - plainAvg);
        emit log_named_uint("overhead as % of unhooked", (hookedAvg - plainAvg) * 100 / plainAvg);

        uint256 overhead = hookedAvg - plainAvg;

        // TIGHT bound, not a guard rail. The README quotes this number, so it must be
        // pinned here rather than transcribed from a log. Widen deliberately (and update
        // the README) if a change to the hook genuinely moves it.
        // Range re-pinned when H-1's decay-on-read was added: reading the fee now costs one
        // decayFactor() evaluation in beforeSwap, ~1,030 gas over the previous 11,192.
        assertGe(overhead, 11_500, "gas overhead below the pinned range - update the README");
        assertLe(overhead, 13_000, "gas overhead above the pinned range - update the README");

        // Persist it so analysis/gas_economics.py reads a measurement rather than a constant.
        string memory json = string.concat(
            '{"gasOverhead":',
            vm.toString(overhead),
            ',"unhookedSwapGas":',
            vm.toString(plainAvg),
            ',"hookedSwapGas":',
            vm.toString(hookedAvg),
            ',"overheadPctOfUnhooked":',
            vm.toString(overhead * 100 / plainAvg),
            ',"runs":',
            vm.toString(runs),
            ',"note":"measured by test/WindwardGas.t.sol on a local Deployers harness, not on mainnet"}'
        );
        vm.writeFile("data/gas_overhead.json", json);
    }

    /// @notice A same-block swap takes the dt==0 early return, so it should be cheaper than a
    /// swap that actually updates the estimate.
    function test_gas_sameBlockSwapIsCheaper() public {
        vm.warp(block.timestamp + 12);
        uint256 g0 = gasleft();
        swap(hooked, true, -1e15, "");
        uint256 updating = g0 - gasleft();

        // no warp: dt == 0
        g0 = gasleft();
        swap(hooked, true, -1e15, "");
        uint256 sameBlock = g0 - gasleft();

        emit log_named_uint("gas: swap that updates the estimate", updating);
        emit log_named_uint("gas: same-block swap (dt==0 early return)", sameBlock);
        assertLt(sameBlock, updating, "the dt==0 path must avoid the storage writes");
    }
}
