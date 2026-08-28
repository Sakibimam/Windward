# CURRENT_STATE.md — Windward

**Read this before anything else in a new session.**

**Last updated:** 2026-08-28 — Blocks 1-5 complete, 45 tests green.

---

## What this is

**Windward** — a volatility-adaptive fee hook for Uniswap v4, plus a 7-day Unichain
microstructure study. UHI10 Hookathon, submission **2026-09-03**, demo day 2026-09-11.

Windward is the **ninth** candidate. Eight were killed; `DECISIONS.md` records each with
evidence. **The project is LOCKED — no further pivots.** If something fails, repair or narrow
scope.

## Block status

| Block | Scope | State |
|---|---|---|
| 1 | Reproducibility — `analysis/` as committed code, regression tests for both decode bugs | **DONE** |
| 2 | Widen the sample to 7 days, re-test the priority-fee claim | **DONE** |
| 3 | Repair the hook (F-1, W-01, W-02, W-03, W-06, W-07, W-10, W-12) | **DONE** |
| 4 | Honest claims — SECURITY.md, THREAT_MODEL.md, no "optimal" anywhere | **DONE** |
| 5 | Demo + writeup (`script/demo.sh`, `README.md`) | **DONE** |
| 6 | Testnet deploy, verified source, rehearse | **BLOCKED — needs a funded key.** Sepolia addresses now verified on-chain; gas measured. |

## Tests

**47 passing, 0 failing** (`forge test`), plus `analysis/test_decode.py` (15 checks).

- `test/WindwardAttack.t.sol` — one regression test per closed security finding
- `test/SwapEventConvention.t.sol` — pins the Swap sign convention against the protocol
- `test/WindwardHook.t.sol` — hook behaviour + fuzzed library properties

## The headline numbers (all from `data/stats.json`)

7 days, blocks 56549879-57154678, **426,807 swaps**, 232 pools, 6,000 sampled txs.

- Priority fee: retail median 1,450,000 wei vs arb median 1,000,000 (C1) / 83,161 (C2)
  -> retail pays **1.4x to 17.4x more**. A priority-keyed fee would tax retail.
- **82.7%** of swaps are alone in their block for their pool.
- **19** JIT events in 7 days; **46** distinct LP addresses.
- Direction is **pool-dependent** — 2 of 5 mean-revert, 3 trend.
- Hook repair on the same 426,807 swaps: swaps at the fee floor **20.6-79.5% -> 0.0%**;
  distinct fee values **21-49 -> 437-2,349**.

## Retracted claims — do not requote

`DECISIONS.md` D-0020. The 50-minute sample gave "301x priority gap", "zero JIT", "3 LP
addresses". The 7-day sample gives **1.4-17.4x**, **19**, **46**. Also retracted: both the
"mean-reverting" (D-0016) and the later "momentum" (D-0017) characterisations — the effect is
pool-dependent, not a chain property.

## Standing rules

1. The word **"optimal"** may not describe Windward anywhere (D-0019). It is a heuristic.
2. The LP benefit is **unvalidated**. Fee revenue is not LP PnL.
3. No statistic may be quoted that did not come from `analysis/stats.py`.
4. `test_sanity_higherFeeOnIdenticalVolumeCollectsMoreFees` is **not evidence**; it proves
   10000 > 500.

## Next action — Block 6

Deploy to Unichain Sepolia. **Blocked on a funded deployer key**, which only the owner can
provide. Before deploying:

1. Verify the Unichain Sepolia addresses in `docs/RECON.md` §7 on-chain — they are still
   `UNVERIFIED`.
2. Write `script/Deploy.s.sol` with CREATE2 address mining for the flag bits
   `AFTER_INITIALIZE | BEFORE_SWAP | AFTER_SWAP`, all returns-delta bits clear.
3. Mine and build under `FOUNDRY_PROFILE=deploy` (D-0006) — mining against default-profile
   bytecode produces an address that does not match the deployed code.
4. Gas is measured (11,192/swap); re-measure after any change to the hook.

## Known gaps

- Gas measured: **11,192 per swap, ~15%** of an unhooked swap (`test/WindwardGas.t.sol`).
- No LP-PnL or demand-elasticity model (D-0019) — the central unvalidated claim.
- `PROJECT.md`, `TESTING.md`, `RESEARCH.md` still describe earlier candidates and are historical.
