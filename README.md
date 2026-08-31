# Windward

**A Uniswap v4 hook that raises the swap fee when the pool is moving and lowers it when the pool
is calm, using nothing but the pool's own recent price history.**

UHI10 Hookathon · *The Fair Flow Frontier*

Live on Unichain Sepolia: **`0x609634584d5BD12Ba4216116528e364d385Ad0C0`** — runtime bytecode
verified against source (`docs/DEPLOYMENT.md`).

## What it does

A static fee tier is wrong most of the time: too high when nothing is happening, too low exactly
when prices are moving — which is when informed order flow is most expensive for liquidity
providers. Windward prices that difference per swap.

**How.** After each swap the hook reads the new tick straight from the `PoolManager` and folds
the squared tick move, divided by elapsed time, into a time-decayed variance estimate. Before the
next swap it takes the square root, scales it, adds a floor and clamps to a ceiling, returning
that fee to v4 with the override flag for that swap only. Observations lose weight on a
300-second half-life, so a quiet pool drifts back to the floor on its own.

**What it never does.** No oracle, no external call on the swap path, no priority-fee assumption,
and no owner, pause, upgrade or setter — every parameter is `immutable`. Both callbacks return
zero deltas and all four `*_RETURNS_DELTA` address bits are clear, so v4 never even parses a
delta from it. **Windward cannot move funds. It can only price them.**

## Does the fee actually track volatility?

This needs a null — otherwise "our fee varies a lot" proves nothing, since a random number
generator varies too. So: for each pool, shuffle the order of the real `(tick move, block gap)`
observations with a fixed seed. That preserves the multiset **exactly** — same heavy tail, same
median, same maximum — and destroys only volatility clustering, the one thing an adaptive fee
could exploit.

**Bucket every swap by the fee charged, then measure the tick move that actually followed:**

| pool | swaps | decile 1 | decile 10 | lift | null lift | ρ | null ρ |
|---|---|---|---|---|---|---|---|
| `0xc4f393…` | 89,048 | 1.53 | 7.31 | **4.78x** | 1.04x | 0.2501 | 0.0129 |
| `0x75b192…` | 76,313 | 1.25 | 8.15 | **6.52x** | 1.13x | 0.1965 | 0.0135 |
| `0x3258f4…` | 71,915 | 0.79 | 1.51 | **1.91x** | 1.01x | 0.1005 | 0.0148 |
| `0x04b7dd…` | 31,011 | 2.08 | 2.80 | **1.35x** | 0.99x | 0.2353 | 0.0662 |
| `0x51f9d6…` | 22,353 | 0.57 | 1.07 | **1.88x** | 1.13x | 0.1217 | 0.0330 |

Deciles are mean realised tick move over the interval each swap opened.

Across 290,640 real Unichain swaps the top fee decile precedes tick moves **1.35–6.52x** larger
than the bottom decile, in all five pools, against a null of **0.99–1.13x**. ρ is Spearman rank
correlation against realised forward variance — rank rather than Pearson, because tick moves are
heavy-tailed. Read effect sizes, not significance: at this sample size an economically worthless
correlation would still clear any threshold.

**We ran this null on our own headline metrics first, and they failed it.** "Sits at the fee
floor 0.0% of the time" and "takes 440–2,412 distinct values" are both reproduced by the shuffle —
the null even wins a pool. Both were demoted to a diagnosis of the integer-truncation bug that
real data caught and unit tests did not (`docs/ABLATION.md`).

**What this does not show.** Charging at the right *times* is necessary, not sufficient. It does
not show the revenue exceeds the adverse selection it offsets. **The LP benefit is unvalidated.**
Reproduce: `python3 analysis/economics.py`.

## Quick start

```bash
forge test                             # 61 tests
python3 analysis/test_differential.py  # model <-> contract agreement
analysis/run.sh                        # 102s warm; a cold run refetches 541MB
analysis/run.sh --quick                # smoke test only — NOT a reproduction
script/demo.sh                         # 6.8s cold, fully offline
```

## Testing

61 tests, green under both profiles (`forge test`, `FOUNDRY_PROFILE=deep forge test`). Fuzzing
uses a fixed seed so evidence is reproducible: 1,000 runs by default, 100,000 under `deep`.

Two standing rules: **never weaken a test to make a suite pass**, and **every finding gets a
named regression test before it is fixed**, written while it still fails so it has proven it can
fail. Both directions of each invariant are tested.

## Security

Six independent reviews across two rounds. **Eight findings fixed, each pinned by a regression
test that fails if the fix is removed; one open and documented rather than quietly dropped.**

The second round found two issues the first missed, both confirmed by our own probe tests rather
than taken on trust. **H-1** (fixed): the fee was priced from *undecayed* state, so a pool at the
1% ceiling still quoted 1% after seven silent days. **C-1** (open, accepted): a same-block round
trip can strand the tick anchor, so the next honest swap pays for a phantom move — it cannot move
funds, but a production deployment must fix it.

Full policy in **`SECURITY.md`**; every vector in **`THREAT_MODEL.md`**.

**Not audited. Prototype. Must not secure real funds.**

## Limitations

The six that most affect how the result should be read. All ten are in `docs/LIMITATIONS.md`.

1. **Windward is a HEURISTIC, and the word *optimal* does not describe it.** It is a volatility-
   adaptive fee computed from the pool's own tick history, motivated by the loss-versus-rebalancing
   literature — **not** an implementation of any optimal policy from it, and **not** validated as
   improving LP outcomes (`DECISIONS.md` D-0019).
2. **The LP benefit is unvalidated.** We measure *fee revenue*, not LP PnL, with no
   demand-elasticity model. `test_sanity_…` proves `10000 > 500` and is **not evidence**.
3. **The replay covers the 5 busiest pools only.** **136,167 swaps across 227 pools (31.9% of
   the window) were never replayed** — and those are the thin, low-activity pools where the
   estimator is least tested. **The thin-pool regime is untested.**
4. **The tick is steerable.** A funded actor can raise a pool's fee by trading it.
5. **All four hook parameters are underived deployment choices, not results.** `feeMin` (500),
   `feeMax` (10000), `feePerSigma` (200) and `halfLife` (300s) are constructor arguments picked
   by hand. **Nothing in the study derives, fits, or optimises any of them**, and no sensitivity
   analysis was run.
6. **The lift result is a correlation, not a causal or welfare claim.** It shows the fee is
   charged at the right *times*. It does not show the revenue exceeds the adverse selection it is
   meant to offset. See #2.

## Partner integrations

**None.** Windward integrates no partner technology. It has no oracle, no external call on the
swap path, and no dependency beyond Uniswap v4 core and periphery. Nothing in this repository
should be considered for a partner track prize.

## Repository map

| Path | What |
|---|---|
| `src/` | The hook and its estimator |
| `analysis/` | The study; `run.sh` reproduces every number here |
| `demo/index.html` | Visual walkthrough of the result (`analysis/make_demo_page.py`) |
| `data/*.json` | **Every published figure is read from these files** |
| `docs/ABLATION.md` | The truncation bug, and which repair did what |
| `docs/GAS.md` | Gas overhead in dollars, and the breakeven swap |
| `docs/SIGNALS.md` | Signals measured and rejected; why we read the tick |
| `docs/CORRECTIONS.md` | Claims this project retracted |
| `docs/LIMITATIONS.md` | All ten limitations |
| `docs/DEPLOYMENT.md` | Deployment evidence, read back from chain |
| `THREAT_MODEL.md` · `SECURITY.md` · `DECISIONS.md` | Vectors · policy · append-only decision log |

MIT licensed. See `LICENSE`.
