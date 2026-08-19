// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {CompileCanary} from "../src/CompileCanary.sol";

/// @notice Phase 0 build canary test. Proves forge-std and the v4-core test harness
/// (Deployers) compile and run against our pinned dependency set.
contract CompileCanaryTest is Test, Deployers {
    CompileCanary internal canary;

    function setUp() public {
        deployFreshManagerAndRouters();
        canary = new CompileCanary(IPoolManager(address(manager)));
    }

    function test_managerDeployed() public view {
        assertTrue(address(manager) != address(0), "PoolManager not deployed");
        assertEq(address(canary.poolManager()), address(manager));
    }

    function test_hookFlagDecoding() public view {
        // BEFORE_SWAP_FLAG is asserted below against the library constant itself in
        // docs/RECON.md; here we only check the bitmask decode is wired correctly.
        assertTrue(canary.hasBeforeSwap(IHooks(address(uint160(1 << 7)))));
        assertFalse(canary.hasBeforeSwap(IHooks(address(uint160(1 << 6)))));
    }
}
