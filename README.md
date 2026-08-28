# Windward

**A naive volatility-scaled fee sat at its floor on 49.9% of real Unichain swaps (swap-weighted)
and took only 21–49 distinct values. Repaired, it never reaches the floor and takes 437–2,349
distinct values per pool. That was found by replaying the estimator over 290,640 real swaps —
not by a unit test, which had shown it working.**

A volatility-adaptive fee **heuristic** for Uniswap v4, computed from the pool's own tick
history. Motivated by the loss-versus-rebalancing literature; **not** an implementation of any
optimal policy from it, and **not** validated as improving LP outcomes.

The primary artifact is the **measurement study**; the hook is the instrument that produced it
(`DECISIONS.md` D-0018).

UHI10 Hookathon · *The Fair Flow Frontier: MEV protection and sustainable low-fee liquidity*

---

## The surviving finding

Replayed over the **five busiest pools — 290,640 swaps, 68.1% of the 426,807 in the 7-day
window**. Per pool, never "up to X" across pools:

| pool | swaps | original: at floor | repaired: at floor | original: distinct | repaired: distinct |
|---|---|---|---|---|---|
| `0xc4f393…` (busiest) | 89,048 | 20.6% | **0.0%** | 49 | **2,349** |
| `0x75b192…` | 76,313 | 73.0% | **0.0%** | 49 | **1,786** |
| `0x3258f4…` | 71,915 | 58.7% | **0.0%** | 35 | **1,039** |
| `0x04b7dd…` | 31,011 | 35.3% | **0.0%** | 31 | **909** |
| `0x51f9d6…` | 22,353 | 79.5% | **0.0%** | 21 | **437** |
| **swap-weighted** | 290,640 | **49.9%** | **0.0%** | — | — |

### Which repair did what

Four arms over the same 290,640 swaps, isolating each change:

| arm | at floor | distinct values |
|---|---|---|
| v1 original | 20.6 – 79.5% | 21 – 49 |
| **v2: WAD carried through the division and the sqrt — nothing else** | **0.0%** | **1,006 – 4,443** |
| v3: + time-based decay replacing the per-observation EMA | 0.0% | 403 – 3,107 |
| v4: + `dt == 0` identity and the cap tightened 1e12 → 1e8 (= the contract) | 0.0% | 437 – 2,349 |

**The fixed-point fix alone does all of it.** v2 takes every pool from 20.6–79.5% at the floor to
0.0%, and to 1,006–4,443 distinct values — more resolution than the shipped contract has.

**The security repairs made the signal worse.** Time-based decay and the `dt == 0` identity cut
the busiest pool from **4,443 distinct values to 2,349** — a 47% loss of resolution — and on
`0x51f9d6…` from 1,006 to 437. **We kept them anyway.** W-01 and W-02 are exploitable: without
time-based decay, 30 dust swaps in one block drop the fee from 10000 to 500 pips in the same
transaction as the trade they defeat, and one ordinary swap pins a pool at 1% for a week. A
sharper signal that a trader can switch off at will is worth less than a blunter one they cannot.
That is a deliberate trade, not a free win.

Reproduce: `python3 analysis/stats.py`.

**What "0.0% at floor" actually means:** the repaired hook charges **above** its 500-pip floor on
**every** replayed swap. That is not self-evidently good — it is a fee increase on 100% of flow,
and it is what makes the gas breakeven below come out positive by construction. Pool
`0x75b192…` still pins the 1% **ceiling** on 0.3% of its swaps despite W-02 being closed.

**Real flow is small and fast:** median absolute tick move **1** (p90 = 3), median gap between
consecutive swaps **2 blocks** (p90 = 23), and 19.4% of consecutive swaps share a block. Integer
`(dTick²)/dt` truncates most of that to zero.

### This is a Python model, not the contract

The replay runs `analysis/volatility_model.py`, a reimplementation of `src/lib/Volatility.sol`.
The two are pinned to a fixed 8-step vector by `test/VolatilityDifferential.t.sol` and
`analysis/test_differential.py`, which assert the same expected values from both sides — if
either drifts, one fails. Without that pair these numbers would describe a model of the hook
rather than the hook.

`dt` in the replay is a **block** delta; the contract uses a **second** delta. Unichain produces
one block per second, so they coincide there — but the measured quantity is blocks.

## Does it pay for its own gas?

Gas overhead is **11,192 per swap**, **15%** of the harness's 71,259-gas unhooked swap. It is
asserted to a tight range in `test/WindwardGas.t.sol` and written to `data/gas_overhead.json`,
which `analysis/gas_economics.py` reads — it is not transcribed into any script or comment.
It is a **local Foundry harness** measurement with synthetic swap sizes, not a mainnet figure.

```
$ cast gas-price --rpc-url https://mainnet.unichain.org
1500000
```

ETH/USD is a **single live `sqrtPriceX96` spot read** from the pool identified as native-ETH/USDC
by Transfer-log heuristics: **~$2,444** at the time of writing. One pool, one instant, no TWAP,
sanity-checked only for order of magnitude — and re-read live on every run, so the cent-level
figures below move between runs.

```
11,192 gas x 1,500,000 wei = 0.000000016788 ETH = ~$0.000041 per swap
```

**Headline is the conservative case: the p10 fee**, i.e. the fee charged on the calmest decile of
swaps. The median-fee figure flatters the result, because a breakeven derived from the median fee
is then compared against the *full* distribution of swap sizes.

| pool | pair | median swap | p10 fee | **breakeven (p10)** | **% above** | median fee | breakeven (median) | % above |
|---|---|---|---|---|---|---|---|---|
| `0xc4f393…` | USDC/HYPE | $113.62 | 636 | **$0.30** | **99.8%** | 761 | $0.16 | 99.9% |
| `0x75b192…` | USDC/SOL | $0.92 | 577 | **$0.53** | **99.0%** | 643 | $0.29 | 99.4% |
| `0x3258f4…` | ETH/USDC | $124.59 | 557 | **$0.72** | **98.3%** | 639 | $0.29 | 99.1% |
| `0x04b7dd…` | WETH/USD₮0 | $103.04 | 568 | **$0.60** | **99.3%** | 645 | $0.28 | 99.5% |

**A swap must clear roughly $0.72 before the LP's extra fee income exceeds the extra gas the
swapper burns. 98.3–99.8% of real swaps do.** On the optimistic median-fee basis the figure is
$0.29 and 99.1–99.9% — the percentages barely move; the breakeven more than doubles.

That is an accounting identity across two different parties, not a welfare result: the swapper
pays both the gas and the higher fee, so a swapper is strictly worse off.

Two further caveats. "vs static 500" assumes the counterfactual pool charges 500 pips; nothing in
the dataset establishes these pools' actual fees, and 500 is the hook's own `feeMin`. And it
assumes the same flow still arrives at a higher fee — see Limitations #1.

Figures from one run of `analysis/gas_economics.py`; the live ETH spot read moves the cent-level
values slightly between runs.

## Why it reads the tick and nothing else

**Chronology, stated plainly.** The **50-minute, 745-swap** study drove these four eliminations
(`DECISIONS.md` D-0016). The **7-day** study came afterwards (D-0020) and **retracted three of
the figures those eliminations rested on**. The eliminations still stand; the numbers below are
the corrected ones, and where the original reason no longer holds it is marked.

| Signal | 7-day measurement | Why it was eliminated |
|---|---|---|
| **Priority fee** | Retail via Universal Router pays 1,450,000 wei at p25–p90, with a heavy right tail (max 464M). Broad classifier (n=619): retail median is **17.4×** the arb median | The direction, not the magnitude — see below |
| **First-of-block** | **82.7%** of swaps are the **first** swap for their pool in their block; the other 17.3% (~10,500/day) are not | Too thin a base to key a mechanism on. *Originally justified at 95.4%, now retracted to 82.7%* |
| **JIT contention** | **19** events in 7 days across 232 pools | **OpenZeppelin ships `LiquidityPenaltyHook` (311 lines, complete)** — prior art, not rarity. The rarity argument rested on "zero JIT", now retracted |
| **Directional toxicity** | Pool-dependent — 2 of 5 mean-revert (AC(1) −0.139, −0.133), 3 trend (+0.114 to +0.186) | No chain-wide direction |

On the priority fee: the conservative classifier has **n=9**, and its distribution is a single
constant (1.0 gwei at p25 through max), so it cannot support a magnitude — we report the
**direction only**. Both classifiers' false-positive assumptions are in `analysis/stats.py`.

Windward depends on none of these. It reads only the pool's own tick history.

## Quick start

```bash
forge test                             # 49 tests
python3 analysis/test_differential.py  # model <-> contract agreement
analysis/run.sh                        # 102s with the cache warm; a cold run refetches 541MB
analysis/run.sh --quick                # smoke test on 20k blocks / 200 txs — NOT a reproduction
script/demo.sh                         # 5.7s cold, fully offline
```

## Security

**Windward holds and transfers no tokens.** It does set the LP fee, which is an economic lever
over every swap — see Limitations #5.

- `beforeSwap` returns a zero delta; `afterSwap` returns `0`.
- All four `*_RETURNS_DELTA` address bits are clear, so v4 **never parses** a returned delta.
- The constructor calls `Hooks.validateHookPermissions` with the full 14-flag set.
- No owner, no pause, no upgrade path, no setters. Every parameter is `immutable`.

Three independent reviews (security, protocol, adversarial) ran on 2026-08-28.

| Finding | Was | Now | Pinned by |
|---|---|---|---|
| **W-01** dust-swap suppression | 30 dust swaps in one block dropped the fee 10000 → 500 pips (20×), in the same transaction as the trade it defeated | Decay by elapsed time; `dt == 0` is an identity | a test that previously passed by demonstrating the attack |
| **W-02** ceiling pinned | One ordinary swap pinned the pool at 1%, still there seven days later | Decays on wall-clock time | same |
| **W-03** fee ladder | 1 distinct fee value across 40 escalating swaps | 1-pip resolution | same |
| **F-1** permission bits | Only returns-delta bits checked; a missing flag meant a permanently fee-free pool, silently | Full 14-flag validation | a constructor-rejection test |
| **W-06** exact-output DoS | `feeMax == MAX_LP_FEE` reverts every exact-output swap in v4 | Rejected in the constructor | a constructor-rejection test |

**Not audited.** Hackathon prototype. Must not secure real funds.

## Limitations

1. **The LP benefit is unvalidated.** We measure *fee revenue*, not LP PnL, with no
   demand-elasticity model. `test_sanity_…` proves `10000 > 500` and is **not evidence**.
2. **The replay covers the 5 busiest pools only.** **136,167 swaps across 227 pools (31.9% of
   the window) were never replayed** — and those are the thin, low-activity pools where the
   estimator is least tested. **The thin-pool regime is untested.**
3. **The fee is charged to the trader after the mover.** Property of every reactive dynamic fee.
4. **The estimator conflates transient and permanent price impact.** LVR depends on the
   permanent component.
5. **The tick is steerable.** A funded actor can raise a pool's fee by trading it.
6. **`feePerSigma` has no derivation.** A free parameter, in an immutable contract.
7. **One chain, one 7-day window, one public RPC, a 6,000-transaction sample.** Pool identities
   come from Transfer-log heuristics, not a registry.

## Retracted findings

An earlier 50-minute, 745-swap sample produced four claims that **did not survive** the 7-day,
426,807-swap window (`DECISIONS.md` D-0020):

| Retracted claim | 50-min sample | 7-day sample |
|---|---|---|
| "Retail pays **301×** the median arbitrageur" | 301× (n=40) | **17.4×** (broad, n=619); the conservative classifier cannot support a magnitude |
| "**Zero JIT** on Unichain" | 0 events | **19 events** |
| "Only **3 LP addresses**" | 3 | **46** |
| "Unichain v4 flow **mean-reverts**" — and its later retraction claiming **momentum** | one or the other | **Pool-dependent.** Both were over-generalisations |

The 95.4% first-of-block figure was also overstated; it is 82.7%.

### Three data errors we found in our own analysis

| # | Error | Effect | Prevented now by |
|---|---|---|---|
| 1 | **int24 sign extension** — decoded ticks with a 24-bit convention; the ABI sign-extends across a full 32-byte word | 31% of ticks decoded as ~2²⁵⁶ | `analysis/test_decode.py` |
| 2 | **Swap direction inverted** — `PoolManager` emits the **caller's** delta, so `amount0 > 0` is a *buy*; `IPoolManager.sol:85` says the opposite | Every direction-conditional statistic inverted | `test/SwapEventConvention.t.sol`, which pins the convention against the **protocol** |
| 3 | **Wrong denominator** — priority-fee shares over all transactions rather than swap flow | Inverted the conclusion | Classifiers state population and FP assumptions |

Root cause of all three: the analysis lived in uncommitted scratchpad scripts. `analysis/` exists
so a judge can reproduce every number here from a fresh clone.

## Candidate count

Windward is the **eleventh** candidate; **ten** were eliminated, each recorded in `DECISIONS.md`:

1. Tempo — flashblock-position fee (D-0001)
2. Generic Keel — three universal invariants (D-0002)
3. Keel — runtime accounting guard (D-0003, killed D-0013)
4. Keel — invariant test kit (rejected D-0014, off-theme)
5. Fathom — counterfactual fee-hook backtester (D-0014, superseded D-0015)
6. Ballast — priority-fee MEV tax (D-0015, killed D-0016)
7. Nezlobin directional fee · 8. first-of-block surcharge · 9. JIT protection · 10. am-AMM
   auction hook (all D-0016)

D-0016's own table says "seven successive candidates died" — that count covers rows 3, 4, 6–10
only, excluding Tempo, generic Keel and Fathom. Windward's own *economic thesis* was then killed
in D-0018; the code survives as a measurement instrument.

## Repository map

| Path | What |
|---|---|
| `src/WindwardHook.sol`, `src/lib/Volatility.sol` | The hook and its estimator |
| `analysis/` | The study. `run.sh` reproduces every number |
| `analysis/volatility_model.py` | The Python model the replay uses |
| `data/stats.json`, `data/gas_economics.json`, `data/gas_overhead.json` | Committed outputs |
| `docs/WINDWARD_DESIGN.md` | Frozen design |
| `DECISIONS.md` | Append-only log, including every retraction |
