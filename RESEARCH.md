# RESEARCH.md — Keel

Every substantive claim in this file carries a tag. **Never silently promote a tag.**

| Tag | Meaning |
|---|---|
| `FACT` | Verified this session from source on disk, a live query, or official documentation. Source and date recorded. |
| `INFERENCE` | Reasoned from verified evidence. The reasoning is stated so it can be attacked. |
| `HYPOTHESIS` | Currently being tested. Not yet evidence for anything. |
| `UNVERIFIED` | Not checked. **May not be relied on.** Never write a value here that was guessed. |

Research phases 1–4 append to this file. Phase 0 established only what is below.

---

## 1. Motivating case study — the Bunni exploit

**Phase 3 complete.** Full analysis with primary sources: **`docs/BUNNI_CASE_STUDY.md`**.
Everything previously tagged `UNVERIFIED` here has been sourced or corrected:

- `FACT` 2 September 2025; ~$8.4M (~$2.4M Ethereum, ~$5.9-6.0M Unichain).
- `FACT` Root cause: a rounding-direction bug at `BunniHubLogic.sol:478`,
  `newBalance = balance - balance.mulDiv(shares, currentTotalSupply)` — `mulDiv` rounds down, so
  the *retained* idle balance rounds up.
- `FACT` Audited by **three** firms (Pashov, Trail of Bits, Cyfrin), not two as the brief stated.
- `FACT` **Never patched.** No fix commit exists; the protocol shut down instead.
- `FACT` `BunniHub.withdraw()` is **not a v4 hook callback**; BunniHook implements only
  `afterInitialize` and `beforeSwap`, and Bunni holds **no v4 LP positions at all**
  (`modifyLiquidity` appears 0 times in `BunniHubLogic.sol`).

**Two findings that cut against the thesis and must be confronted at the Phase 4 gate:**

1. `INFERENCE` **The textbook ERC-4626 invariant would NOT have caught Bunni.** Total assets per
   share *increased* through the attack. What collapsed was the *active* component of a
   decomposed reserve (`active = total - idle`). Rounding safety is not compositional under
   subtraction.
2. `INFERENCE` The invariant that would have caught it needs the protocol's **component
   decomposition**, which a generic library cannot know. The author must declare it. Keel's
   honest claim shrinks from "install this and be safe" to "declare what backs your shares, and
   this enforces monotonicity on every path".

`INFERENCE` Q2 answered **partially yes**: the general principle is a-priori statable, but the
naive version is useless and the useful version needs author-supplied structure. Not a kill on
its own; a material weakening. See `docs/BUNNI_CASE_STUDY.md` §5 Q7.

## 2. Prior art — Phase 2 COMPLETE. Outcome: **redundant**.

Full review by `research-reviewer`, 2026-08-28. Its three load-bearing claims were then
**independently re-verified** by the main session against primary sources.

### Verified by direct source reading (not taken on the agent's word)

- `FACT` **OpenZeppelin `uniswap-hooks` v1.2.1 ships `src/base/BaseCustomAccounting.sol`** —
  natspec: *"Base implementation for custom accounting and hook-owned liquidity."* This is
  literally Keel's target class, from the most authoritative source, funded by a Uniswap
  Foundation grant. It has **no backing, solvency, or share-price invariant**: the only reverts
  in 443 lines are `ExpiredPastDeadline`, `PoolNotInitialized`, `InvalidNativeValue`,
  `TooMuchSlippage`, `AlreadyInitialized`, and `LiquidityOnlyViaHook`.
- `FACT` **The repo contains no `test/invariant/` directory at all** (full recursive git-tree
  read at `acbd604c…`, `truncated: false`; 54 `.sol` files). Zero invariant tests for anything.
  *(The agent reported an invariant suite covering `LimitOrderHook`; that is wrong — there is
  none. Corrected here.)*
- `FACT` `BaseCustomAccounting.sol:329-349` **reverts `LiquidityOnlyViaHook()`** when liquidity
  is added or removed via the `PoolManager`. It *forces* all liquidity through the hook, so the
  hook is always `msg.sender` to the PoolManager. **This is independent confirmation from the
  canonical library that D-0011's `noSelfCall` blindness governs the real target class.**
- `FACT` **`BaseHook.sol` exists — in `uniswap-hooks`, not v4-periphery.** This **closes D-0005
  and `docs/RECON-hooks.md` H4.**
- `FACT` **Trail of Bits, "Building secure Uniswap v4 hooks", published 2026-07-30** — five weeks
  ago. Failure pattern #3 is *"Custom accounting leaks value"*; it names the Bunni exploit
  ($8.4M, September 2025, idle-balance rounding) and prescribes three invariants to test,
  including *"Internal accounting matches actual asset balances."* It ships **prose and
  checklists only — no runtime code and no library.**

### Classification summary

| # | Finding | Class | Gap it leaves |
|---|---|---|---|
| F-1 | ERC-7265 Circuit Breaker | PARTIALLY SOLVED | No share/backing concept; outflow rate only. `FACT` PR #7265 **closed unmerged 2023-10-25**; 404 on `ercs.ethereum.org`. Never finalised — D-0002's "established standard" framing was too strong. |
| F-2 | OZ `uniswap-hooks` `BaseCustomAccounting` | PARTIALLY SOLVED | **Ships the substrate with no guard and no invariant tests. Keel's strongest remaining opening.** |
| F-3 | Trail of Bits v4 hook guide (2026-07-30) | PARTIALLY SOLVED (test time) | Prose only, no code — but it **publishes the invariant**, damaging novelty of merely stating it. |
| F-4 | Euler **Ethereum Vault Connector** | PARTIALLY SOLVED / SOLVED ELSEWHERE | **Closest architectural prior art.** Deployed, audited, generic cooperative `checkVaultStatus()` with deferral across batches — exactly D-0011's category, already solved. Defines no invariant *content*. |
| F-5 | **Phylax Credible Layer** | **ALREADY SOLVED** where available | Solidity assertions enforced by the sequencer; sees whole-transaction state diffs, so it **defeats `noSelfCall` entirely**, costs zero gas, needs no author cooperation. Confirmed on Linea; **no evidence of Unichain**. |
| F-6 | Ironblocks / Venn on-chain firewall | PARTIALLY SOLVED | `BalanceChangePolicy` is an absolute-magnitude cap; no ratio/share concept. |
| F-7 | Cube3, Forta Firewall | SOLVED OFF-CHAIN | Heuristic risk scores; introduce a third party who can freeze withdrawals. |
| F-8 | Hypernative, Hexagate, Chaos Labs, Gauntlet, OZ Defender | SOLVED OFF-CHAIN | Not synchronous. Keel's synchronicity claim survives this category. |
| F-9 | Certora "Proving Solvency in Uniswap v4" | SOLVED ELSEWHERE | Proves **v4-core** solvency; explicitly excludes hook accounting. |
| F-10 | a16z `erc4626-tests`, `crytic/properties` (37 ERC-4626 properties), Foundry/Echidna/Medusa/Halmos | **SOLVED AT TEST TIME** | The share↔asset property already ships as reusable code for the vanilla 4626 shape. **Nothing for v4 custom accounting.** |
| F-11 | Trace2Inv (FSE'24) | RESEARCH ONLY | Best evidence the category *works* (23/27 exploits blocked, 0.28% FP) — and that nobody productised it in two years. |
| F-13 | Balancer v3 `MIN/MAX_INVARIANT_RATIO` | SOLVED ELSEWHERE | Same shape, live since 2024, in another AMM. |
| F-14 | ERC-4626 conventions / OZ inflation-attack defence | SOLVED ELSEWHERE | Different failure mode; **does not transfer** — see Q4 below. |

### Market evidence — the market-need kill condition

- `FACT` `Uniswap/hooklist` (Uniswap's own registry) lists ~100 hooks across chainIds 42161,
  43114, 8453. **Ethereum mainnet and Unichain do not appear. Not one entry self-describes as a
  tokenised-LP-share vault.** Registry is voluntary, so this is a lower bound, not a census.
- `FACT` Bunni — the archetype — DefiLlama TVL **$231,564**, and it is **shut down**.
- `INFERENCE` Live v4 hooks minting fungible claims against pool liquidity: **effectively zero to
  three, and the flagship member is dead.**

### The materially simpler solution

`INFERENCE` For any hook on OZ `BaseCustomAccounting`, all of Keel reduces to snapshotting
`(assets, totalSupply)` and asserting `assetsAfter * supplyBefore >= assetsBefore * supplyAfter`
— five lines, no dependency, more auditable than an import, and free to run in CI as an
Echidna/Medusa property. The genuinely hard part (Q4) is not made easier by packaging it.

### Bottom line

> **Keel-as-runtime-guard is redundant.** Every layer exists and is deployed — the invariant
> (ToB, F-3), the cooperative opt-in harness (EVC, F-4), gasless synchronous enforcement
> (Phylax, F-5), reusable share/asset property code (F-10), the on-chain balance modifier
> (F-6) — and `noSelfCall` (D-0011) already reduced Keel to something the author must
> voluntarily install, i.e. something they could type themselves. And the hook class is empty.

## 3. Uniswap v4 protocol facts

`FACT` All v4 API facts verified so far live in `docs/RECON.md` §6, each with file path and line
number at the pinned commit. They are not duplicated here.

Highlights that shape the design:

- `FACT` Hook permission flags occupy the low 14 bits of the hook address
  (`Hooks.ALL_HOOK_MASK = (1 << 14) - 1`). `docs/RECON.md` §6.1.
- `INFERENCE` Keel's observe-and-revert-only property is enforceable as a property of the
  deployed **address**: the four `*_RETURNS_DELTA_FLAG` bits (bits 0–3) must be clear. This is
  testable, not just documented. Phase 6 must assert it.
- `FACT` Swap parameters are a type named `SwapParams` from
  `@uniswap/v4-core/src/types/PoolOperation.sol` at our pins — **not** `IPoolManager.SwapParams`.
  Older code and training data get this wrong.
- `FACT` `BaseHook.sol` does **not** exist in v4-periphery at our pin. Any import from
  `v4-periphery/src/utils/BaseHook.sol` is wrong here. See `DECISIONS.md` D-0005.
- `UNVERIFIED` Exact return tuples of `beforeSwap` / `afterSwap` / liquidity callbacks, and the
  fee-override encoding. **Phase 1** work. Do not write hook code before it is done.

---

## 4. Open research questions carried into later phases

| # | Question | Phase | Status |
|---|---|---|---|
| Q1 | Does a generic backing invariant exist for the share-like-claim hook class? | 4 | `HYPOTHESIS` |
| Q2 | Could the Bunni property have been stated a priori? | 3 | open |
| Q3 | Is this redundant with ERC-7265, OZ `uniswap-hooks`, or an existing product? | 2 | open |
| Q4 | What exactly counts as "assets" when the hook's liquidity sits inside the PoolManager? | 4 | open |
| Q5 | How do fees, donations, rebasing tokens, fee-on-transfer tokens, external yield, and custom curves each perturb the claims↔assets relationship? | 4 | open |
| Q6 | Can false positives be driven near zero? A guard that freezes withdrawals is worse than the bug it prevents. | 4, 7 | open |
| Q7 | Who is `0x2BAD8182C09F50c8318d769245beA52C32Be46CD` (the Unichain PoolManager owner)? Matters for the threat model. | 1 | `UNVERIFIED` |
| Q8 | Is `https://mainnet.unichain.org` usable for a full fork test suite, and is Ethereum archive access needed for Phase 8? | 8 | partly open — see `docs/RECON.md` §3.3 |
