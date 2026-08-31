// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTestHooks} from "@uniswap/v4-core/src/test/BaseTestHooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";

/// @notice A minimal stand-in for a vault-style hook: a wrapper that owns
/// its own LP position and exposes user-facing entry points, rather than making users call the
/// PoolManager directly.
///
/// It exists only to characterise v4's `noSelfCall` semantics for Phase 1. It has no share
/// accounting and no security properties. It is NOT part of Windward and must never be deployed.
///
/// Every callback simply counts its own invocation, so a test can distinguish "the PoolManager
/// invoked this hook" from "the PoolManager silently skipped it".
contract VaultStyleHookMock is BaseTestHooks, IUnlockCallback {
    using CurrencySettler for Currency;

    IPoolManager public manager;
    PoolKey internal key;

    uint256 public beforeAddCount;
    uint256 public afterAddCount;
    uint256 public beforeRemoveCount;
    uint256 public afterRemoveCount;
    uint256 public beforeSwapCount;
    uint256 public afterSwapCount;

    /// @dev When true, afterSwap returns a non-zero delta. Used to prove the protocol ignores it
    /// unless the address carries AFTER_SWAP_RETURNS_DELTA_FLAG.
    bool public returnBogusDelta;

    function setManager(IPoolManager _manager) external {
        manager = _manager;
    }

    function setKey(PoolKey calldata _key) external {
        key = _key;
    }

    function setReturnBogusDelta(bool v) external {
        returnBogusDelta = v;
    }

    function totalCallbacks() external view returns (uint256) {
        return beforeAddCount + afterAddCount + beforeRemoveCount + afterRemoveCount + beforeSwapCount + afterSwapCount;
    }

    // -------------------------------------------------------------------------------------
    // The vault's own liquidity management. This is the path a real vault-style hook uses:
    // the HOOK is msg.sender to the PoolManager, not the end user.
    // -------------------------------------------------------------------------------------

    function vaultModifyLiquidity(int256 liquidityDelta) external {
        manager.unlock(abi.encode(liquidityDelta));
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        int256 liquidityDelta = abi.decode(data, (int256));

        (BalanceDelta delta,) = manager.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: liquidityDelta, salt: 0}), ""
        );

        // Settle whichever side we owe, and take whichever side we are owed. Amounts are cast
        // from int128 to uint256 only after an explicit sign check, so no negation overflow is
        // possible on int128.min: a negative amount is negated as int256, which cannot overflow.
        _settleOrTake(key.currency0, delta.amount0());
        _settleOrTake(key.currency1, delta.amount1());

        return "";
    }

    function _settleOrTake(Currency currency, int128 amount) internal {
        if (amount < 0) {
            currency.settle(manager, address(this), uint256(-int256(amount)), false);
        } else if (amount > 0) {
            currency.take(manager, address(this), uint256(int256(amount)), false);
        }
    }

    // -------------------------------------------------------------------------------------
    // Callbacks — each one only counts itself.
    // -------------------------------------------------------------------------------------

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        beforeAddCount++;
        return IHooks.beforeAddLiquidity.selector;
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        afterAddCount++;
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        beforeRemoveCount++;
        return IHooks.beforeRemoveLiquidity.selector;
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        afterRemoveCount++;
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        beforeSwapCount++;
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        afterSwapCount++;
        // A hook WITHOUT AFTER_SWAP_RETURNS_DELTA_FLAG returning a non-zero delta: the protocol
        // must ignore it entirely. See Hooks.sol:301 -> callHookWithReturnDelta(parseReturn=false).
        return (IHooks.afterSwap.selector, returnBogusDelta ? int128(1e12) : int128(0));
    }
}
