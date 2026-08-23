# docs/BUNNI_CASE_STUDY.md — Phase 3

Researched 2026-08-28 from primary sources: the Bunni v2 source on GitHub, on-chain transaction
identifiers, and independent third-party post-mortems.

> **Bunni is the motivating case, not the specification.** Nothing in this file authorises a
> Bunni-specific detector. Its purpose is to answer one question: *could the violated property
> have been written down by someone who had never heard of Bunni?* The answer is in §7, and it
> is more nuanced than "yes".

**Reproduction status: `NOT REPRODUCED`.** No fork replay has been attempted at the time of
writing. Phase 8 will attempt one and must label the result `EXACT REPLAY`,
`FAITHFUL RECONSTRUCTION`, or `NOT REPRODUCED`. Nothing here may be described as a replay.

---

## 1. Incident facts

| Item | Value | Tag |
|---|---|---|
| Date | 2 September 2025 | `FACT` |
| Total loss | ~$8.4M — ~$2.4M Ethereum, ~$5.9–6.0M Unichain | `FACT` |
| Ethereum tx | `0x1c27c4d625429acfc0f97e466eda725fd09ebdc77550e529ba4cbdbc33beb97b` | `FACT` |
| Unichain tx | `0x4776f31156501dd456664cd3c91662ac8acc78358b9d4fd79337211eb6a1d451` | `FACT` |
| Ethereum block | 23273098 | `FACT` |
| Attacker | `0x657D8BcCDD9C6e1Da8DA1e7d331CFdeA8357AdBc` | `FACT` |
| BunniHub | `0x000000000049C7bcBCa294E63567b4D21EB765f1` | `FACT` |
| BunniHook | `0x000052423c1dB6B7ff8641b85A7eEfc7B2791888` | `FACT` |
| Ethereum pool | USDC/USDT | `FACT` |
| Unichain pool | weETH/ETH | `FACT` |
| Audited by | **Pashov Audit Group, Trail of Bits, and Cyfrin** | `FACT` |
| Outcome | Protocol permanently shut down | `FACT` |

`FACT` The brief said "audited by two reputable firms". It was **three**. Corrected here.

`FACT` The vulnerable line is **still present on `main`** as of this session. The last functional
commit to `src/lib/BunniHubLogic.sol` was `4c017494c4` (2025-06-01), three months *before* the
exploit; the only later commit is `2b303b8c1b` (2025-10-23) "update license to MIT, update
readme". **There is no fix commit** — the protocol shut down instead. So there is no corrected
implementation to compare against.

Sources: [Coinspect Learn EVM Attacks](https://www.coinspect.com/learn-evm-attacks/cases/bunni/),
[QuillAudits](https://www.quillaudits.com/blog/hack-analysis/bunni-v2-exploit),
[Halborn](https://www.halborn.com/blog/post/explained-the-bunni-hack-september-2025),
[Verichains](https://blog.verichains.io/p/bunnixyz-vulnerability-exposed-how),
[Bunni v2 source](https://github.com/Bunniapp/bunni-v2),
[Pashov audit](https://github.com/pashov/audits/blob/master/team/md/Bunni-security-review-August.md).
All fetched 2026-08-28.

## 2. Architecture — and why it matters more than the bug

`FACT` Read from source at `Bunniapp/bunni-v2@main`:

- **`BunniHub`** is the contract LPs interact with. It holds reserves, mints and burns share
  tokens (`state.bunniToken`), and implements `deposit()` / `withdraw()`.
- **`BunniHook`** is the Uniswap v4 hook. It implements exactly **two** callbacks —
  `afterInitialize` (`BunniHook.sol:514`) and `beforeSwap` (`:525`), the latter returning a
  `BeforeSwapDelta` (`:559`). It implements **no liquidity callbacks at all**.
- `FACT` `grep -c modifyLiquidity src/lib/BunniHubLogic.sol` → **0**. Bunni holds **no Uniswap v4
  LP positions whatsoever.** Liquidity is virtual: the Liquidity Distribution Function (LDF)
  computes a distribution, and `beforeSwap` + `BeforeSwapDelta` takes over swap execution as a
  custom curve.
- `FACT` Bunni ships its **own** 30-line `BaseHook` abstract contract
  (`src/base/BaseHook.sol`), declaring only those two callbacks. Independent corroboration of
  `docs/RECON-hooks.md` §9: there is no canonical `BaseHook` to inherit.
- `FACT` Bunni's `BaseHook` imports `IPoolManager.SwapParams` — the pre-`PoolOperation.sol`
  spelling. It was built against an older v4 than our pins, corroborating `docs/RECON.md` §6.2.

`FACT` **The exploited function, `BunniHubLogic.withdraw()`, is not a Uniswap v4 hook callback.**
It is an ordinary external function on a separate contract.

`INFERENCE` This is decisive confirmation of `DECISIONS.md` D-0011, from the motivating case
itself: **a guard implemented as v4 hook callbacks could not have seen this exploit.** Bunni has
no liquidity callbacks to hook, and the share burn happens in a contract the PoolManager never
calls. Keel must be a cooperative library invoked inside the protocol's own `withdraw()`. This
closes `docs/RECON-hooks.md` question **H1**.

`INFERENCE` It also **invalidates part of the Phase 1 optimism.** `docs/RECON-hooks.md` §7
celebrated `StateLibrary.getPositionLiquidity` as a non-forgeable source of truth. For this hook
class it is **useless** — there is no position. The assets are ERC-20 balances held by the Hub
plus shares in external yield vaults. Only two of the three "non-forgeable sources" survive, and
the vault-reserve component is valued through an external call.

## 3. The bug

`FACT` `src/lib/BunniHubLogic.sol:475-482`, `withdraw()`:

```solidity
// decrease idle balance proportionally to the amount removed
{
    (uint256 balance, bool isToken0) = IdleBalanceLibrary.fromIdleBalance(state.idleBalance);
    uint256 newBalance = balance - balance.mulDiv(shares, currentTotalSupply);
    if (newBalance != balance) {
        s.idleBalance[poolId] = newBalance.toIdleBalance(isToken0);
    }
}
```

`FACT` `mulDiv` rounds **down**. So the amount subtracted from `balance` is rounded down, and
therefore `newBalance` — the *retained* idle balance — is rounded **up**.

`FACT` The surrounding withdrawal amounts round the other way (`BunniHubLogic.sol:462-467`):

```solidity
uint256 reserveAmount0 = getReservesInUnderlying(state.reserve0.mulDiv(shares, currentTotalSupply), state.vault0);
uint256 rawAmount0     = state.rawBalance0.mulDiv(shares, currentTotalSupply);
```

Also rounding down — correctly, in the protocol's favour: the withdrawer receives slightly less.

`FACT` The corresponding `deposit()` path uses `mulDivUp` (`BunniHubLogic.sol:214-215`). The
rounding direction of the idle balance is **asymmetric between deposit and withdraw**.

### Why rounding "in the protocol's favour" was the bug

`INFERENCE` Bunni's reserves decompose as `total = active + idle`, where **active** is the
portion the LDF deploys into the curve and **idle** is held back. Writing `f = shares / totalSupply`:

- `total` decreases by `floor(total · f)` → `total_new ≥ total·(1−f)` → **total per share rises.** Safe.
- `idle` decreases by `floor(idle · f)` → `idle_new ≥ idle·(1−f)` → **idle per share rises.**
- `active = total − idle`, so `active_new ≈ active·(1−f) + ε₁ − ε₂` with `ε₁, ε₂ ∈ [0,1)`.
  **When `ε₂ > ε₁`, active per share FALLS.**

Each individual error is at most ~1 wei. It became catastrophic only because the attacker first
drove the active balance to **28 wei**, at which point a 1-wei error is ~3.5% of the whole active
balance — and then repeated it.

`INFERENCE` The developers reasoned about rounding **component-wise** — "round down, the protocol
keeps more" — which is correct for `total` and for `idle` in isolation. It is wrong for the
**derived** quantity `active = total − idle`, where rounding one operand up and the other down
compounds in the same direction. Rounding safety is not compositional under subtraction. That is
the transferable lesson, and it is not Bunni-specific.

## 4. The attack sequence

`FACT` Per Coinspect's reconstruction of the Ethereum transaction:

1. **Flash loan** — 3M USDT from the Uniswap v3 USDT pool `0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36`.
2. **Three priming swaps** — USDT→USDC→USDT→USDC, pushing the pool's **active USDC balance down
   to 28 wei**. This is the amplifier: it makes a 1-wei rounding error economically enormous.
3. **44 withdrawals** — each compounding the rounding error. Total liquidity fell from
   `5.83e16` to `9.114e15` — an **84.4% reduction** — while only a small fraction of shares was
   burned.
4. **Extreme swap** — 10 quintillion USDT for 1 wei USDC, moving the pool to tick **839,189**.
   The corrupted liquidity made this cheap.
5. **Reverse swap at the manipulated price** — ~1.33M USDC + ~1M USDT extracted; flash loan repaid.

### Does the rounding model reproduce the observed numbers?

`INFERENCE` A first-order check, as a sanity test on the mechanism described in §3. If each
withdrawal costs the active balance ~1 wei beyond its proportional share, and the active balance
was driven to 28 wei, then the per-iteration loss is `1/28 = 3.57%`, and after 44 iterations
`(1 - 1/28)^44 = 20.2%` of active liquidity would remain — a **79.8% reduction**.

`FACT` The reported collapse was `5.83e16 → 9.114e15`, i.e. **15.6% remaining, an 84.4%
reduction**.

`INFERENCE` The model lands within ~5 percentage points of the observed figure using only two
reported constants and no fitting. That is good corroboration that §3 identifies the right
mechanism. It is **not** a reproduction: the real dynamics involve the LDF recomputing the
distribution between withdrawals, and the active balance changing each iteration. Treated as a
consistency check only. Phase 8 owns any actual reproduction.

`INFERENCE` The profit came from **step 5**, not from over-withdrawal in step 3. Steps 2–3
corrupted the accounting; step 4–5 monetised it. A guard therefore has to fire during **step 3**,
on the withdrawal path — by step 4 the state is already invalid and the swap itself is legitimate
given that state. This is important for Phase 6: watching swaps would be too late.

## 5. The ten questions

**1. What assumption was supposed to hold?**
`INFERENCE` That reducing `idle` proportionally on withdrawal keeps the active/idle split
proportional, so that each remaining share is backed by the same active liquidity as before.

**2. What state actually changed?**
`FACT` `s.idleBalance[poolId]` retained more than its proportional share; total liquidity fell
`5.83e16 → 9.114e15`.

**3. How did the attacker cause it?**
`FACT` Priming swaps to drive active balance to 28 wei, then 44 repeated small withdrawals.

**4. Economic consequence?**
`FACT` ~$8.4M extracted; remaining LPs left with a pool whose shares were no longer backed.

**5. What property was violated?**
`INFERENCE` **Per-share backing monotonicity on redemption, applied to the *active* reserve
component.** Formally, with `A` = active backing and `S` = share supply, a withdrawal must satisfy
`A' / S' ≥ A / S`. Bunni's withdraw drove `A/S` down.
**Critically, the property was NOT violated for total reserves** — `total/S` actually *increased*.

**6. Was the property known before the exploit?**
`FACT` Yes in its general form. "Share price must not decrease on redeem" is the canonical
ERC-4626 invariant, documented since 2022 and present in every standard vault property-test
suite.

**7. Could someone formulate it without knowing the Bunni exploit?** — **the decisive question**

`INFERENCE` **Partially, and this is the project's central tension. Answering "yes" without
qualification would be dishonest.**

- The *naive* form — `totalAssets / totalSupply` non-decreasing on redeem — is completely
  standard, needs no hindsight, and **would NOT have caught Bunni.** Bunni's total-per-share went
  *up*. A guard enforcing the textbook 4626 invariant would have passed all 44 withdrawals.
- The form that *would* have caught it — per-share monotonicity of **each reserve component**,
  including derived ones like `active = total − idle` — is a genuine a-priori generalisation:
  *"if you decompose reserves, per-share value of every component you decompose into must be
  non-decreasing on redeem, because rounding safety is not compositional under subtraction."*
  That is statable by someone who never heard of Bunni.
- **But** a *generic* library cannot enumerate a protocol's components. It cannot know Bunni has
  an active/idle split. The hook author must declare the components.

`INFERENCE` This is survivable but it reshapes the product: Keel cannot be "install this and be
safe". It can at most be "declare what backs your shares, including each component, and this
enforces monotonicity on every path". The value moves from *detection* toward *forcing the author
to state the decomposition* — which is arguably where the bug actually was, since the developers
never wrote down what `active` was supposed to satisfy. **Phase 4 must decide whether that
residual value justifies the project.** It is a materially weaker claim than the brief assumed.

**8. Is the property generic across a defined hook class?**
`INFERENCE` Per-share monotonicity is generic for any share-issuing vault. The *component
decomposition* is not generic — it must be supplied per protocol.

**9. Can it be checked deterministically at runtime?**
`INFERENCE` Yes, cheaply, **if** the protocol exposes its components: snapshot `(componentᵢ, S)`
before, compare after, require `Aᵢ'·S ≥ Aᵢ·S'` (cross-multiplied, no division). No price oracle
and no external call needed if components are token balances. Vault-backed components require an
external call, which is a reentrancy and manipulation surface. Phase 4 must resolve this.

**10. Could checking it create false positives?**
`INFERENCE` **Yes, and this is the primary risk.** Known legitimate cases where per-share backing
falls: fee-on-transfer tokens; a lossy external yield vault; rebalancing that legitimately shifts
value between components; a rebasing token contracting; the first depositor; and — for a
*component* invariant — any deliberate rebalance between active and idle, **which for Bunni is the
LDF's entire purpose.** That last one is severe: Bunni's rebalancer legitimately moves value
between active and idle on every swap. A naive component-monotonicity check would fire constantly.
Phase 4 must separate "withdrawal path" from "rebalance path", or the guard is unusable.

## 6. What Keel must NOT conclude from this

- Do not check `idleBalance`. That is a Bunni field.
- Do not check "44 withdrawals in one transaction". That is a signature, not an invariant.
- Do not assume assets are v4 position liquidity. For this class they are **not**.
- Do not claim the textbook ERC-4626 invariant would have prevented this. **It would not have.**

## 7. Carried into Phase 4

| # | Question |
|---|---|
| B1 | Can a component decomposition be declared by the author without the API becoming so protocol-specific that Keel is just a naming convention? |
| B2 | How is the withdrawal path distinguished from a legitimate rebalance path, given rebalancing is exactly what moves value between components? |
| B3 | Do external-vault-valued components force an external call, and does that create a worse attack surface than it closes? |
| B4 | Given the textbook invariant would not have caught the motivating case, what is Keel's honest claim? |
