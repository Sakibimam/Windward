# PROJECT.md — Windward

## Identity

**Windward** is a volatility-adaptive fee hook for Uniswap v4. It sets the LP fee on every swap
from a time-decayed estimate of the pool's own realised tick variance. No oracle, no external
call, no priority-fee assumption, no admin key.

It ships with a 7-day Unichain microstructure study, which is the artifact that produced the
design and which found the bug the design exists to fix.

## The problem

A static fee tier is wrong most of the time. It is too high when the pool is quiet, which costs
the pool flow, and too low when the pool is moving, which is exactly when informed order flow is
most expensive for liquidity providers. v4 makes a per-swap dynamic fee possible for the first
time; the open question is what to drive it with.

Windward drives it with the only signal that needs nothing outside the pool: the pool's own
recent price movement.

## What it is, precisely

A **heuristic**, motivated by the loss-versus-rebalancing literature. It is **not** an
implementation of any optimal policy from that literature, and **the claim that it improves LP
outcomes is unvalidated** — fee revenue is not LP PnL, and there is no demand-elasticity model
for the flow that leaves at a higher fee. See `DECISIONS.md` D-0019. The word *optimal* may not
be used to describe it.

What the study does establish is narrower and testable: the fee carries information about
near-future price movement, and a shuffled null that preserves the move distribution exactly
does not reproduce that. Figures in `data/economics.json`; method in `analysis/economics.py`.

## Scope

**In scope**

- A single immutable hook contract with no owner, pause, upgrade path, or setter.
- A fee bounded between two constructor-set values, moving with realised variance.
- A reproducible measurement study over real on-chain flow.

**Explicit non-goals** — reject these if they resurface

- An oracle dependency, or any external call on the swap path.
- A priority-fee or block-position signal. Measured and rejected; see `docs/SIGNALS.md`.
- Governance, admin keys, upgradeability, or a configurable framework.
- Off-chain monitoring or simulation. The hook is on-chain and synchronous or it is nothing.
- Any claim about LP profitability that the data does not support.

## Governing security property

> **Windward cannot move funds. It can only price them.**

`beforeSwap` returns a zero delta and `afterSwap` returns `0`; all four `*_RETURNS_DELTA` bits
of the hook address are clear, so v4 never parses a returned delta. Every parameter is
`immutable`.

**What is not guaranteed:** the fee override *is* an accounting-affecting lever, and Windward
steers it. The dominant harm is a fee high enough to price honest flow out of the pool. Full
analysis in `THREAT_MODEL.md`; policy in `SECURITY.md`.

## Definition of success

1. The fee is demonstrably informative about near-future volatility, tested against a null
   designed to reproduce the headline metrics by accident.
2. Every figure published is regenerated from committed code and data, not transcribed.
3. The hook is deployed, and its runtime bytecode is verified against source.
4. Security findings are fixed and pinned by regression tests, or explicitly accepted with a
   stated reason. Silently dropping a finding is prohibited.
5. Gas overhead per swap is measured and defensible.
6. The limitations are stated honestly, including what the study does **not** show.

Windward **fails honestly** — an acceptable outcome — if the evidence does not support the
thesis and we say so with the data. That has already happened once: the original economic
thesis was killed in `DECISIONS.md` D-0018, and two headline metrics were demoted in D-0024
after they failed their own null.

## Kill conditions

Recommend killing or fundamentally changing the project, immediately and without hedging, if:

- The fee signal is indistinguishable from noise under a null that preserves the move
  distribution.
- The mechanism introduces a new critical attack vector. **A fee high enough to price honest
  flow out of the pool is one.**
- Gas cost is unreasonable for the pools that would use it.
- The approach is redundant with existing tooling, standards, or libraries.
- The result cannot be reproduced from the committed pipeline.

When recommending a kill, produce the evidence, the **strongest counterargument to your own
recommendation**, and the best alternative found.

## Lineage

Windward is the last of several candidates; the earlier ones were eliminated on evidence, each
recorded in `DECISIONS.md` (D-0001 through D-0018) with the measurement that killed it. That
history is kept deliberately: `docs/CORRECTIONS.md` lists the claims this project retracted
about its own findings.
