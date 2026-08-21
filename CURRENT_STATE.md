# CURRENT_STATE.md — Keel

**Read this file before anything else in a new session.** It is the top of the source-of-truth
hierarchy. Update it after every meaningful milestone, and before any compaction.

**Last updated:** 2026-08-28 (Phase 0, session 2)

---

## Current phase

**Phase 0 — recon and scaffold. COMPLETE.**
**Blocked on: product owner approval to begin Phase 1.** Do not start Phase 1 without it.

## Current objective

Present the Phase 0 plan and wait for approval.

## Implementation status

| Area | Status |
|---|---|
| Protocol code | **None written, by design.** No code before design (`CLAUDE.md` rule). |
| `src/CompileCanary.sol` | Throwaway build canary only. Proves the dependency pins compile together. **Delete once real contracts exercise the same imports.** |
| Dependencies | Resolved, pinned, verified compiling together. `docs/RECON.md` §4. |
| Memory architecture | Complete. All documents populated with real Phase 0 content. |
| Permissions, hooks, rules, agents, skills | Complete and tested. |
| `docs/INVARIANTS.md` | Does not exist yet. **Phase 4 deliverable.** |

## Latest verified facts

Full evidence in `docs/RECON.md`. Highlights:

- `FACT` Toolchain: Foundry 1.7.1, solc 0.8.26, evm `cancun`, git 2.50.1, node v24.16.0,
  macOS 26.6.2 arm64, Claude Code 2.1.250.
- `FACT` Pins: v4-core `59d3ecf5`, v4-periphery `dce236d4`, permit2 `cc56ad0f`,
  forge-std `1de6eecf`, solmate `4b47a190`, openzeppelin-contracts `dbb6104c`.
  v4-core follows v4-periphery's own submodule pin, not the `v4.0.0` tag (D-0004).
- `FACT` `forge build` and `forge test` pass — 2 tests, `CompileCanaryTest`.
- `FACT` Unichain PoolManager `0x1f98400000000000000000000000000000000004` (chain id 130),
  confirmed by two independent sources (docs + `StateView.poolManager()` on-chain).
- `FACT` `https://mainnet.unichain.org` served historical `eth_call` back to block 1,000,000 —
  a Unichain fork reproduction looks plausible without a paid archive provider.
- `FACT` `SwapParams` is in `@uniswap/v4-core/src/types/PoolOperation.sol`, **not**
  `IPoolManager.SwapParams`, at our pins.
- `FACT` `BaseHook.sol` does **not** exist in v4-periphery at our pin. The tutorial import is
  wrong here. What Keel's hook inherits from is an open decision (D-0005).
- `FACT` PreToolUse hook suite: **38 passed, 0 failed** (`docs/RECON-hooks.md`). The hook was
  also observed blocking two real tool calls.

## Blockers

1. **Owner approval to begin Phase 1.** The only hard blocker.

## Known risks

- `HYPOTHESIS` The core thesis is unproven. Phases 2, 3, and 4 are each allowed to kill it, and
  should. See `PROJECT.md` kill conditions.
- **The dominant risk is a false positive that freezes withdrawals** (`THREAT_MODEL.md` V7). It
  is worse than the bug Keel prevents and is an explicit kill condition.
- ~30 hours of build time against 12 phases. Phases 2–4 may consume a large share and end in a
  kill recommendation. **That is an acceptable and honest outcome**, not a failure.
- `UNVERIFIED` The Bunni case study is entirely unverified — it is the brief's framing, not
  established fact. Phase 3 must source it primarily or discard it.
- `UNVERIFIED` Unichain Sepolia addresses; not checked on-chain. Verify before Phase 10.
- `UNVERIFIED` Whether the public RPC survives a full fork suite, and whether Ethereum archive
  access is needed for Phase 8.

## Open questions for the owner

Not blocking — Phase 1 can proceed without them.

1. **RPC.** No RPC environment variables are set on this machine. The public Unichain endpoint
   works and serves archive state, so nothing is needed yet. A provider key may be needed at
   Phase 8, and an Ethereum archive key may be needed if the Phase 8 reproduction requires
   Ethereum-side state.
2. **Deployment target.** Phase 10 assumes Unichain Sepolia. Confirm at that point.

## Next action

Await approval, then begin **Phase 1 — Uniswap v4 research**: read actual source in `lib/`,
verify `beforeSwap`/`afterSwap`/liquidity callback signatures **including return tuples**, fee
override encoding, permission flags and address mining, dynamic-fee initialisation, and
`StateLibrary` reads. Record every signature with file path and line number in `docs/RECON.md`.
Also identify the PoolManager owner `0x2BAD8182C09F50c8318d769245beA52C32Be46CD`
(`RESEARCH.md` Q7).

## Test status

- **Last passing:** `test/CompileCanary.t.sol:CompileCanaryTest` — `test_managerDeployed`,
  `test_hookFlagDecoding`. 2 passed, 0 failed.
- **Last failing:** none.
- **Hook harness:** `.claude/hooks/guard-bash.test.sh` — 38 passed, 0 failed.

## Deployment status

**Nothing deployed.** No contract deployed to any network, testnet or mainnet. No deployment
credentials configured. `.env` does not exist.

## Session-2 corrections

Two errors from session 1 were found and fixed. Both are recorded rather than quietly patched.

- **D-0009** — a block labelled "verbatim" in `docs/RECON.md` §4.1 contained a mistranscribed
  commit sha. Corrected from a live re-query. Blast radius was zero, because `uniswap-hooks` is
  not vendored.
- **D-0010** — the git **index** held stale submodule SHAs from the initial `forge install`,
  not the resolved pins. A first commit would have recorded pins contradicting `docs/RECON.md`,
  and a fresh clone would not have reproduced the verified build. Re-staged; index and worktree
  now agree.
- `docs/RECON.md` §5 recorded a secrets-check result that could not have been produced as
  written — `.env.example` did not exist. The file was created and every check genuinely re-run.
