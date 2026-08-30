// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {WindwardHook} from "../src/WindwardHook.sol";
import {HookMiner} from "./HookMiner.sol";

/// @notice Mines a valid hook address and deploys WindwardHook to Unichain Sepolia.
///
/// MUST be run under the deploy profile, for BOTH the dry run and the broadcast:
///
///   FOUNDRY_PROFILE=deploy forge script script/Deploy.s.sol:Deploy \
///     --rpc-url https://sepolia.unichain.org
///
///   FOUNDRY_PROFILE=deploy forge script script/Deploy.s.sol:Deploy \
///     --rpc-url https://sepolia.unichain.org \
///     --account windward-deployer --broadcast --verify
///
/// The address is derived from the init code hash, so mining under the default profile and
/// broadcasting under `deploy` would produce an address whose permission bits do not match the
/// deployed code — `DECISIONS.md` D-0006. `_assertDeployProfile()` below makes that mistake
/// fail loudly instead of silently.
contract Deploy is Script {
    /// @dev Verified on-chain 2026-08-28: chain id 1301, PoolManager has code, and both
    /// StateView and PositionManager independently return this address from `poolManager()`.
    /// `docs/RECON.md` §6. Never substitute an unverified address here.
    IPoolManager constant POOL_MANAGER = IPoolManager(0x00B036B58a818B1BC34d502D3fE730Db729e62AC);

    // Parameters. These match the values used throughout the study and the test suite, so the
    // deployed hook is the one the README's numbers describe.
    uint24 constant FEE_MIN = 500; // 0.05% floor
    uint24 constant FEE_MAX = 10_000; // 1.00% ceiling
    uint256 constant FEE_PER_SIGMA = 200; // pips per tick/sqrt(s)
    uint256 constant HALF_LIFE = 300; // seconds

    /// @dev afterInitialize | beforeSwap | afterSwap. All four returns-delta bits clear, which
    /// is what makes "cannot move funds" protocol-enforced rather than a matter of discipline.
    uint160 constant FLAGS = uint160(Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

    function run() public {
        _assertDeployProfile();

        bytes memory constructorArgs = abi.encode(POOL_MANAGER, FEE_MIN, FEE_MAX, FEE_PER_SIGMA, HALF_LIFE);

        (bytes32 salt, address predicted) =
            HookMiner.find(HookMiner.CREATE2_DEPLOYER, FLAGS, type(WindwardHook).creationCode, constructorArgs);

        console2.log("=== Windward deployment ===");
        console2.log("chain id        ", block.chainid);
        console2.log("PoolManager     ", address(POOL_MANAGER));
        console2.log("CREATE2 factory ", HookMiner.CREATE2_DEPLOYER);
        console2.log("salt            ", vm.toString(salt));
        console2.log("predicted addr  ", predicted);
        _logFlags(predicted);

        vm.startBroadcast();
        WindwardHook hook = new WindwardHook{salt: salt}(POOL_MANAGER, FEE_MIN, FEE_MAX, FEE_PER_SIGMA, HALF_LIFE);
        vm.stopBroadcast();

        require(address(hook) == predicted, "deployed address != mined address");
        _assertPermissions(address(hook));

        console2.log("deployed at     ", address(hook));
        console2.log("OK: address matches, permission bits verified on the deployed code.");
    }

    /// @dev The default profile compiles without via_ir and produces different bytecode, hence a
    /// different CREATE2 address. Detect the profile by comparing the runtime code size of the
    /// artifact the script was compiled with against the known deploy-profile size band.
    function _assertDeployProfile() internal view {
        uint256 len = type(WindwardHook).creationCode.length;
        // deploy profile (via_ir, optimizer_runs=44444444) produces ~6.3KB of creation code;
        // the default profile is materially larger. A wide band avoids brittleness while still
        // catching a run under the wrong profile.
        require(len < 7000, "Run with FOUNDRY_PROFILE=deploy (D-0006): creation code too large");
    }

    function _assertPermissions(address hookAddr) internal pure {
        uint160 a = uint160(hookAddr);
        require(a & HookMiner.FLAG_MASK == FLAGS, "permission bits do not match");
        require(a & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG == 0, "beforeSwap returns-delta set");
        require(a & Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG == 0, "afterSwap returns-delta set");
        require(a & Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG == 0, "afterAdd returns-delta set");
        require(a & Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG == 0, "afterRemove returns-delta set");
    }

    function _logFlags(address a) internal pure {
        uint160 u = uint160(a);
        console2.log("  afterInitialize ", u & Hooks.AFTER_INITIALIZE_FLAG != 0);
        console2.log("  beforeSwap      ", u & Hooks.BEFORE_SWAP_FLAG != 0);
        console2.log("  afterSwap       ", u & Hooks.AFTER_SWAP_FLAG != 0);
        console2.log("  returns-delta   ", u & 0x0F != 0, "(must be false)");
    }
}
