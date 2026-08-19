// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";

/// @notice Phase 0 build canary. Its only job is to prove that the pinned v4-core and
/// v4-periphery commits recorded in docs/RECON.md compile together against our solc
/// settings. It has no protocol behaviour and MUST NOT be deployed.
/// Delete this file once real contracts exercise the same imports (tracked in CURRENT_STATE.md).
contract CompileCanary {
    using StateLibrary for IPoolManager;

    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @dev Touches a StateLibrary read so the extsload path is actually type-checked.
    function slot0(PoolKey calldata key) external view returns (uint160 sqrtPriceX96, int24 tick) {
        (sqrtPriceX96, tick,,) = poolManager.getSlot0(PoolId.wrap(keccak256(abi.encode(key))));
    }

    /// @dev Touches the Hooks permission-bit library so its constants are type-checked.
    function hasBeforeSwap(IHooks hooks) external pure returns (bool) {
        return uint160(address(hooks)) & Hooks.BEFORE_SWAP_FLAG != 0;
    }

    /// @dev Touches BalanceDelta and the periphery base layer.
    function unwrap(BalanceDelta delta) external pure returns (int128, int128) {
        return (delta.amount0(), delta.amount1());
    }
}

/// @dev Proves the periphery base contracts are reachable and inheritable.
abstract contract CanaryCallback is SafeCallback {}
