# CURRENT_STATE.md — Windward (formerly Keel)

**Read this file before anything else in a new session.**

**Last updated:** 2026-08-28 — Windward implementation started, 28 tests green.

---

## Current project

**Windward** — a volatility-adaptive dynamic-fee hook for Uniswap v4.
Target: **UHI10 Hookathon** ("The Fair Flow Frontier: MEV protection and sustainable low-fee
liquidity"). Submission deadline **2026-09-03**; demo day **2026-09-11**. ~30h build budget.

**Keel is dead.** Both forms — the runtime guard (D-0013) and the invariant test kit (D-0014) —
were killed on evidence. Read `DECISIONS.md` D-0013 through D-0016 before questioning this;
seven candidate mechanisms were eliminated with recorded causes.

## Status

| Area | State |
|---|---|
| `src/WindwardHook.sol` | Implemented. Prices swaps from EWMA tick variance. |
| `src/lib/Volatility.sol` | Implemented. EWMA + integer sqrt, clamps, capped observations. |
| `test/WindwardHook.t.sol` | 17 tests green (10 hook, 7 library). |
| `data/unichain-swaps.json` | 745 real Unichain v4 swaps joined to tx priority fees. |
| Calibration | **NOT DONE.** See blockers. |
| Simulation harness on real traces | Not started. |
| Demo script | Not started. |
| Testnet deploy | Not started. |
| README | Not written. |

**Tests: 28 passing, 0 failing** (`forge test`). Build green.

## Blockers / next actions, in order

1. **Calibrate `feePerSigma`.** In `test_windwardEarnsMoreThanStaticFeeOnVolatileFlow` the fee
   saturates at `FEE_MAX` (10,000 pips) for most of the sequence, giving ~15.7x the static
   pool's fee growth. That is a **parameter problem, not a correctness problem**, but a fee
   pinned at its ceiling is a bad demo and an easy judge objection. Calibrate against the real
   tick series in `data/unichain-swaps.json` so the fee moves through a sensible mid-range.
2. Build the twin-pool simulation driven by the **real** trace rather than synthetic swaps.
3. Write `script/demo.sh` — one command, prints the comparison table.
4. README with the honest limitations section.
5. Testnet deploy (Unichain Sepolia addresses in `docs/RECON.md` §7 are still `UNVERIFIED` —
   verify on-chain first).

## Known risks

- `HYPOTHESIS` That a volatility-scaled fee actually improves LP outcomes. Currently supported
  by theory (LVR grows with variance) and by a synthetic twin-pool test. **Not yet demonstrated
  on real flow.** Item 2 above is what turns this into evidence.
- The mechanism is not novel; differentiation rests on execution quality plus the measured
  Unichain study. Judges may still read it as "another dynamic fee hook."
- `FACT` Fee saturation at current parameters (item 1).

## The measured Unichain study — the differentiator

All `FACT`, from primary on-chain data, recorded in `DECISIONS.md` D-0016:
retail pays **301x** the median arbitrage transaction in priority fees; **82%** of arbs pay less
than the median retail swap; **zero JIT** events; **3 unique LP addresses**; **95.4%** of swaps
are alone in their block; **8.2 txs/block**. Unichain v4 has essentially no MEV microstructure,
which is why Windward deliberately depends on none of those signals.

## Stale documents

`PROJECT.md`, `SECURITY.md`, `THREAT_MODEL.md`, `TESTING.md`, `RESEARCH.md` still describe Keel.
They are **historical** until rewritten for Windward. `DECISIONS.md`, `docs/RECON.md`,
`docs/RECON-hooks.md` and `docs/BUNNI_CASE_STUDY.md` remain accurate and useful.
