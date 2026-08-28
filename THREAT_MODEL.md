# THREAT_MODEL.md — Windward

**Rewritten 2026-08-28.** The previous version enumerated V1–V20 against Keel, a runtime
accounting guard that no longer exists. Those vectors do not apply to a fee-setting hook and
were misleading a reviewer into checking the wrong properties.

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
| V2 | **Ceiling pinned indefinitely** (T2/T3). No time decay existed. | One ordinary swap pinned the pool at 1% and it was **still there seven days later**. | The estimate decays on wall-clock time; the ceiling releases with no trading required. |
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
| V12 | Gas overhead per swap (one `extsload`, two SSTOREs, one `sqrt`, one event). | **Measured: 11,192 gas, ~15% of an unhooked swap** (`test/WindwardGas.t.sol`, interleaved 5-run average on warm storage). The `dt == 0` path costs 65,098 vs 143,581. No longer open. |

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
