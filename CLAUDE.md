# CLAUDE.md — Windward

## Session-start ritual

**Read `CURRENT_STATE.md` before doing anything else.** Then check the current phase below.
Do not start a new phase without the owner's approval.

## Identity

**Windward** is a volatility-adaptive fee hook for Uniswap v4. It sets the LP fee per swap from a
time-decayed estimate of the pool's own realised tick variance — no oracle, no external call, no
priority-fee assumption, no admin key. It ships with a 7-day, 426,807-swap Unichain
microstructure study that produced the design.

It is a **heuristic** motivated by the loss-versus-rebalancing literature, **not** an
implementation of any optimal policy from it, and the claim that it improves LP outcomes is
**unvalidated**. The word *optimal* may not be used to describe it (`DECISIONS.md` D-0019).

Windward is the ninth candidate here; eight were killed on evidence. **Keel** — the runtime
accounting guard this file used to describe — is dead (D-0013, D-0018). Do not resurrect it.

## The seven rules

1. **The repository is the source of truth. This conversation is not.** Every durable fact,
   decision, and assumption goes into a file. A future session must be able to reconstruct the
   project from the repo alone.
2. **Never write an API call, import path, function signature, struct field, version number,
   commit hash, or contract address you have not verified this session.** Verify from source on
   disk, a live query, or official documentation. Training data is stale.
3. **When you cannot verify something, write `UNVERIFIED` and stop.** Stopping is correct.
   Guessing is the worst outcome — the owner will not catch it.
4. **Tag every substantive claim**: `FACT` (verified this session, with source) / `INFERENCE`
   (reasoned from verified evidence) / `HYPOTHESIS` (being tested) / `UNVERIFIED`.
   Never silently promote a tag.
5. **The project is LOCKED. Do not propose a tenth candidate.** Nine were tried and eight were
   killed on evidence (`DECISIONS.md` D-0013 to D-0018) — that phase is over. If something
   fails, **repair it or narrow the scope**; do not switch projects. Report a fatal finding
   honestly and let the owner decide.
6. **Never weaken security to save time without recording the trade-off in `DECISIONS.md`.**
7. **Every block of work ends with a green build and an updated `CURRENT_STATE.md`.** Never
   leave broken code and continue.

## Source-of-truth hierarchy

`CURRENT_STATE.md` → `DECISIONS.md` → `RESEARCH.md` → this conversation (**last**).

Evidence lives in `docs/RECON.md`. If any document disagrees with it, `docs/RECON.md` wins.

## Commands

| Purpose | Command |
|---|---|
| Build | `forge build` |
| Test (47 tests) | `forge test` |
| One test, verbose | `forge test --match-test <name> -vvv` |
| Attack regressions | `forge test --match-path "test/WindwardAttack.t.sol"` |
| Gas overhead | `forge test --match-path "test/WindwardGas.t.sol" -vv` |
| Deep fuzz / invariant | `FOUNDRY_PROFILE=deep forge test` |
| Format | `forge fmt` |
| Production build | `FOUNDRY_PROFILE=deploy forge build` |
| **Reproduce the study** | `analysis/run.sh` (`--quick` for a 20k-block window) |
| Decoder regressions | `python3 analysis/test_decode.py` |
| Gas in dollars | `python3 analysis/gas_economics.py` |
| **Demo** | `script/demo.sh` (5.7s cold, offline) |
| Hook self-test | `.claude/hooks/guard-bash.test.sh "$PWD/.claude/hooks/guard-bash.sh"` |

## Dependencies and verified facts

Pins are commit-exact and live in `docs/RECON.md` §4 — read them there rather than duplicating
them here (`git submodule status` prints the live values). They were resolved by following
v4-periphery's own submodule tree, **not** by taking latest tags (`DECISIONS.md` D-0004).
**Never `forge update`.**

Toolchain: Foundry 1.7.1, solc `0.8.26`, evm `cancun` (required — v4 uses transient storage).

**Two traps already confirmed** (`docs/RECON.md` §6):
`SwapParams` is in `@uniswap/v4-core/src/types/PoolOperation.sol`, not `IPoolManager.SwapParams`.
`BaseHook.sol` does **not** exist in v4-periphery at our pin.

Unichain PoolManager: `0x1f98400000000000000000000000000000000004` (chain id 130), verified
on-chain. **Never invent an address**; only `docs/RECON.md` §7 addresses may be used.

## Governing security property

> **Windward cannot move funds. It can only price them.**

`beforeSwap` returns a zero delta and `afterSwap` returns `0`; the address has all four
`*_RETURNS_DELTA_FLAG` bits (address bits 0–3) **clear**, so v4 never even parses a returned
delta. The constructor calls `Hooks.validateHookPermissions` with the full 14-flag set. No owner,
no pause, no upgrade path, no setters — every parameter is `immutable`.

**What is NOT guaranteed:** the fee override *is* an accounting-affecting lever
(`Pool.sol:303-307`), and Windward steers it between `feeMin` and `feeMax`. "Never touches
accounting" was Keel's property and is **false here**.

**The dominant harm is a fee high enough to price honest flow out of the pool.** Full analysis in
`THREAT_MODEL.md`; policy in `SECURITY.md`.

## Review chain — mandatory for security-sensitive changes

```
implement → test → security-reviewer → adversarial-reviewer → fix → test again
```

Your own explanation of your code is **not** evidence it is correct. Only passing tests and
independent review are. Reviewers are read-only by design (D-0008); the main session fixes.

## Working with the owner

The owner is a competent technical thinker but **not a Solidity programmer, and cannot audit
this code.** Assume mistakes will not be caught downstream. Catching them is your job.

- Explain decisions in plain language. Never assume they know why a command is safe.
- **Never ask them to inspect code you can inspect yourself**, or to debug what you can test.
- Do not stop for trivial approvals inside an approved phase. Work autonomously.
- **Do** stop for: architecture changes, scope changes, adding a dependency, real-money
  transactions, mainnet deployment, destructive operations, security changes that materially
  increase risk, contradictory evidence you cannot resolve, and anything affecting the core
  thesis.

When you need something only they can do, use exactly this format:

```
MANUAL ACTION REQUIRED
1. What to do:
2. Why:
3. Exact command or click:
4. What you should see:
5. What to paste back to me:
```

Assume they can infer nothing.

## No code before design

For every feature: inspect relevant code → verify the current API from source → state
assumptions explicitly → identify the attack surface → propose a design → update documentation →
implement → test → adversarially review → update `CURRENT_STATE.md`.

Do not generate a large amount of code from unverified assumptions.

## Compaction protocol

**Before compacting:** update `CURRENT_STATE.md` and `DECISIONS.md`.
**After compacting, or in a new session:** re-read `CURRENT_STATE.md`, `DECISIONS.md`, and
`docs/RECON.md`, and **explicitly flag any conflict between your context and the files.** The
files win. Say so out loud rather than silently reconciling.

## The surviving finding

The naive volatility fee sits at its **fee floor on 20.6–79.5%** of real Unichain swaps and takes
only **21–49 distinct values** across 426,807 of them. The repaired version sits at the floor
**0.0%** of the time and takes **437–2,349** values on the same data. Integer division in
`(dTick²)/dt` and `sqrt(var/WAD)` truncated most real observations to zero; carrying WAD scaling
through the division fixes it. Every figure here comes from `data/stats.json`.

## Standing rules

1. **The word "optimal" may not describe Windward anywhere** — repo, README, or deck
   (`DECISIONS.md` D-0019). It is a **heuristic** motivated by the LVR literature, not an
   implementation of any optimal policy from it. Paper titles quoted as citations are exempt.
2. **The LP benefit is unvalidated.** Fee revenue is not LP PnL, and there is no
   demand-elasticity model. Never imply otherwise.
3. **No statistic may be quoted that did not come from `analysis/stats.py`** or
   `analysis/gas_economics.py`. No hand-transcription — that caused all three data errors (D-0017).
4. `test_sanity_higherFeeOnIdenticalVolumeCollectsMoreFees` is **not evidence**; it proves
   `10000 > 500`.
5. Retracted claims must never be requoted: the 301× priority gap, zero JIT, 3 LP addresses, and
   both the "mean-reverting" and "momentum" characterisations (D-0020).

## Current status

**Blocks 1–5 complete. 47 tests passing.** Remaining: testnet deployment, then freeze.
The project is **LOCKED — no further pivots.** If something fails, repair or narrow scope.
`CURRENT_STATE.md` has the exact next action.
