# docs/CORRECTIONS.md — what this project got wrong about its own findings

Extracted from the README. **Nothing here is abridged.** This file is kept deliberately: a
project that reports only its surviving claims is not reporting honestly.

## Retracted findings

An earlier, much smaller sample produced four claims that **did not survive** the 7-day,
426,807-swap window. All four are retracted. The superseded magnitudes are recorded in
`DECISIONS.md` D-0020 and are deliberately not repeated here — **every number in this README is
one that `analysis/` regenerates from the chain**, and the old sample's artifacts no longer exist.

| Retracted claim | What the 7-day window shows |
|---|---|
| "Retail pays a large multiple of the median arbitrageur" | **17.4×** on the broad classifier (n=619); the conservative classifier (n=9) is a single constant value and cannot support a magnitude at all |
| "**Zero JIT** on Unichain" | **19** events in 7 days across 232 pools |
| "Only **a handful** of LP addresses" | **46** distinct LP senders |
| "Unichain v4 flow **mean-reverts**" — and its later retraction claiming **momentum** | **Pool-dependent**: 2 of 5 mean-revert, 3 trend. Both characterisations were over-generalisations |

The first-of-block share was also overstated; the 7-day figure is **82.7%**.

## Three data errors we found in our own analysis

| # | Error | Effect | Prevented now by |
|---|---|---|---|
| 1 | **int24 sign extension** — decoded ticks with a 24-bit convention; the ABI sign-extends across a full 32-byte word | 31% of ticks decoded as ~2²⁵⁶ | `analysis/test_decode.py` |
| 2 | **Swap direction inverted** — `PoolManager` emits the **caller's** delta, so `amount0 > 0` is a *buy*; `IPoolManager.sol:85` says the opposite | Every direction-conditional statistic inverted | `test/SwapEventConvention.t.sol`, which pins the convention against the **protocol** |
| 3 | **Wrong denominator** — priority-fee shares over all transactions rather than swap flow | Inverted the conclusion | Classifiers state population and FP assumptions |

Root cause of all three: the analysis lived in uncommitted scratchpad scripts. `analysis/` exists
so a judge can reproduce every number here from a fresh clone.
