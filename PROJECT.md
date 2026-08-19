# PROJECT.md — Keel

## Identity

**Keel** is a runtime safety layer for a *narrow class* of Uniswap v4 hooks: those implementing
custom accounting with **share-like LP claims** — vault-style wrappers that tokenise LP
positions into fungible claims.

## The problem

Uniswap v4's `PoolManager` enforces exactly one global invariant at the end of a transaction:
every currency delta must be settled to zero. That is a *conservation* check. It says nothing
about whether the accounting a hook keeps on top of the pool is economically coherent.

A hook that mints fungible shares against pool liquidity introduces a second, independent
accounting system. Nothing in v4 checks it. A hook can therefore reach a state where the shares
it has issued are not backed by the assets it controls, and every individual transaction still
settles perfectly. The PoolManager will happily wave it through.

## Current thesis `HYPOTHESIS`

> Enforce, during execution, that share-like claims remain properly backed by assets —
> preventing economically invalid state transitions that the PoolManager's settlement invariant
> does not catch.

**This is a hypothesis, not a conclusion.** Phase 4 exists specifically to test whether a
generic invariant for this class actually exists and can be stated without knowledge of any
particular exploit. If it cannot, the correct outcome is to kill the project (see §Kill
conditions and `CLAUDE.md` rule 5).

## Target user

The author or operator of a v4 hook that issues fungible claims against pool liquidity.
Secondarily: an auditor or a security-conscious integrator who wants a runtime backstop that
does not depend on having found every bug at review time.

## Scope

**In scope**

- Hooks with an explicit share/claim concept, where claims are minted and burned against
  assets the hook controls or accounts for.
- Runtime (execution-time) enforcement inside hook callbacks.
- Observe-and-revert only. The guard reads state and reverts; it never modifies accounting.

**Explicit non-goals** — reject these aggressively if they resurface

- A universal safety layer for all v4 hooks. Rejected: see `DECISIONS.md` D-0002.
- Price-movement caps ("price cannot move more than X per block"). Actively harmful.
- Withdrawal rate limiting / circuit breaking. That is substantially ERC-7265 (2023).
- A framework, an SDK, a plugin system, or anything configurable enough to need docs.
- Off-chain monitoring, alerting, or simulation. Keel is on-chain and synchronous or it is
  nothing.
- Detecting the Bunni exploit specifically. See `RESEARCH.md`.
- Upgradeability, governance, admin keys, or a fee mechanism.

## Constraints

- **~30 hours of build time. Hard deadline is imminent.**
- Priority order, strictly: **correctness → security → evidence → working demo → simplicity →
  presentation.**
- The product owner is not a Solidity programmer and cannot audit the code. Errors will not be
  caught downstream. See the vibe-coder protocol in `CLAUDE.md`.
- Target chain: **Unichain (chain id 130)**. PoolManager address verified in `docs/RECON.md` §7.
- Deliverable is a **small, correct, demonstrable thing — not a framework.**

## Definition of success

Keel succeeds if, at the deadline, all of the following are true:

1. `docs/INVARIANTS.md` states at least one invariant formally, with exact preconditions, that
   is sound for the stated hook class and was derivable **without** knowing about any specific
   exploit.
2. Tests prove it catches the failure class on a mock, and does **not** fire across a broad
   fuzzed set of legitimate sequences (false-positive rate driven near zero).
3. It is wired into real v4 hook callbacks with `returnDelta = false`, proven by the hook
   address's permission bits.
4. Gas overhead per guarded action is measured and defensible.
5. A one-command demo runs reproducibly.
6. The README states the limitations honestly, including anything Keel does not catch and
   whether the Phase 8 artifact is a replay or a reconstruction.

Keel **fails honestly** — which is an acceptable outcome — if Phase 2, 3, or 4 shows the
invariant is unsound, redundant, or unstateable, and we say so with evidence. See
`CLAUDE.md` rule 5 and the kill conditions below.

## Kill conditions

Recommend killing or fundamentally changing the project, immediately and without hedging, if:

- The invariant is mathematically unsound or not universal within the stated hook class.
- False positives cannot be driven acceptably low.
- The safety layer introduces a new critical attack vector. **A guard that can freeze
  withdrawals is one.**
- Gas cost is unreasonable for the pools that would use it.
- The protection is redundant with existing tooling, standards, or libraries.
- An equivalent product already exists.
- The motivating failure cannot be meaningfully reproduced or reconstructed.
- The project cannot be convincingly demonstrated within the remaining time.
- A materially simpler solution provides the same value.
- The market need turns out to be insufficient.

When recommending a kill, produce: the evidence, the **strongest counterargument to your own
recommendation**, and the best alternative found. Do not optimise for preserving this project.
