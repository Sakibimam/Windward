# CLAUDE.md — Keel

## Session-start ritual

**Read `CURRENT_STATE.md` before doing anything else.** Then check the current phase below.
Do not start a new phase without the owner's approval.

## Identity

**Keel** is a runtime safety layer for a *narrow class* of Uniswap v4 hooks: those implementing
custom accounting with **share-like LP claims** (vault-style wrappers that tokenise LP positions
into fungible claims). It enforces, during execution, that share-like claims remain properly
backed by assets — preventing economically invalid state transitions that the PoolManager's
settlement invariant does not catch. This is a **hypothesis**, not a conclusion; Phase 4 exists
to test whether such an invariant actually exists.

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
5. **You are authorised and expected to kill this project** if a kill condition in `PROJECT.md`
   becomes true. Do not preserve the thesis out of momentum.
6. **Never weaken security to save time without recording the trade-off in `DECISIONS.md`.**
7. **Every phase ends with a green build and an updated `CURRENT_STATE.md`.** Never leave broken
   code and continue.

## Source-of-truth hierarchy

`CURRENT_STATE.md` → `DECISIONS.md` → `RESEARCH.md` → this conversation (**last**).

Evidence lives in `docs/RECON.md`. If any document disagrees with it, `docs/RECON.md` wins.

## Commands

| Purpose | Command |
|---|---|
| Build | `forge build` |
| Test | `forge test` |
| One test, verbose | `forge test --match-test <name> -vvv` |
| Deep fuzz / invariant | `FOUNDRY_PROFILE=deep forge test` |
| Coverage | `forge coverage` |
| Gas | `forge snapshot` |
| Format | `forge fmt` |
| Fork test | `forge test --fork-url $UNICHAIN_RPC_URL` |
| Production build | `FOUNDRY_PROFILE=deploy forge build` |
| Hook self-test | `.claude/hooks/guard-bash.test.sh "$PWD/.claude/hooks/guard-bash.sh"` |

## Directory map

| Path | What it is |
|---|---|
| `src/` | Contracts. Currently only `CompileCanary.sol` — a throwaway pin-verification canary. |
| `test/` | Foundry tests. |
| `script/` | Deployment scripts. Empty. |
| `lib/` | Pinned dependencies as git submodules. **Never `forge update`.** |
| `docs/RECON.md` | All Phase 0/1 evidence: tool output, pins, verified signatures, addresses. |
| `docs/RECON-hooks.md` | PreToolUse hook evidence and test results. |
| `docs/INVARIANTS.md` | **Phase 4 deliverable.** Does not exist yet. |
| `.claude/rules/` | Always-loaded coding, security, testing, and research rules. |
| `.claude/agents/` | Four read-only review subagents. |
| `.claude/skills/` | `verify-before-code`, `keel-security-review`, `release-check`. |

## Verified dependency pins

Evidence: `docs/RECON.md` §4. Resolved by following v4-periphery's own submodule tree, **not**
by taking latest tags (`DECISIONS.md` D-0004).

| Dependency | Commit |
|---|---|
| v4-periphery | `dce236d4e2057422d0791d9a973a58765eb46f65` |
| v4-core | `59d3ecf53afa9264a16bba0e38f4c5d2231f80bc` |
| permit2 | `cc56ad0f3439c502c246fc5cfcc3db92bb8b7219` |
| forge-std | `1de6eecf821de7fe2c908cc48d3ab3dced20717f` |
| solmate | `4b47a19038b798b4a33d9749d25e570443520647` |
| openzeppelin-contracts | `dbb6104ce834628e473d2173bbc9d47f81a9eec3` |

Toolchain: Foundry 1.7.1, solc `0.8.26`, evm `cancun` (required — v4 uses transient storage).

**Two traps already confirmed** (`docs/RECON.md` §6):
`SwapParams` is in `@uniswap/v4-core/src/types/PoolOperation.sol`, not `IPoolManager.SwapParams`.
`BaseHook.sol` does **not** exist in v4-periphery at our pin.

Unichain PoolManager: `0x1f98400000000000000000000000000000000004` (chain id 130), verified
on-chain. **Never invent an address**; only `docs/RECON.md` §7 addresses may be used.

## Governing security property

> **The guard observes and reverts. It never touches accounting.**

Hook callbacks return zero deltas; the hook address must have the four `*_RETURNS_DELTA_FLAG`
bits (address bits 0–3) **clear**, asserted by test. Keel has no owner, no upgrade path, and
**no pause** — a pause on a withdrawal path is a fund-freezing switch.

**A false positive that freezes withdrawals is worse than the bug it prevents.** It is an
explicit kill condition.

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

## Current phase

**Phase 0 complete. Awaiting owner approval to begin Phase 1 (Uniswap v4 research).**
See `CURRENT_STATE.md` for the exact next action.
