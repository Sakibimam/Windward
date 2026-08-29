# THREAT_MODEL.md — Windward

**Rewritten 2026-08-28.** The previous version enumerated V1–V20 against Keel, a runtime
accounting guard that no longer exists. Those vectors do not apply to a fee-setting hook and
were misleading readers into checking the wrong properties.

`SECURITY.md` holds the policy; this file holds the analysis.

---

## 1. Assets

| # | Asset | Loss looks like |
|---|---|---|
| A1 | LP fee revenue | The fee sits below what the pool's risk warrants, or the pool is drained of flow. |
| A2 | **Pool usability** | The fee is driven high enough that honest swappers route elsewhere. **This is the dominant harm.** |
| A3 | Swapper funds in flight | Not reachable — Windward cannot move tokens (`SECURITY.md` §2). |
| A4 | The integrity of the study's numbers | A false statistic shipped as a `FACT`. Three such errors already occurred (D-0017). |

## 2. Attackers

| # | Attacker | Capability | Goal |
|---|---|---|---|
| T1 | Fee suppressor | Trades to push the estimate down, then trades large at the floor | Underpay LPs |
| T2 | Fee inflater / griefer | Trades to push the estimate up | Make the pool uncompetitive; deny LPs flow (A2) |
| T3 | Ordinary whale | One large legitimate swap | No malice — but can inflict T2's effect by accident |
| T4 | **Us** | Time pressure, unverified assumptions, uncommitted analysis scripts | A4. Empirically the most active threat in this project. |

## 3. Vectors

### Closed, each pinned by a regression test in `test/WindwardAttack.t.sol`

| # | Vector | Was | Now |
|---|---|---|---|
| V1 | **Dust-swap fee suppression** (T1). Decay ran per observation, so N no-move swaps multiplied the estimate by (1−α)^N. | 30 dust swaps in one block: fee **10000 → 500**, a 20× suppression, for gas. Same transaction as the trade it defeated. | Decay is by elapsed time; `dt == 0` is an identity. Same-block swaps cannot move the fee at all. |
| V2 | **Ceiling pinned indefinitely** (T2/T3). No time decay existed. | One ordinary swap pinned the pool at 1% and it was **still there seven days later**. | **PARTIALLY closed.** `Volatility.update` decays on elapsed time, so the ceiling releases *once a trade occurs*. It does **not** release without one — see H-1 below. The earlier wording here ("releases with no trading required") was false and is retracted. |
| V3 | **Same-block slicing to hide a move** (T1). | — | The anchor does not advance on `dt == 0`, so a sliced move is measured in full at the next timestamped observation. |
| V4 | **Silent mis-deployment** (F-1). Only the returns-delta bits were checked. | Missing `BEFORE_SWAP_FLAG` → a dynamic-fee pool falls back to `slot0.lpFee` = 0 → **every swap fee-free forever, silently**. An extra action flag → every `modifyLiquidity` reverts, bricking the pool permanently. | `Hooks.validateHookPermissions` with the full 14-flag set, in the constructor. |
| V5 | **Exact-output DoS** (W-06). | `feeMax == MAX_LP_FEE` → `Pool.sol` reverts `InvalidFeeForExactOut` on every exact-output swap — the Universal Router's retail path. | Constructor rejects `feeMax >= MAX_LP_FEE`. |
| V6 | **Signal destroyed by truncation** (W-03). | `sq/dt` then `sqrt(var/WAD)` truncated twice. Measured over 426,807 real swaps: **44.9–79.6%** of observations rounded to zero and the fee sat at its floor on **20.6–79.5%** of swaps. (An earlier 50-minute sample gave 52–85% / 80–96%; superseded by D-0020.) | WAD scaling is carried through; resolution is 1 pip. |
| V7 | Unbounded `feePerSigma` → overflow panic on the swap path (W-07). | Unvalidated. | Bounded in the constructor. |

### Open — accepted, not fixed

| # | Vector | Why accepted |
|---|---|---|
| V8 | **The tick is steerable.** Anyone can raise a pool's fee by trading it. | Irreducible: the signal *is* the price. Bounded by `MAX_OBSERVATION` (now 1e8, previously an inert 1e12) and by time decay. The attacker pays their own price impact. **Not eliminated.** |
| V9 | **The fee is set from pre-swap state.** The trader who moves the price pays the old fee; the next trader pays the elevated one. | Unfixable without predicting the move before it happens. Shared by every reactive dynamic fee. Stated plainly in `SECURITY.md` §5 rather than hidden. |
| V10 | **The estimator conflates transient and permanent impact.** LVR depends on the permanent component; realised pool variance also contains noise-trader impact, which LPs profit from. | Not resolved. It is the core open economic objection (D-0019) and the reason the LP-benefit claim is labelled unvalidated. |
| V11 | v4 stores the post-swap tick off by one in a direction-dependent way (`Pool.sol:409-412, :431`), so a round trip can register a spurious ±1 tick. | Bounded and small after the W-03 fix, but real on a 1-second-block chain. Not corrected. |
| V12 | Gas overhead per swap (one `extsload`, two SSTOREs, one `sqrt`, one event, and the decay-on-read added for H-1). | **Measured: 12,221 gas, 17% of the harness's 71,259-gas unhooked swap** (`test/WindwardGas.t.sol`, interleaved 5-run average on warm storage, written to `data/gas_overhead.json`). No longer open. |

### Process vectors

| # | Vector | Status |
|---|---|---|
| V13 | Analysis code not committed → statistics unreproducible and uncheckable. | **Occurred, three times** (D-0017). Closed: `analysis/` is committed, one command reproduces every number, and `analysis/test_decode.py` plus `test/SwapEventConvention.t.sol` pin the two specific decode bugs. |
| V14 | A comment asserting a security property the code does not have. | **Occurred, three times** — `MIN_DT`, `MAX_OBSERVATION`, and the `sqrt` convergence argument. All three rewritten. Reviewers relied on them. |
| V15 | A tautological test presented as evidence. | **Occurred.** Relabelled `test_sanity_higherFeeOnIdenticalVolumeCollectsMoreFees`, with a comment stating it proves `10000 > 500`. |

## 4. Explicitly accepted risks

- **R1 — Not audited.** Hackathon prototype. Must not secure real funds.
- **R2 — The economic claim is unvalidated.** Windward may not improve LP outcomes at all. See
  D-0019 for exactly what evidence is missing.
- **R3 — `feePerSigma` has no derivation.** It is a free parameter chosen by the deployer, and a
  bad choice is unrecoverable because the contract is immutable.
- **R4 — Uniswap v4 core is trusted.** Not audited by us.
- **R5 — The study samples a public RPC.** Rate limits and endpoint behaviour could bias
  collection; `analysis/fetch.py` caches per chunk and pins the end block so a run is
  reproducible, but the underlying node is trusted.

## 5. What would change the picture

An LP-PnL comparison with an explicit demand-elasticity assumption, and a decomposition showing
the fee tracks the permanent rather than the transient component of price impact. Until then V10
stands and the honest description of Windward is a heuristic with an unvalidated benefit.

---

## 6. Findings from the 2026-08-29 review

Both were confirmed by probe test before any fix, and are pinned by
`test/WindwardOpenFindings.t.sol`.

**Status: H-1 is FIXED in source. C-1 is OPEN and accepted.**

> **Redeployed 2026-08-30 with the H-1 fix: `0x609634584d5BD12Ba4216116528e364d385Ad0C0`**
> (Unichain Sepolia, block 61265509). Its runtime code was compared byte-for-byte against a local
> `FOUNDRY_PROFILE=deploy` build: the only differences are the five `immutable` slots, each then
> confirmed by calling its getter. The earlier `0x7FEe…10c0` predates the fix, still contains
> H-1, is immutable, and **must not be cited**. See `docs/DEPLOYMENT.md`.

### H-1 (High) — the charged fee was read from undecayed state — **FIXED**

`beforeSwap` and `currentFee` read `varianceWad` raw. Decay is applied only inside `afterSwap`,
i.e. **after** the fee has been charged. Measured: a pool driven to the 1% ceiling still quotes
**10000 pips after 1 hour and after 7 days** of no trading; the fee drops to the floor only
*after* the next trade has paid the un-decayed rate.

Consequence: up to a **20x overcharge on the first swap following any quiet period**, and a
self-reinforcing pin — a high fee deters flow, no flow means no decay. It cannot move funds
(returns-delta bits are clear) but it is exactly the harm `SECURITY.md` names as dominant: a fee
high enough to price honest flow out of the pool.

**Fixed** by `WindwardHook._varianceNow`: `beforeSwap`, `currentFee` and `currentSigmaWad` decay
the stored estimate forward to `block.timestamp` before pricing. It is a pure read — nothing is
written, so the update path and the `dt == 0` anchor semantics are untouched, and `beforeSwap`
stays `view`. Cost: one extra `decayFactor` evaluation per swap. Total overhead after the fix is
**12,221 gas**, from `data/gas_overhead.json` (written by `test/WindwardGas.t.sol`).

Regression tests: `test_H1_feeDecaysWithElapsedTimeAlone` and `test_H1_currentFeeViewDecaysToo`.

The fix also flushed out a **second, quieter instance of the same pathology hiding in a passing
test** (D-0022). `test_windwardDoesNotOverchargeOnCalmFlow` asserted a calm pool sits at exactly
the floor. It did — but only because a stale 503-pip fee, three pips above the floor, was just
enough to stop a dust swap crossing back over a tick boundary. The pool then never moved again,
the estimate decayed to zero, and the pool *read* as calm because the stale fee had suppressed the
flow that would have shown it moving. With decay-on-read the pool oscillates one tick an hour, as
it always really was, and prices at 503. **The bug was manufacturing the evidence that the design
was fine.**

**Requires a redeploy with a re-mined address (D-0006).**

### C-1 (Critical, griefing) — a same-block round trip strands the tick anchor — **OPEN, ACCEPTED**

The `dt == 0` anchor hold that closes W-01 has a second edge. A trader who is first-of-block can
displace the price (the anchor advances to the displaced tick), then revert the displacement in
the **same block** (that leg takes the `dt == 0` path, so the anchor is held). The anchor is left
at a price that never survived the block, and the **next** swap measures the reversal as a second,
equally large move.

Measured: anchor stranded at tick -591 while the real tick is 14; an honest dust swap in the next
block is then charged for a phantom 605-tick move, taking the fee from **5325 to 7402 pips**.

The attacker pays real fees on both legs, so this is a griefing primitive, not a profit one — but
it lets a third party raise the fee honest traders pay, and combined with H-1 the elevated fee
persists until someone is willing to pay it.

Fix direction: the defect is that the sample is taken mid-block. Sampling against the tick current
at the *start* of the next timestamped observation would make an intra-block spike that is
reverted contribute nothing. Any change must be re-tested against
`test_W01_sameBlockSlicingCannotHideAMove`, since the anchor hold is what closes W-01.

**Why this is ACCEPTED rather than fixed** (D-0023):

1. **The two requirements are in direct tension.** Hold the anchor on `dt == 0` and a same-block
   round trip strands it (C-1). Advance it and a move split across same-block slices is erased
   (W-01, exploitable and cheaper). There is no local patch: the correct fix re-defines the anchor
   as *the tick at the last block boundary*, which changes what the estimator measures. That is a
   design change to the core mechanism, not a bug fix, and it is out of scope this close to
   submission.
2. **It cannot move funds.** All four returns-delta bits are clear, so v4 never parses a delta
   this hook returns.
3. **It is not profitable.** The attacker pays the full fee on both legs and faces the raised fee
   themselves on their next trade. It is griefing, and it costs the griefer more than the target.
4. **The H-1 fix materially reduces its impact.** The phantom elevation now decays with elapsed
   time whether or not anyone trades, so a stranded anchor raises fees for one interval rather
   than until the next trade arrives.
5. **It is bounded by `feeMax`.** The worst case is the 1% ceiling, which is reachable by ordinary
   volatility anyway.

**This is an accepted risk, not a dismissed finding.** A production deployment must fix it. The
block-boundary anchor is the recommended design and is recorded here so it does not have to be
rediscovered.
