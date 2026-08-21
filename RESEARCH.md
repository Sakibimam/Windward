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

> **This is the motivating case, NOT the specification.** Do not build a Bunni detector. Build
> against the *property class*. If Phase 3 concludes the property could not have been written by
> someone who had never heard of Bunni, that is a kill signal — see `PROJECT.md`.

`UNVERIFIED` — everything in this section. It is the brief's framing as given by the product
owner and has **not** been checked against primary sources this session. Phase 3 must establish
each of these from primary sources (post-mortems, on-chain transactions, the protocol's own
disclosure) or discard them.

- `UNVERIFIED` Date: September 2025.
- `UNVERIFIED` Loss: approximately $8.4M, split across Ethereum and Unichain.
- `UNVERIFIED` Mechanism: a rounding-direction flaw in withdrawal logic, compounded through
  repeated withdrawals to corrupt the pool's liquidity accounting, then exploited via a swap
  against the corrupted state.
- `UNVERIFIED` Bunni had been audited by two reputable firms and shut down afterwards.

**Phase 3's decisive question**, to be answered honestly:

> Could the violated economic property have been written down by someone who had never heard of
> Bunni?

If the honest answer is **no**, recommend killing. A property that can only be stated in
hindsight is a detector, not an invariant.

### What Phase 3 must produce

1. Primary-source citations (URL + date) for the incident, replacing every `UNVERIFIED` above.
2. A statement of the **economic property** that was violated, expressed without reference to
   Bunni's specific code.
3. An explicit answer to the decisive question, with reasoning.
4. Transaction hashes and block numbers, if a Phase 8 fork reproduction is to be attempted.

---

## 2. Prior art — status: NOT YET RESEARCHED

`UNVERIFIED` Phase 2 must search exhaustively and classify each finding as: *already solved /
partially solved / research only / solved off-chain / solved elsewhere / genuinely open.*

Known leads to investigate, recorded so Phase 2 does not have to rediscover them:

- **ERC-7265** (Circuit Breaker, proposed 2023) and its descendants. Already established as
  covering the "rate-limit withdrawals" idea — that is *why* that idea was rejected in
  `DECISIONS.md` D-0002. Phase 2 must determine whether it also covers backing/solvency.
- **OpenZeppelin `uniswap-hooks`** — `FACT` exists, latest release tag `v1.2.1` at
  `acbd604c409a827f7f98c9517236da860c4fca1a`, verified by live `git ls-remote` on 2026-08-28
  (`docs/RECON.md` §4.1). Whether it contains anything resembling a solvency guard is
  `UNVERIFIED`.
- **ERC-4626** and its accounting conventions. The share/asset relationship Keel wants to
  enforce is the same shape as 4626's. `UNVERIFIED` whether existing 4626 invariant libraries
  transfer to the v4 hook setting.
- v4-specific hook security libraries, runtime invariant enforcement, and solvency guards
  generally. `UNVERIFIED`.

**If something already does this well, say so and recommend killing.**

---

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
