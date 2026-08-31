# docs/RECON-hooks.md — Uniswap v4 hook API evidence

Every signature, constant, and behaviour below was read from source on disk on **2026-08-28**.

**Commit under review:** v4-core `59d3ecf53afa9264a16bba0e38f4c5d2231f80bc`
(v4-periphery `dce236d4e2057422d0791d9a973a58765eb46f65`). Paths are repo-relative; line numbers
are at that commit. Nothing here came from a tutorial, a blog post, or memory.

> Naming note: this file is about **Uniswap v4 hooks**. The unrelated local shell guard-hook
> evidence formerly at this path now lives in `docs/RECON-guard-hook.md`.

---

## 1. The settlement model — what v4 actually guarantees

`FACT` `lib/v4-core/src/PoolManager.sol:104-114`

```solidity
function unlock(bytes calldata data) external override returns (bytes memory result) {
    if (Lock.isUnlocked()) AlreadyUnlocked.selector.revertWith();
    Lock.unlock();
    // the caller does everything in this callback, including paying what they owe via calls to settle
    result = IUnlockCallback(msg.sender).unlockCallback(data);
    if (NonzeroDeltaCount.read() != 0) CurrencyNotSettled.selector.revertWith();
    Lock.lock();
}
```

`FACT` The **only** global invariant enforced at the end of a v4 transaction is
`NonzeroDeltaCount == 0` — every currency delta, for every address, must net to zero
(`PoolManager.sol:112`).

`FACT` Deltas are per-`(address, currency)` values in **transient storage**
(`lib/v4-core/src/libraries/CurrencyDelta.sol:10-41`, `tload`/`tstore`). They exist only for the
duration of the transaction.

`INFERENCE` **This is a conservation check, not a solvency check.** It says tokens moved
consistently; it says nothing about whether any accounting layered on top is coherent. This is
exactly the gap the guard-hook design targeted, and this sweep confirms the gap is real: there is
no v4 mechanism that inspects a hook's own bookkeeping. **`HYPOTHESIS` remains** that a useful
generic invariant exists to fill it — that question is not settled here.

## 2. Hook callback signatures — complete and verified

`FACT` `lib/v4-core/src/interfaces/IHooks.sol`. **Return tuples included** — these were
`UNVERIFIED` beforehand and are the most common source of stale-memory errors.

| Line | Signature | Returns |
|---|---|---|
| 21 | `beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)` | `bytes4` |
| 29-31 | `afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)` | `bytes4` |
| 39-44 | `beforeAddLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData)` | `bytes4` |
| 55-62 | `afterAddLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, BalanceDelta delta, BalanceDelta feesAccrued, bytes calldata hookData)` | `(bytes4, BalanceDelta)` |
| 70-75 | `beforeRemoveLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, bytes calldata hookData)` | `bytes4` |
| 86-93 | `afterRemoveLiquidity(address sender, PoolKey calldata key, ModifyLiquidityParams calldata params, BalanceDelta delta, BalanceDelta feesAccrued, bytes calldata hookData)` | `(bytes4, BalanceDelta)` |
| 103-105 | `beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)` | `(bytes4, BeforeSwapDelta, uint24)` |
| 115-121 | `afterSwap(address sender, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData)` | `(bytes4, int128)` |
| 130-136 | `beforeDonate(address sender, PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData)` | `bytes4` |
| 145-151 | `afterDonate(address sender, PoolKey calldata key, uint256 amount0, uint256 amount1, bytes calldata hookData)` | `bytes4` |

`FACT` `beforeSwap` must return exactly **96 bytes** (`bytes4` + 32-byte delta + fee), enforced at
`lib/v4-core/src/libraries/Hooks.sol:259`; a wrong length reverts `InvalidHookResponse`.

### Parameter structs

`FACT` `lib/v4-core/src/types/PoolOperation.sol:8-16, 19-26` — **`SwapParams` and
`ModifyLiquidityParams` are free-standing structs in `PoolOperation.sol`, not nested in
`IPoolManager`.** Importing `IPoolManager.SwapParams` does not compile at this commit.

```solidity
struct ModifyLiquidityParams { int24 tickLower; int24 tickUpper; int256 liquidityDelta; bytes32 salt; }
struct SwapParams { bool zeroForOne; int256 amountSpecified; uint160 sqrtPriceLimitX96; }
```

`FACT` `amountSpecified` is **negative for exactInput, positive for exactOutput**
(`PoolOperation.sol:22`).

`FACT` `PoolKey` is `{Currency currency0; Currency currency1; uint24 fee; int24 tickSpacing; IHooks hooks;}`
(`lib/v4-core/src/types/PoolKey.sol:11-22`). `PoolId` is `keccak256` over its 5 slots
(`lib/v4-core/src/types/PoolId.sol:11-16`) — a `bytes32` user type, `key.toId()`.

## 3. Callback ordering

`FACT` `modifyLiquidity` (`PoolManager.sol:145-184`):
`beforeModifyLiquidity` (:156) → `pool.modifyLiquidity` (:159) → `emit ModifyLiquidity` (:175) →
`afterModifyLiquidity` (:178) → account hook delta (:181) → account caller delta (:183).

`FACT` `swap` (`PoolManager.sol:187-227`):
`beforeSwap` (:202) → `_swap` (:206) → `afterSwap` (:221) → account hook delta (:224) →
account caller delta (:226).

`FACT` `initialize` (`PoolManager.sol:117-142`): validity check (:126) → `beforeInitialize` (:130)
→ `_pools[id].initialize` (:134) → `afterInitialize` (:141).

`FACT` The position owner recorded in the pool is **`msg.sender`** — the direct caller of
`modifyLiquidity` (`PoolManager.sol:161`). For a vault-style hook that manages its own LP
position, that owner is the hook contract itself.

`FACT` Fees are credited to the caller together with principal:
`callerDelta = principalDelta + feesAccrued` (`PoolManager.sol:171`). `feesAccrued` is passed to
the after-liquidity callbacks separately, so a hook can distinguish fee income from principal.

## 4. `noSelfCall` — the most consequential finding of this sweep

`FACT` `lib/v4-core/src/libraries/Hooks.sol:170-175`

```solidity
/// @notice modifier to prevent calling a hook if they initiated the action
modifier noSelfCall(IHooks self) {
    if (msg.sender != address(self)) {
        _;
    }
}
```

`FACT` It is applied to `beforeInitialize` (:178), `afterInitialize` (:187),
`beforeModifyLiquidity` (:200), `beforeDonate` (:320), `afterDonate` (:330).

`FACT` The remaining three carry the same guard inline, as an early return:

- `afterModifyLiquidity` — `Hooks.sol:217`
  `if (msg.sender == address(self)) return (delta, BalanceDeltaLibrary.ZERO_DELTA);`
- `beforeSwap` — `Hooks.sol:253`
  `if (msg.sender == address(self)) return (amountToSwap, BeforeSwapDeltaLibrary.ZERO_DELTA, lpFeeOverride);`
- `afterSwap` — `Hooks.sol:293`
  `if (msg.sender == address(self)) return (swapDelta, BalanceDeltaLibrary.ZERO_DELTA);`

`FACT` **Coverage is total: when a hook calls the PoolManager itself, none of its own ten
callbacks fire.**

### Proven by test, not just by reading

`FACT` `test/Phase1_V4Semantics.t.sol` — 9 tests, all passing. It deploys `VaultStyleHookMock`
(`test/mocks/VaultStyleHookMock.sol`) at an address carrying the six action flags, and counts
every callback invocation.

| Test | Proves |
|---|---|
| `test_externalCaller_firesLiquidityCallbacks` | baseline — an external router **does** trigger `beforeAddLiquidity`/`afterAddLiquidity` |
| `test_externalCaller_firesSwapCallbacks` | baseline — an external swapper **does** trigger `beforeSwap`/`afterSwap` |
| `test_noSelfCall_hookOwnedAddLiquidity_firesNoCallbacks` | the hook adds 1e18 liquidity itself: `getLiquidity` confirms it landed, and **zero** callbacks fired |
| `test_noSelfCall_hookOwnedRemoveLiquidity_firesNoCallbacks` | the hook removes its liquidity: pool liquidity returns to 0, and **zero** callbacks fired |
| `test_noSelfCall_guardInCallbacksCannotObserveVaultWithdrawal` | the finding as a single assertion: a vault-style withdrawal is completely invisible to a callback-based guard |

`FACT` Upstream corroborates this independently: `lib/v4-core/test/SkipCallsTestHook.t.sol`
exercises all ten callbacks with a hook that re-enters the manager from inside each one, and
asserts the counter increments exactly once per external call (e.g. :49, :68-75, :101-110). If
self-calls re-entered the hook, those tests would recurse rather than increment by one.

`INFERENCE` The `noSelfCall` behaviour is therefore **intentional, tested upstream, and
load-bearing for v4's reentrancy safety**. It will not change, and it cannot be worked around.

### Why this matters to Keel

`INFERENCE` The target hook class — vault-style wrappers that tokenise LP positions into
fungible claims — manages the LP position **from the hook contract**. Users deposit and withdraw
through the hook's own external functions (`deposit()`, `withdraw()`, …); the hook then calls
`poolManager.modifyLiquidity(...)` itself. Under `noSelfCall`, those calls fire **no** liquidity
callbacks on that hook.

`INFERENCE` Therefore **a guard implemented as v4 hook callbacks is structurally blind to the
exact operations that mint and burn shares.** `afterRemoveLiquidity` would not fire on a vault
withdrawal. This is not a bug to work around; it is the intended design (the comment at
`Hooks.sol:170` says so).

`INFERENCE` Consequences for the architecture, to be settled at the kill gate:

1. Keel cannot be a **passive observer hook** on someone else's pool. There is no v4 mechanism
   by which contract A observes contract B's hook callbacks.
2. Keel must be invoked **by the guarded hook itself** — a library, modifier, or base contract
   the hook calls at the end of its own state-changing functions.
3. That makes Keel **opt-in and cooperative**, not an external safety net. It protects a hook
   author from their own bugs; it cannot protect users from a hook author who declines to use it,
   or who removes the call.

`INFERENCE` This materially narrows the value proposition and **must be confronted at the
kill gate**, not glossed. It does not by itself kill the project — "a correctness harness the
hook author installs" is a real product category (`SafeERC20`, `ReentrancyGuard`) — but it is a
different and weaker claim than "a runtime safety layer for v4 hooks", and every artifact must
stop making the stronger claim. Recorded as `DECISIONS.md` D-0011.

`UNVERIFIED` Whether some real vault-style hooks route user deposits through
`PoolManager.modifyLiquidity` with the *user* as `msg.sender` (which would fire the callbacks
normally). See `docs/BUNNI_CASE_STUDY.md` for what Bunni actually did.

## 5. Hook permission flags and address validity

`FACT` `lib/v4-core/src/libraries/Hooks.sol:27-47` — flags live in the **low 14 bits of the hook
address**.

| Bit | Constant | Line |
|---|---|---|
| 13 | `BEFORE_INITIALIZE_FLAG` | 29 |
| 12 | `AFTER_INITIALIZE_FLAG` | 30 |
| 11 | `BEFORE_ADD_LIQUIDITY_FLAG` | 32 |
| 10 | `AFTER_ADD_LIQUIDITY_FLAG` | 33 |
| 9 | `BEFORE_REMOVE_LIQUIDITY_FLAG` | 35 |
| 8 | `AFTER_REMOVE_LIQUIDITY_FLAG` | 36 |
| 7 | `BEFORE_SWAP_FLAG` | 38 |
| 6 | `AFTER_SWAP_FLAG` | 39 |
| 5 | `BEFORE_DONATE_FLAG` | 41 |
| 4 | `AFTER_DONATE_FLAG` | 42 |
| 3 | `BEFORE_SWAP_RETURNS_DELTA_FLAG` | 44 |
| 2 | `AFTER_SWAP_RETURNS_DELTA_FLAG` | 45 |
| 1 | `AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG` | 46 |
| 0 | `AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG` | 47 |

`FACT` `ALL_HOOK_MASK = uint160((1 << 14) - 1)` (`Hooks.sol:27`).
`FACT` `hasPermission(self, flag) => uint160(address(self)) & flag != 0` (`Hooks.sol:337-339`).
`FACT` `validateHookPermissions` (`Hooks.sol:83-103`) requires the declared `Permissions` struct
to match the address bits **exactly**, reverting `HookAddressNotValid`. Called from a hook's
constructor.
`FACT` `isValidHookAddress` (`Hooks.sol:109-127`), called by `initialize` at
`PoolManager.sol:126`, additionally enforces that a `*_RETURNS_DELTA` flag requires its base
action flag (:111-120), and that a hook with no flags is only valid with a non-dynamic fee (:124-126).

`FACT` **A returns-delta flag has effect only through these two call sites:**
`PoolManager.sol:181` and `:224` — `if (hookDelta != ZERO_DELTA) _accountPoolBalanceDelta(...)`.
And `hookDelta` can only be non-zero if `callHookWithReturnDelta` was passed `parseReturn = true`,
which is exactly `self.hasPermission(<...>_RETURNS_DELTA_FLAG)` (`Hooks.sol:227, 239, 266, 301`).

`FACT` This confirms `SECURITY.md` §1 mechanically: **with address bits 0-3 clear, a hook
cannot alter accounting even if its callback code tried to** — the returned delta is never
parsed. The "observe and revert only" property is enforced by the protocol, not by our
discipline. This is the strongest single security property available to Keel and must be
asserted by test.

`FACT` **Proven, not merely reasoned.** `test_returnedDeltaIgnoredWhenFlagClear` has the mock
return a non-zero `afterSwap` delta of `1e12` from an address with `AFTER_SWAP_RETURNS_DELTA_FLAG`
clear. The callback runs (`afterSwapCount == 1`), yet the hook's balances of both currencies are
unchanged. The protocol discarded the delta. `test_returnsDeltaBitsAreClearOnHookAddress` asserts
all four bits are clear on the deployed address.

## 6. Delta types

`FACT` `lib/v4-core/src/types/BalanceDelta.sol:8` — `type BalanceDelta is int256`, two packed
`int128`s: upper = `amount0`, lower = `amount1`. Accessors `amount0()` (:61-65) and `amount1()`
(:67-71). `ZERO_DELTA` at :59. Sign convention: positive = the pool owes the caller.

`FACT` `lib/v4-core/src/types/BeforeSwapDelta.sol:6` — `type BeforeSwapDelta is int256`;
upper 128 bits = delta in **specified** token, lower = **unspecified**
(`getSpecifiedDelta` :25-29, `getUnspecifiedDelta` :33-37).

`FACT` `Hooks.sol:273-279` — a non-zero `hookDeltaSpecified` adjusts the swap amount and reverts
`HookDeltaExceedsSwapAmount` if it would flip exactInput/exactOutput.

## 7. What a guard can actually read

This determines which invariants are expressible at all (`THREAT_MODEL.md` U2).

`FACT` `lib/v4-core/src/libraries/StateLibrary.sol` — `extsload`-based reads of committed state:

| Function | Line |
|---|---|
| `getSlot0(manager, poolId) -> (sqrtPriceX96, tick, protocolFee, lpFee)` | 40 |
| `getLiquidity(manager, poolId) -> uint128` | 183 |
| `getPositionLiquidity(manager, poolId, positionId) -> uint128` | 279 |
| `getPositionInfo(manager, poolId, owner, tickLower, tickUpper, salt)` | 230 |
| `getFeeGrowthGlobals(manager, poolId)` | 157 |
| `getFeeGrowthInside(manager, poolId, tickLower, tickUpper)` | 298 |
| `getTickLiquidity`, `getTickInfo`, `getTickBitmap`, `getTickFeeGrowthOutside` | 108, 76, 201, 131 |

`FACT` `lib/v4-core/src/libraries/TransientStateLibrary.sol` — `exttload`-based reads of
in-flight state: `currencyDelta(manager, target, currency)` (:35), `getNonzeroDeltaCount` (:28),
`getSyncedReserves` (:18), `getSyncedCurrency` (:23), `isUnlocked` (:46).

`FACT` `lib/v4-core/src/types/Currency.sol` — `type Currency is address` (:7),
`balanceOf(currency, owner)` (:98), `balanceOfSelf` (:90). Native currency is address zero
(`isAddressZero` :106).

`FACT` `lib/v4-core/src/ERC6909Claims.sol:7` — the PoolManager *is* an ERC-6909; hooks can hold
tokenised claims on pool balances (`PoolManager.mint`/`burn`, `PoolManager.sol:322, 332`).
`FACT` `CurrencyLibrary.toId(currency)` is the 6909 id (`Currency.sol:110-113`).

`FACT` `test_stateLibraryReadsAreIndependentOfHook` reads `getLiquidity`, `getSlot0`, and
`getPositionLiquidity` for the vault's own position directly from PoolManager storage after a
hook-initiated liquidity change, and all three match — while the hook itself observed nothing.

`INFERENCE` A guard therefore has **three independent, non-hook-controlled** sources of truth:
pool position liquidity via `StateLibrary`, in-flight currency deltas via
`TransientStateLibrary`, and raw ERC-20/6909 balances. None of these is a number the guarded
hook merely asserts — which is precisely the property `THREAT_MODEL.md` §3 demanded. **This is
the strongest positive result of this sweep for the thesis.**

`UNVERIFIED` Whether these are *sufficient* to express a backing invariant, and how liquidity in
a tick range converts to a comparable asset quantity without invoking price (which an attacker
may control). To be settled at the kill gate.

## 8. Dynamic fees

`FACT` `lib/v4-core/src/libraries/LPFeeLibrary.sol`: `DYNAMIC_FEE_FLAG = 0x800000` (:15),
`OVERRIDE_FEE_FLAG = 0x400000` (:19), `REMOVE_OVERRIDE_MASK = 0xBFFFFF` (:22),
`MAX_LP_FEE = 1000000` (:25, = 100%). A pool is dynamic iff `key.fee == DYNAMIC_FEE_FLAG` exactly
(`isDynamicFee` :30). `FACT` The `beforeSwap` fee return is only read for dynamic-fee pools
(`Hooks.sol:263`).

`INFERENCE` The guard-hook design does not need dynamic fees. Recorded only so that nobody wires them
in speculatively.

## 9. `BaseHook` — confirmed absent

`FACT` `find lib -name 'BaseHook*.sol'` returns **nothing** across all six dependencies.
`FACT` `lib/v4-periphery/src/` contains `base/`, `hooks/permissionedPools/`, `interfaces/`,
`lens/`, `libraries/` — **there is no `utils/` directory**. `lib/v4-periphery/src/base/` holds
`BaseActionsRouter`, `BaseV4Quoter`, `DeltaResolver`, `ImmutableState`, `SafeCallback`,
`ReentrancyLock`, `Notifier`, and others — but no hook base contract.

`INFERENCE` The near-universal tutorial import
`import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol"` **does not compile at our pins**.
`DECISIONS.md` D-0005 remains open; the prior-art review assesses OpenZeppelin `uniswap-hooks`
before it can be considered as a dependency.

## 10. Unichain deployment — re-verified

`FACT` Re-verified live on 2026-08-28 at block **57148459** against
`https://mainnet.unichain.org` (`cast chain-id` → `130`):

| Check | Result |
|---|---|
| `cast code 0x1f98…0004` | 48103 hex chars — a real deployed contract |
| `PoolManager.owner()` | `0x2BAD8182C09F50c8318d769245beA52C32Be46CD` |
| `StateView(0x86e8…e8f2).poolManager()` | `0x1F98400000000000000000000000000000000004` |
| `PositionManager(0x4529…17bf).poolManager()` | `0x1F98400000000000000000000000000000000004` |

`FACT` **Three independent sources agree** on the PoolManager address (the deployments page plus
two unrelated deployed contracts). Full address table remains `docs/RECON.md` §6.

### Q7 closed — the PoolManager owner

`FACT` `cast code` on `0x2BAD…46CD` returns empty (3 chars, i.e. `0x`). It has **no code on
Unichain** at block 57148459; `getOwners()`, `getThreshold()`, `VERSION()` and `owner()` all
revert with "does not have any code".

`INFERENCE` It is an EOA, or an address whose contract is not deployed on this chain. Its
identity remains `UNVERIFIED`, but the **power** is now bounded and that is what the threat model
needed: `ProtocolFees.sol:29` `setProtocolFeeController` and `:35` `setProtocolFee`, with
`MAX_PROTOCOL_FEE = 1000` out of 1e6 — a **0.1% cap** on swap fees
(`lib/v4-core/src/libraries/ProtocolFeeLibrary.sol:8`, validated at `ProtocolFees.sol:37`).
The owner **cannot** touch pool principal, LP positions, or hook state. `RESEARCH.md` Q7 is
closed as a bounded, non-critical risk.

## 11. Corrections to earlier recon

`FACT` `docs/RECON.md` §5.2 listed IHooks line numbers and marked the return tuples
`UNVERIFIED`. They are now verified in §2 above. One line number in that earlier list was
approximate (`afterAddLiquidity` was given as 55; the declaration spans 55-62). §2 supersedes it.

## 12. Open questions carried to later phases

| # | Question | Phase |
|---|---|---|
| H1 | Does the target hook class route user deposits through the hook (callbacks suppressed by `noSelfCall`) or through `PoolManager` directly? | 3 |
| H2 | Given `noSelfCall`, is a cooperative library-style guard still worth building? | **4 kill gate** |
| H3 | Can position liquidity be converted to an asset quantity without trusting an attacker-movable price? | 4 |
| H4 | What does the hook inherit from, if `BaseHook` does not exist here? | 2 / 6 |
