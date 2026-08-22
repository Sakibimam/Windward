# CURRENT_STATE.md — Keel

**Read this file before anything else in a new session.** It is the top of the source-of-truth
hierarchy. Update it after every meaningful milestone, and before any compaction.

**Last updated:** 2026-08-28 (Phase 1 complete)

---

## Current phase

**Phase 1 — current Uniswap v4 verification. COMPLETE.**
Proceeding autonomously through Phase 2 → 3 → 4 (kill gate), per the owner's standing approval.

## Current objective

Phase 2 — prior art and security research. Run `research-reviewer`; classify every finding;
stop and report if something already provides substantially the same runtime protection.

## Work completed in Phase 1

- Verified all ten `IHooks` callback signatures **including return tuples** (previously
  `UNVERIFIED`) from source, with line numbers. `docs/RECON-hooks.md` §2.
- Verified callback ordering in `PoolManager.modifyLiquidity`/`swap`/`initialize`, the
  `unlock`/settlement model, `BalanceDelta`/`BeforeSwapDelta`, all 14 permission flags,
  `StateLibrary`/`TransientStateLibrary` read surface, dynamic-fee encoding, `Currency`,
  and `ERC6909Claims`.
- **Discovered `noSelfCall`** and proved its consequence with a new 9-test suite.
- Re-verified the Unichain deployment on-chain from three independent sources.
- Closed `RESEARCH.md` Q7 (PoolManager owner).
- Renamed the old `docs/RECON-hooks.md` (Claude Code guard evidence) to
  `docs/RECON-guard-hook.md`, freeing the name for Uniswap hook evidence.

## Implementation status

| Area | Status |
|---|---|
| Protocol code | **None written, by design.** Blocked until the Phase 4 kill gate passes. |
| `src/CompileCanary.sol` | Throwaway pin-verification canary. |
| `test/Phase1_V4Semantics.t.sol` | 9 characterisation tests of v4 semantics. **Not Keel tests** — Keel does not exist yet. |
| `test/mocks/VaultStyleHookMock.sol` | Stand-in for the target hook class. Not a Keel component; never deploy. |
| `docs/INVARIANTS.md` | Does not exist yet. **Phase 4 deliverable.** |

## Latest verified facts

Full evidence in `docs/RECON.md` (environment, pins, addresses) and `docs/RECON-hooks.md`
(v4 API). Phase 1 highlights:

- `FACT` **v4 skips every hook callback when the hook itself is the caller** — `noSelfCall`,
  `Hooks.sol:170-175`, plus inline guards at :217, :253, :293. Proven by
  `test/Phase1_V4Semantics.t.sol`, corroborated by upstream `SkipCallsTestHook.t.sol`.
  **This is the most consequential finding so far.** See D-0011.
- `FACT` The only invariant v4 enforces is `NonzeroDeltaCount == 0` (`PoolManager.sol:112`) — a
  conservation check, not a solvency check. The gap Keel targets is real.
- `FACT` With address bits 0-3 clear, the protocol **discards** any delta a hook returns
  (`PoolManager.sol:224`, `Hooks.sol:301`). "Observe and revert only" is protocol-enforced, and
  is proven by `test_returnedDeltaIgnoredWhenFlagClear`.
- `FACT` A guard has three sources of truth the guarded hook cannot forge: `StateLibrary` pool
  and position reads, `TransientStateLibrary` in-flight deltas, and raw token balances.
  **The strongest positive result for the thesis.**
- `FACT` `SwapParams`/`ModifyLiquidityParams` are free-standing structs in
  `types/PoolOperation.sol`; `beforeSwap` must return exactly 96 bytes (`Hooks.sol:259`).
- `FACT` `BaseHook.sol` is absent from all six dependencies; there is no `v4-periphery/src/utils/`.
- `FACT` Unichain PoolManager `0x1f98400000000000000000000000000000000004` re-verified at block
  57148459 against three independent sources.
- `FACT` **Q7 closed.** The PoolManager owner `0x2BAD…46CD` has no code on Unichain; its power is
  bounded to a protocol fee capped at 0.1% (`ProtocolFeeLibrary.sol:8`). It cannot touch pool
  principal, LP positions, or hook state. Non-critical.

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

Begin **Phase 2 — prior art and security research**. Run the `research-reviewer` subagent over
ERC-7265, ERC-4626 invariant libraries, OpenZeppelin `uniswap-hooks`, Foundry/Echidna/Halmos/
Certora invariant tooling, runtime monitoring products, and any v4 hook safety library.
Classify each finding. **If something already provides substantially the same runtime
protection, stop and report it.**

Carry D-0011 into that search: the honest question is now *"does anything already provide a
cooperative, opt-in accounting-invariant harness for share-issuing v4 hooks?"*

## Test status

- **Last passing:** `forge test` — 11 tests, 0 failures.
  `Phase1V4SemanticsTest` (9) + `CompileCanaryTest` (2).
- **Last failing:** none.
- **Hook harness:** `.claude/hooks/guard-bash.test.sh` — 38 passed, 0 failed.

## Security status

No Keel code exists, so nothing to review yet. Two protocol-level security properties are
established and **proven by test** for later use: returns-delta bits clear means the protocol
discards hook deltas, and a guard has non-forgeable state sources. The dominant open risk is
unchanged — a false positive that freezes withdrawals (`THREAT_MODEL.md` V7).

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
