// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {VaultStyleHookMock} from "./mocks/VaultStyleHookMock.sol";

/// @notice Phase 1 characterisation tests. These do not test Keel — Keel does not exist yet.
/// They pin down the v4 semantics that determine whether Keel CAN exist, so that Phase 4 argues
/// against verified behaviour rather than against assumptions.
///
/// Every assertion here corresponds to a claim in docs/RECON-hooks.md.
contract Phase1V4SemanticsTest is Test, Deployers {
    using StateLibrary for IPoolManager;

    VaultStyleHookMock internal hook;

    /// @dev All six action flags we care about, with every *_RETURNS_DELTA bit deliberately clear.
    uint160 internal constant ACTION_FLAGS = uint160(
        Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            | Hooks.AFTER_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
    );

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        // Place the hook at an address whose low 14 bits are exactly ACTION_FLAGS.
        address hookAddr = address(uint160(type(uint160).max & clearAllHookPermissionsMask) | ACTION_FLAGS);
        VaultStyleHookMock impl = new VaultStyleHookMock();
        vm.etch(hookAddr, address(impl).code);
        hook = VaultStyleHookMock(hookAddr);

        hook.setManager(manager);
        (key,) = initPool(currency0, currency1, IHooks(hookAddr), 3000, SQRT_PRICE_1_1);
        hook.setKey(key);

        // Fund the vault hook so it can provide liquidity from its own balance.
        MockERC20(Currency.unwrap(currency0)).mint(address(hook), 100e18);
        MockERC20(Currency.unwrap(currency1)).mint(address(hook), 100e18);
    }

    // ===================================================================================
    // 1. Permission flag constants — docs/RECON-hooks.md §5
    // ===================================================================================

    function test_permissionFlagConstantsMatchRecon() public pure {
        assertEq(Hooks.ALL_HOOK_MASK, uint160((1 << 14) - 1), "ALL_HOOK_MASK");
        assertEq(Hooks.BEFORE_INITIALIZE_FLAG, 1 << 13, "bit 13");
        assertEq(Hooks.AFTER_INITIALIZE_FLAG, 1 << 12, "bit 12");
        assertEq(Hooks.BEFORE_ADD_LIQUIDITY_FLAG, 1 << 11, "bit 11");
        assertEq(Hooks.AFTER_ADD_LIQUIDITY_FLAG, 1 << 10, "bit 10");
        assertEq(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG, 1 << 9, "bit 9");
        assertEq(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG, 1 << 8, "bit 8");
        assertEq(Hooks.BEFORE_SWAP_FLAG, 1 << 7, "bit 7");
        assertEq(Hooks.AFTER_SWAP_FLAG, 1 << 6, "bit 6");
        assertEq(Hooks.BEFORE_DONATE_FLAG, 1 << 5, "bit 5");
        assertEq(Hooks.AFTER_DONATE_FLAG, 1 << 4, "bit 4");
        assertEq(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG, 1 << 3, "bit 3");
        assertEq(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG, 1 << 2, "bit 2");
        assertEq(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG, 1 << 1, "bit 1");
        assertEq(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG, 1 << 0, "bit 0");
    }

    /// @notice The security property SECURITY.md §1 relies on, asserted against the real address.
    function test_returnsDeltaBitsAreClearOnHookAddress() public view {
        uint160 a = uint160(address(hook));
        assertEq(a & Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG, 0, "beforeSwap returns-delta must be clear");
        assertEq(a & Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG, 0, "afterSwap returns-delta must be clear");
        assertEq(a & Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG, 0, "afterAdd returns-delta must be clear");
        assertEq(a & Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG, 0, "afterRemove returns-delta must be clear");
    }

    // ===================================================================================
    // 2. Baseline: an EXTERNAL caller DOES trigger the hook's callbacks
    // ===================================================================================

    function test_externalCaller_firesLiquidityCallbacks() public {
        assertEq(hook.totalCallbacks(), 0, "clean start");

        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, "");

        assertEq(hook.beforeAddCount(), 1, "beforeAddLiquidity should fire for an external caller");
        assertEq(hook.afterAddCount(), 1, "afterAddLiquidity should fire for an external caller");
    }

    function test_externalCaller_firesSwapCallbacks() public {
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, "");
        uint256 before = hook.beforeSwapCount();

        swap(key, true, -1e15, "");

        assertEq(hook.beforeSwapCount(), before + 1, "beforeSwap should fire for an external swapper");
        assertEq(hook.afterSwapCount(), 1, "afterSwap should fire for an external swapper");
    }

    // ===================================================================================
    // 3. THE FINDING: a hook acting on its own pool fires NONE of its own callbacks.
    //    docs/RECON-hooks.md §4 — Hooks.sol:171-175, :217, :253, :293
    // ===================================================================================

    function test_noSelfCall_hookOwnedAddLiquidity_firesNoCallbacks() public {
        assertEq(hook.totalCallbacks(), 0, "clean start");

        hook.vaultModifyLiquidity(1e18);

        // The liquidity really was added...
        PoolId id = key.toId();
        assertEq(manager.getLiquidity(id), 1e18, "liquidity must actually have been added");

        // ...and yet the hook observed nothing at all.
        assertEq(hook.beforeAddCount(), 0, "beforeAddLiquidity MUST NOT fire on a self-call");
        assertEq(hook.afterAddCount(), 0, "afterAddLiquidity MUST NOT fire on a self-call");
        assertEq(hook.totalCallbacks(), 0, "no callback of any kind may fire on a self-call");
    }

    function test_noSelfCall_hookOwnedRemoveLiquidity_firesNoCallbacks() public {
        hook.vaultModifyLiquidity(1e18);
        assertEq(hook.totalCallbacks(), 0, "add fired nothing");

        hook.vaultModifyLiquidity(-1e18);

        PoolId id = key.toId();
        assertEq(manager.getLiquidity(id), 0, "liquidity must actually have been removed");

        assertEq(hook.beforeRemoveCount(), 0, "beforeRemoveLiquidity MUST NOT fire on a self-call");
        assertEq(hook.afterRemoveCount(), 0, "afterRemoveLiquidity MUST NOT fire on a self-call");
        assertEq(hook.totalCallbacks(), 0, "no callback of any kind may fire on a self-call");
    }

    /// @notice The whole point, stated as one assertion: a guard living in the liquidity
    /// callbacks is structurally blind to a vault hook's own withdrawals.
    function test_noSelfCall_guardInCallbacksCannotObserveVaultWithdrawal() public {
        hook.vaultModifyLiquidity(1e18);
        uint256 callbacksBefore = hook.totalCallbacks();

        // A vault-style withdrawal: the hook removes liquidity on a user's behalf.
        hook.vaultModifyLiquidity(-5e17);

        assertEq(
            hook.totalCallbacks(),
            callbacksBefore,
            "a callback-based guard sees NOTHING when the vault moves its own liquidity"
        );
    }

    // ===================================================================================
    // 4. Returns-delta bits clear => the protocol discards a hook's returned delta.
    //    docs/RECON-hooks.md §5 — PoolManager.sol:224, Hooks.sol:301
    // ===================================================================================

    function test_returnedDeltaIgnoredWhenFlagClear() public {
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, "");
        hook.setReturnBogusDelta(true);

        uint256 hookBal0Before = MockERC20(Currency.unwrap(currency0)).balanceOf(address(hook));
        uint256 hookBal1Before = MockERC20(Currency.unwrap(currency1)).balanceOf(address(hook));

        // The hook returns a non-zero afterSwap delta. Because AFTER_SWAP_RETURNS_DELTA_FLAG is
        // clear, Hooks.sol never parses it, so the swap settles as if it were zero.
        swap(key, true, -1e15, "");

        assertEq(hook.afterSwapCount(), 1, "afterSwap did run");
        assertEq(
            MockERC20(Currency.unwrap(currency0)).balanceOf(address(hook)),
            hookBal0Before,
            "hook must not have gained currency0 from a delta it is not permitted to return"
        );
        assertEq(
            MockERC20(Currency.unwrap(currency1)).balanceOf(address(hook)),
            hookBal1Before,
            "hook must not have gained currency1 from a delta it is not permitted to return"
        );
    }

    // ===================================================================================
    // 5. What a guard can read without trusting the hook. docs/RECON-hooks.md §7
    // ===================================================================================

    function test_stateLibraryReadsAreIndependentOfHook() public {
        hook.vaultModifyLiquidity(1e18);
        PoolId id = key.toId();

        // Pool liquidity, read straight from PoolManager storage via extsload.
        assertEq(manager.getLiquidity(id), 1e18, "getLiquidity");

        (uint160 sqrtPriceX96, int24 tick,,) = manager.getSlot0(id);
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1, "slot0 price");
        assertEq(tick, 0, "slot0 tick");

        // The vault's own position, keyed by the hook as owner. This number is written by the
        // PoolManager, not asserted by the hook - which is what makes it usable by a guard.
        bytes32 positionId = keccak256(abi.encodePacked(address(hook), int24(-120), int24(120), bytes32(0)));
        assertEq(manager.getPositionLiquidity(id, positionId), 1e18, "vault position liquidity");
    }
}
