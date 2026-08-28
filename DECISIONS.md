# DECISIONS.md — Keel

**Append-only.** Never edit a past entry. To change a decision, add a new entry that supersedes
it and explains why. Mark the old one `SUPERSEDED BY D-xxxx` and leave everything else intact.

Entry format: date, decision, alternatives considered, reason, evidence, consequence.

---

## D-0001 — Reject Tempo (flashblock-position dynamic fee hook)

- **Date:** before 2026-08-28 (historical, recorded retrospectively during Phase 0)
- **Status:** rejected, closed
- **Decision:** Do not build Tempo, a dynamic-fee v4 hook that keys the fee on a swap's position
  within a Unichain flashblock.
- **Alternatives considered:** build it anyway with a different signal; scope it to a single
  pool; ship it as a research artifact.
- **Reason:** three independent failures, any one of which is fatal.
  1. The mechanism it depends on does not exist as assumed: `getFlashblockNumber()` returns a
     **global monotonic counter**, not a sub-block index. There is no on-chain way to read
     position-within-flashblock.
  2. Even if it existed, it would be the wrong signal. Unichain's priority ordering makes
     `tx.gasprice` a strictly better and cheaper proxy for the same information.
  3. It is evadable in equilibrium. Arbitrageurs simply wait for the cheap slot, so the fee
     curve redistributes timing rather than capturing value.
- **Evidence:** `UNVERIFIED` this session — carried over from prior work. Not re-derived,
  because the decision is to *not* build it and nothing downstream depends on the reasoning
  being exactly right. If Tempo is ever revived, re-verify claim 1 from source first.
- **Consequence:** flashblock-position mechanics are out of scope permanently. Do not
  relitigate.

---

## D-0002 — Reject generic Keel (universal v4 hook safety layer, three invariants)

- **Date:** before 2026-08-28 (historical, recorded retrospectively during Phase 0)
- **Status:** rejected, closed. Directly motivates D-0003.
- **Decision:** Do not build a universal v4 hook safety layer offering three generic invariants.
- **Alternatives considered:** ship all three as opt-in modules; ship only the strongest one;
  reframe as a linting/static-analysis tool.
- **Reason:** each proposed invariant fails on its own terms.
  1. *"Price cannot move more than X per block"* — **actively harmful.** It reverts during
     genuine volatility, which is exactly when the market needs the pool to function. It traps
     LPs, and it corrupts the pool as an oracle by suppressing true price discovery. This is a
     safety feature that creates a worse hazard than the one it prevents.
  2. *"No more than X% of liquidity may exit per block"* — **not novel.** This is substantially
     ERC-7265 (Circuit Breaker), proposed in 2023. Building it again is redundant.
  3. *"Liquidity per share is monotonic"* — **not expressible.** Vanilla Uniswap v4 has no share
     concept at all. There is nothing to write the invariant against.
- **Evidence:** point 3 is corroborated by Phase 0 source reading — v4-core has no share or
  claim abstraction anywhere in the pool accounting (`docs/RECON.md` §6). Points 1 and 2 are
  carried over reasoning, `UNVERIFIED` this session; Phase 2 will independently confirm the
  ERC-7265 overlap.
- **Consequence:** "universal v4 safety layer" is a dead direction. The failure of invariant 3
  is the load-bearing one: it says the interesting property **requires** shares to exist. That
  observation produces D-0003.

---

## D-0003 — Narrow scope to hooks that have share-like claims

- **Date:** before 2026-08-28 (historical, recorded retrospectively during Phase 0)
- **Status:** active. **This scope restriction is the project.**
- **Decision:** Keel targets only v4 hooks implementing custom accounting with share-like LP
  claims — vault-style wrappers that tokenise LP positions into fungible claims.
- **Alternatives considered:** abandon the direction entirely after D-0002; broaden to "any hook
  with custom accounting"; narrow further to a single named protocol's design.
- **Reason:** D-0002's third invariant failed only because vanilla v4 has no shares. Restricting
  the domain to hooks that *do* have shares is precisely the move that makes the property
  expressible. "Any hook with custom accounting" is too broad — without a claims concept there
  is nothing to check backing against. A single named protocol is too narrow — that is a
  detector, not an invariant.
- **Evidence:** follows from D-0002. Whether the invariant actually exists inside this narrowed
  scope is still `HYPOTHESIS` and is Phase 4's job to settle.
- **Consequence:** the scope restriction is load-bearing and must be stated in every artifact,
  including the README. Keel does not claim to protect arbitrary hooks. If Phase 4 finds the
  invariant does not hold even in this narrowed class, the project is dead — there is no
  further narrowing that would not make it a detector.

---

## D-0004 — Pin v4-core from v4-periphery's own submodule, not from the v4.0.0 tag

- **Date:** 2026-08-28 (Phase 0)
- **Status:** active
- **Decision:** v4-core is pinned to `59d3ecf53afa9264a16bba0e38f4c5d2231f80bc`, which is the
  commit v4-periphery `dce236d` records in its own `lib/` tree. forge-std, solmate, and
  openzeppelin-contracts are likewise pinned to v4-core's own submodule commits rather than to
  their latest tags.
- **Alternatives considered:** pin v4-core to its only tag `v4.0.0` (`e50237c`); pin everything
  to latest tags (e.g. forge-std `v1.9.7`); use `forge install` defaults.
- **Reason:** v4-periphery has no tags at all, so it can only be pinned by commit. Its `main`
  HEAD was built against a specific v4-core commit that is **12 commits ahead of `v4.0.0`**.
  Pinning to the tag would produce a v4-core that periphery was never tested against. Taking
  the newest forge-std alongside v4-core's test harness is exactly the "HEAD of one dependency
  with an unrelated commit of another" failure mode.
- **Evidence:** `docs/RECON.md` §4.1–§4.4 — verbatim `git ls-remote` output, the raw
  `.gitmodules` and git-trees API reads that produced the pin, the GitHub compare showing
  `ahead_by=12 behind_by=0`, and a passing `forge build` + `forge test` on `CompileCanary`
  proving the set compiles and runs together.
- **Consequence:** dependency bumps are a deliberate, evidenced operation, never a `forge
  update`. To bump, re-derive periphery's pin first and re-run the canary. **`forge update` is
  forbidden** — it would silently destroy this resolution.

---

## D-0005 — Do not vendor OpenZeppelin `uniswap-hooks` yet; `BaseHook` source left open

- **Date:** 2026-08-28 (Phase 0)
- **Status:** **open decision**, to be closed in Phase 2 or Phase 6
- **Decision:** `uniswap-hooks` is not added as a dependency during Phase 0. The question of
  what Keel's hook inherits from is deferred.
- **Alternatives considered:** vendor `uniswap-hooks` v1.2.1 now and inherit its `BaseHook`;
  implement `IHooks` directly with no base contract; copy a minimal base into `src/`.
- **Reason:** two reasons to wait. (a) `FACT` `BaseHook.sol` does **not** exist in v4-periphery
  at our pin — `find lib/v4-periphery/src -name 'BaseHook.sol'` returns nothing, and there is no
  `src/utils/` directory. So the conventional import that tutorials and training data suggest is
  simply wrong here and a real choice has to be made. (b) Phase 2 must review `uniswap-hooks`
  as **prior art** anyway. Adopting it as a dependency before assessing whether it already
  solves the problem would prejudice that review.
- **Evidence:** `docs/RECON.md` §4.1 (tag `v1.2.1` = `acbd604c409a827f7f98c9517236da860c4fca1a`,
  live query) and §6.3 (`BaseHook` absent from periphery).
- **Consequence:** no hook code may be written until this is closed. Phase 2 assesses
  `uniswap-hooks` as prior art first; Phase 6 then picks the base and records the choice as a
  superseding entry. **Adding a dependency is a scope change** and needs the owner's approval
  per the vibe-coder protocol.

---

## D-0006 — Compiler settings mirror upstream Uniswap v4

- **Date:** 2026-08-28 (Phase 0)
- **Status:** active
- **Decision:** `solc 0.8.26`, `evm_version = cancun`, `bytecode_hash = none`. Default profile
  runs `via_ir = false` with `optimizer_runs = 800`; a separate `deploy` profile turns
  `via_ir = true` with `optimizer_runs = 44444444`.
- **Alternatives considered:** newest solc; `via_ir` on everywhere; `paris` evm version.
- **Reason:** our contracts compile against v4-core's sources, so the compiler must match what
  those sources are written for. `cancun` is **required**, not preferred — v4-core uses
  transient storage (`TSTORE`/`TLOAD`). Running `via_ir` off by default keeps the edit-test loop
  fast, matching v4-core's own `debug` profile; the `deploy` profile exists because bytecode
  matters for hook address mining and for verified deployments, and those must be produced under
  production settings.
- **Evidence:** `forge build` / `forge test` pass under the default profile
  (`docs/RECON.md` §4.4). `UNVERIFIED` — the `deploy` profile has not yet been exercised.
  Phase 6/10 must build under it before any address mining or deployment.
- **Consequence:** **address mining and deployment must use `FOUNDRY_PROFILE=deploy`.** Mining
  an address against default-profile bytecode and deploying `via_ir` bytecode would produce a
  hook whose address does not match its permission bits. This is a deployment-breaking trap and
  is on the `release-check` list.

---

## D-0007 — `ffi = false`

- **Date:** 2026-08-28 (Phase 0)
- **Status:** active
- **Decision:** Foundry FFI stays disabled. `fs_permissions` grants read access to `./out` only.
- **Alternatives considered:** enable FFI for richer test tooling.
- **Reason:** FFI lets any test — including one pulled in transitively from a dependency —
  execute arbitrary host commands. The convenience does not come close to justifying that on a
  machine that will later hold deployment credentials.
- **Evidence:** `foundry.toml`, `ffi = false`.
- **Consequence:** any future need for FFI is a **security change** requiring owner approval and
  a superseding entry here.

---

## D-0008 — Review subagents are read-only

- **Date:** 2026-08-28 (Phase 0)
- **Status:** active
- **Decision:** `security-reviewer`, `protocol-reviewer`, `research-reviewer`, and
  `adversarial-reviewer` are configured with a read-only tool list **and** an explicit
  `disallowedTools` denying `Write`, `Edit`, and `NotebookEdit`.
- **Alternatives considered:** give reviewers write access so they can fix what they find.
- **Reason:** a reviewer that can edit is not an independent review — it can make its own
  finding disappear, and its report stops being falsifiable. Separating "who finds" from "who
  fixes" is the whole point of the review chain. The redundant `disallowedTools` exists so that
  adding a tool to the allow-list later cannot silently grant write access.
- **Evidence:** frontmatter fields `tools` and `disallowedTools` confirmed against
  `code.claude.com/docs/en/sub-agents` on 2026-08-28 (`docs/RECON.md` §1.6).
- **Consequence:** the main session applies all fixes. Every review runs
  implement → test → `security-reviewer` → `adversarial-reviewer` → fix → test again, and each
  stage is recorded.

---

## D-0009 — Accuracy incident: mistranscribed commit sha in `docs/RECON.md`

- **Date:** 2026-08-28 (Phase 0, session 2)
- **Status:** corrected
- **Decision:** Record, rather than quietly fix, an error found in a block labelled "verbatim".
- **What happened:** `docs/RECON.md` §4.1 presented a `git ls-remote --tags` block whose final
  line read `7170eec9… refs/tags/v1.2.1`. A live re-query in session 2 showed that
  `7170eec9…` is actually `refs/tags/v1.2.0-rc.1`, and `v1.2.1` is
  `acbd604c409a827f7f98c9517236da860c4fca1a` — which is what the surrounding prose had said all
  along. The transcription dropped a line and reattached the wrong ref name.
- **Reason for recording it:** a block labelled verbatim that is not verbatim is the exact
  failure mode this project's rules exist to prevent, and it survived into a file that other
  documents treat as ground truth. Silently correcting it would destroy the signal that
  transcription — not just reasoning — is a place where errors enter.
- **Evidence:** `git ls-remote --tags https://github.com/OpenZeppelin/uniswap-hooks | grep v1.2`
  re-run 2026-08-28. The corrected block and an inline correction note are in `docs/RECON.md`
  §4.1.
- **Consequence:** **Never hand-transcribe command output.** Redirect it to the file, or paste
  it whole. Nothing downstream depended on the wrong sha (`uniswap-hooks` is not vendored, per
  D-0005), so the blast radius was zero this time. It will not always be.

---

## D-0010 — Stale submodule SHAs found in the git index

- **Date:** 2026-08-28 (Phase 0, session 2)
- **Status:** corrected
- **Decision:** Re-stage all submodules so the index records the resolved pins before the first
  commit.
- **What happened:** session 1 resolved the dependency pins (D-0004) and checked them out in the
  working tree, but the git **index** still held the earlier `forge install` defaults —
  forge-std `da5b326f…`, openzeppelin-contracts `9d0459ea…`, solmate `89365b88…`, v4-core
  `46c68346…`. `git submodule status` flagged this with a `+` prefix on four of six modules.
  The first commit would have recorded pins that contradict `docs/RECON.md` §4.3, and a fresh
  clone would not have reproduced the verified build.
- **Reason for recording it:** the evidence in `RECON.md` was correct and the working tree was
  correct, yet the artifact that a future session would actually inherit was wrong. Verifying a
  fact is not the same as verifying that the fact got persisted.
- **Evidence:** index-vs-worktree comparison run in session 2; after `git add lib/…` the two
  agree, and both match `docs/RECON.md` §4.3.
- **Consequence:** the pre-commit checklist includes `git submodule status` — **any `+` or `-`
  prefix blocks the commit.** Added to the `release-check` skill.

---

## D-0011 — `noSelfCall` forces Keel to be a cooperative library, not an observer hook

- **Date:** 2026-08-28 (Phase 1)
- **Status:** active, and **the central input to the Phase 4 kill gate**
- **Decision:** Record that a callback-based guard cannot observe the operations Keel exists to
  guard, and carry the consequence into Phase 4 rather than designing around it now.
- **What was found:** `FACT` v4 skips **every** hook callback when the hook itself is the caller.
  `lib/v4-core/src/libraries/Hooks.sol:170-175` defines `modifier noSelfCall`, applied to
  `beforeInitialize` (:178), `afterInitialize` (:187), `beforeModifyLiquidity` (:200),
  `beforeDonate` (:320), `afterDonate` (:330); the other three carry the same guard inline as an
  early return — `afterModifyLiquidity` (:217), `beforeSwap` (:253), `afterSwap` (:293).
  Proven by `test/Phase1_V4Semantics.t.sol` (9 tests passing) and corroborated by upstream's own
  `lib/v4-core/test/SkipCallsTestHook.t.sol`.
- **Why it matters:** the target class — vault-style wrappers that tokenise LP positions — owns
  its LP position and calls `poolManager.modifyLiquidity` **itself**, with users entering through
  the hook's own functions. Under `noSelfCall` those calls fire no callbacks. A guard placed in
  `afterRemoveLiquidity` is therefore structurally blind to exactly the withdrawals that mint and
  burn shares.
- **Alternatives considered:**
  1. *Guard as a separate observer hook on the same pool* — **impossible.** A pool has exactly one
     hook (`PoolKey.hooks`), and there is no mechanism by which one contract observes another's
     callbacks.
  2. *Guard in the swap callbacks only* — those do fire for external swappers, but swaps are not
     where shares are minted or burned. It would watch the wrong event.
  3. *Guard as a library/modifier the hook calls itself* — the only mechanism that can observe
     share mint/burn. **Cooperative and opt-in.**
- **Consequence:** Keel cannot be an external safety net imposed on an arbitrary hook. It can
  only be a correctness harness a hook author installs in their own code — the `SafeERC20` /
  `ReentrancyGuard` category. That is a real and defensible product category, but it is a
  **materially weaker claim** than "a runtime safety layer for Uniswap v4 hooks", and every
  artifact must stop making the stronger claim. `PROJECT.md` and `README` must say "opt-in".
- **Open:** whether a cooperative guard is worth building at all is **Phase 4's** question, and
  the `adversarial-reviewer` must be pointed directly at it. It is not settled here.

---

## D-0012 — Close D-0005: `BaseHook` exists, in OpenZeppelin `uniswap-hooks`

- **Date:** 2026-08-28 (Phase 2)
- **Status:** closes D-0005 and `docs/RECON-hooks.md` H4
- **Decision:** The hook base-contract question is answered: `BaseHook.sol` exists at
  `src/base/BaseHook.sol` in `OpenZeppelin/uniswap-hooks` v1.2.1
  (`acbd604c409a827f7f98c9517236da860c4fca1a`), alongside `BaseCustomAccounting.sol`,
  `BaseCustomCurve.sol`, and `BaseAsyncSwap.sol`.
- **Evidence:** full recursive git-tree read at the pinned SHA, `truncated: false`, 54 `.sol`
  files. Verified by the main session, not only reported by the subagent.
- **Consequence:** Phase 0's finding was correct but narrower than stated — `BaseHook` is absent
  from **v4-periphery**, not from the ecosystem. Any future hook work uses `uniswap-hooks`.
  Whether to vendor it is now moot unless the project continues in a form that needs it.

---

## D-0013 — Phase 2 outcome: Keel-as-runtime-guard is redundant. **KILL RECOMMENDED.**

- **Date:** 2026-08-28 (Phase 2)
- **Status:** **recommendation to the product owner. Awaiting decision. Phase 4 NOT started.**
- **Decision:** Recommend killing Keel in its current form — a runtime invariant guard library
  for share-issuing Uniswap v4 hooks. Do not proceed to Phase 4 invariant design or write any
  guard implementation.
- **Kill conditions triggered** (`PROJECT.md`), each with evidence:
  1. **Redundant with existing tooling.** Euler's **EVC** already ships the exact architecture
     D-0011 forces Keel into — a cooperative, opt-in, synchronous, author-installed vault status
     check, deployed and audited, with the hard part (deferral across nested/batched calls)
     already solved. **Phylax Credible Layer** is strictly more expressive: Solidity assertions
     enforced at the sequencer, seeing whole-transaction state diffs, so it defeats `noSelfCall`
     entirely at zero gas and needs no author cooperation.
  2. **A materially simpler solution provides the same value.** Five inline lines
     (`assetsAfter * supplyBefore >= assetsBefore * supplyAfter`) give the same protection with
     no dependency and better auditability — and run free in CI.
  3. **Market need insufficient.** Uniswap's own `hooklist` registry lists ~100 hooks and **zero**
     self-described share-issuing vaults; the archetype (Bunni) had $231K TVL and is shut down.
  4. **Novelty largely gone.** Trail of Bits published this exact failure pattern, named Bunni,
     and prescribed the invariant on **2026-07-30 — five weeks ago**.
- **What survives, and is genuinely unfilled** (the strongest counterargument):
  OpenZeppelin's `uniswap-hooks` — the canonical, UF-funded library — ships
  `BaseCustomAccounting` ("custom accounting and hook-owned liquidity") with **no backing
  invariant** and, verified by full tree read, **no `test/invariant/` directory at all**. Its own
  `ReHypothecationHook` documents an insolvency mode in a WARNING and guards nothing. ToB gave
  prose, not code. Trace2Inv (FSE'24) shows guards of this family block 23/27 real exploits at
  ~0.3% false positives. So a real hole exists — but it justifies **a contribution, not a
  project**, and it does not answer the market evidence.
- **Best alternative found:** ship the invariant **test kit**, not the runtime guard — a reusable
  Foundry/Medusa property harness for OZ's `BaseCustomAccounting`, formalising ToB's three prose
  invariants against the real v4 substrate, with a Bunni-shaped reconstruction proving the
  property catches what three audit firms missed. `noSelfCall` becomes irrelevant (a harness
  drives the hook's own entry points), there is no false-positive-freeze hazard, no gas cost, no
  new attack surface, and it has a natural home as a PR to `OpenZeppelin/uniswap-hooks` or
  `crytic/properties`.
- **Consequence:** no protocol code has been written, so nothing is wasted. Phases 0-3 produced
  durable, reusable evidence regardless of the decision.
- **Unresolved either way:** `RESEARCH.md` Q4 / `docs/RECON-hooks.md` H3 — converting hook-owned
  tick-range liquidity into an asset quantity without invoking an attacker-movable price. Nobody
  in the prior art has solved it; Certora sidestepped it by staying inside v4-core. **If a
  runtime guard were built anyway, this would have to be solved first or the guard is unsound as
  well as redundant.**

---

## D-0014 — Kill Keel entirely (both forms). Build **Fathom**.

- **Date:** 2026-08-28 (decision session)
- **Status:** **DECIDED.** Supersedes D-0013's "pivot to test kit" alternative.
- **Decision:** Kill Keel as a runtime guard **and** kill the invariant-test-kit pivot. Build
  **Fathom**, a counterfactual evaluation harness for Uniswap v4 fee hooks, plus one reference
  fee hook to demonstrate it.

### The fact that decided it

- `FACT` **UHI10's theme is "The Fair Flow Frontier: MEV protection and sustainable low-fee
  liquidity on Uniswap v4."** Curriculum covers dynamic fee hooks, game-theoretic and directional
  fee designs (incl. Nezlobin's), swap-ordering randomisation, fee-rebate systems, MEV auction
  hooks. Hackathon 2026-08-17 → 2026-09-03; demo day 2026-09-11.
  Source: Atrium Academy, verified 2026-08-28.
- `INFERENCE` A security/invariant test kit is **off-theme**. It would score ~2/10 on
  Uniswap/Atrium alignment — a 15%-weighted criterion — and judges would rightly ask why it was
  submitted to a fee-and-MEV hookathon. This kills the D-0013 pivot for this venue, independently
  of its technical merit.

### Kill test run BEFORE committing (the Tempo lesson applied)

The leading on-theme candidate was a priority-fee "MEV tax" hook (Paradigm's *Priority is All
You Need*, applied as a drop-in hook). It was killed by measurement in ten minutes:

- `FACT` Sampled 31 Unichain blocks, 223 user transactions: **only 8 (3.59%) paid any priority
  fee at all.** Median priority fee **0**, p95 **0**, max 1,450,000 wei. Base fee is a flat
  500,000 wei across all blocks sampled.
- `FACT` **Unichain averages 8.2 transactions per block** (max 10 observed). The chain is not
  congested, so there is no priority auction to tax.
- `INFERENCE` A priority-fee-keyed mechanism collects ~nothing on Unichain today and cannot
  discriminate arbitrage from retail flow. **This also weakens D-0001's claim** that `tx.gasprice`
  is "a strictly better and cheaper signal" — better than a flashblock index, yes, but
  empirically near-useless on Unichain because there is no contested priority market.

### Feasibility verified before committing

- `FACT` Unichain v4 `PoolManager` emitted **3,448 `Swap` events in the last 10,000 blocks**
  (164 in the last 1,000). Block time **1.00 s** → **~30,000 real v4 swaps/day**. Ample trace data.
- `FACT` Archive reads verified back to block 1,000,000 in Phase 0 (`docs/RECON.md` §3.3).
- `FACT` Dynamic-fee mechanics verified from source in Phase 1: `DYNAMIC_FEE_FLAG = 0x800000`,
  `OVERRIDE_FEE_FLAG = 0x400000`, fee returned from `beforeSwap` and only honoured for dynamic-fee
  pools (`Hooks.sol:263`, `LPFeeLibrary.sol:15-19`).

### The gap Fathom fills

- `FACT` v3 LP backtesters exist (DefiLab, academic CLMM frameworks). Hacken ships a v4 hook
  **correctness/security** harness. Metrix Finance does forward-looking LP fee **projections**.
- `INFERENCE` **Nothing answers "does this fee hook actually leave LPs better off than the vanilla
  pool, on real historical flow?"** Every fee-hook proposal asserts it; none measures it.
- `FACT` The Uniswap Foundation is working with OpenZeppelin on hook data standards explicitly to
  "give LPs a complete risk-reward picture" — the Foundation cares about this measurement problem.

### Why this is the right call

Competing on *mechanism novelty* against Angstrom/Sorella (uniform-price batching + priority tax,
production team) and a cohort full of taught Nezlobin hooks is a losing game in 30 hours. Fathom
competes on the axis almost nobody contests: **evidence**. It is on-theme (it evaluates exactly
the fee designs the theme is about), it is infrastructure the whole cohort and the Foundation
would use, and its demo can falsify a popular hook design live.

### Consequence

- No Keel guard code is written. Phases 0-3 evidence is retained and reused: the v4 semantics
  work (Phase 1) directly supports Fathom, and the rigour discipline (replay vs reconstruction,
  FACT/INFERENCE tagging) becomes a selling point rather than overhead.
- `PROJECT.md` must be rewritten for Fathom. `SECURITY.md`/`THREAT_MODEL.md` shrink drastically —
  Fathom is an off-chain/test-time tool plus one simple fee hook, not a guard in the path of funds.

---

## D-0015 — Supersedes D-0014. Build **Ballast**, not Fathom.

- **Date:** 2026-08-28 (decision session, second pass)
- **Status:** **DECIDED. This is the project.**

### Correction to D-0014

D-0014 killed the priority-fee mechanism on the basis that "only 3.59% of Unichain transactions
pay any priority fee." **That inference was wrong, and the error was in the denominator.**

Re-measured over 121 blocks / 930 user transactions, segmented by destination:

- `FACT` The zero-priority population is almost entirely **system and bot noise**: 121 txs to the
  zero address, 121 to `0xd44f…6a29` (one each per block), and 600 to a single address
  `0x3c3a8a41…` (~5/block). These are not swap flow.
- `FACT` **Every one of the 21 Universal Router transactions sampled paid a priority fee, and all
  21 paid exactly 1,450,000 wei** — a flat wallet/interface default. Universal Router
  (`0xef740bf2…`) is verified in `docs/RECON.md` §7.
- `FACT` `0x099b1a87…` — a 45KB contract, i.e. a bot — sent 31 transactions with priority fees
  ranging from **1 wei to 179,440,586 wei**. Other competitive bidders paid 18.9M, 20.5M, 23.5M wei.
- `FACT` Base fee is a flat 500,000 wei. Max observed priority is **359× base** and **123× the
  retail default**.

`INFERENCE` **Priority fee is a clean, free, on-chain discriminator between retail and searcher
flow on Unichain.** Retail pays a constant interface default; searchers bid variably and orders
of magnitude higher. The signal is not absent — it is concentrated in exactly the flow that
matters.

### Why the mechanism is sound *specifically* on Unichain

- `FACT` Unichain's sequencer is a **TEE-based block builder (Rollup Boost, Uniswap Labs +
  Flashbots)** and **"the TEE orders transactions based purely on priority fees."** Flashblocks
  produce 200ms sub-blocks inside TEEs enforcing priority-by-fee ordering.
  Sources: `blog.uniswap.org/rollup-boost-is-live-on-unichain`,
  `blog.uniswap.org/flashblocks-are-live`, `writings.flashbots.net/introducing-rollup-boost`.
- `INFERENCE` Because ordering is purely priority-fee-based and TEE-attested, there is **no side
  channel** — no builder bribe, no coinbase transfer — by which a searcher can buy priority
  without revealing it in `tx.gasprice`. This is Paradigm's "Priority is all you need"
  precondition, and Unichain satisfies it *verifiably*. A fee keyed on priority fee is therefore
  **incentive-compatible and non-circumventable there**, which is not true on Ethereum L1.
- `INFERENCE` Corroborating behavioural evidence: searchers pay up to 359× base fee on a chain
  averaging **8.2 transactions per block**. On an uncongested chain that is only rational if
  priority fee buys ordering. The observed bidding is itself proof the ordering rule binds.

### Mechanism verified from source (Phase 1 + this session)

- `FACT` `Hooks.sol:263` — `if (key.fee.isDynamicFee()) lpFeeOverride = result.parseFee();`
- `FACT` `Pool.sol:303-304` — `params.lpFeeOverride.isOverride() ? removeOverrideFlagAndValidate() : ...`
- `FACT` `LPFeeLibrary.sol` — `DYNAMIC_FEE_FLAG = 0x800000` (:15), `OVERRIDE_FEE_FLAG = 0x400000`
  (:19), `MAX_LP_FEE = 1000000` (:25), `isOverride` (:61), `removeOverrideFlagAndValidate` (:75).
- `INFERENCE` A hook can therefore set a **per-swap** LP fee from `beforeSwap`, computed from
  `tx.gasprice - block.basefee`, with no oracle and no external call.

### Ecosystem alignment

- `FACT` **PFDA (Protocol Fee Discount Auction) is live in 2026** under UNIfication: it auctions
  the right to swap without paying the protocol fee, burning the proceeds, explicitly to
  "internalize MEV that would otherwise go to searchers or validators." Stated effect: **+$0.06
  to +$0.26 LP return per $10k traded, against typical LP returns of -$1.00 to +$1.00.**
- `FACT` UNIfication states "PFDA, v4, aggregator hooks, and bridge adapters ... are in progress."
- `INFERENCE` Uniswap is itself building MEV internalisation and wants it in v4 hooks. Ballast is
  the pool-level analogue that routes the captured value to **LPs** rather than the UNI burn.

### Why not Fathom

`INFERENCE` Fathom is a measurement tool, not a hook, at a *hookathon*; its novelty rests on
being "the first v4 backtester," which invites "another backtester" and requires judges to trust
a counterfactual methodology they cannot check in two minutes. Ballast keeps Fathom's real
advantage — measured evidence nobody else has — and attaches it to a working hook. **The
measurement becomes the proof, not the product.**

### Consequence

`PROJECT.md`, `SECURITY.md`, and `THREAT_MODEL.md` are rewritten for Ballast. Keel's guard work
is dead; Phase 1's v4 semantics evidence and the measurement discipline carry forward directly.

---

## D-0016 — Ballast killed by its own day-one test. Final decision: **Windward**.

- **Date:** 2026-08-28 (decision session, third pass)
- **Status:** **FINAL. Supersedes D-0015. Begin implementation.**

### Ballast is dead — the hypothesis was inverted

Day-one kill test, 745 swaps / 690 txs / 530 blocks over a 3,000-block Unichain window,
each swap joined to its transaction's priority fee:

| Group | n | median priority | % zero |
|---|---|---|---|
| Retail (Universal Router) | 318 | **1,450,000 wei** | 0% |
| Arb proxy (non-router, ≥2 swaps in tx) | 40 | **4,824 wei** | 42% |

- `FACT` **Retail pays 301× the median arbitrage transaction.**
- `FACT` **82% of arbitrage transactions pay less priority fee than the median retail swap.**
- `INFERENCE` A priority-keyed fee would **tax retail and subsidise arbitrage** — the exact
  inverse of the design intent. D-0015's inference was wrong. Ballast is killed.
- `INFERENCE` Cause: at 8.2 txs/block Unichain is uncongested, so an arbitrageur wins the race
  paying ~nothing. "Priority is all you need" requires a *contested* auction; Unichain has none.

### The generalised finding — the real result of this session

Five independent measurements of Unichain v4, all pointing the same way:

- `FACT` 3.6-8.9% of transactions pay any priority fee; median and p90 are 0.
- `FACT` Arbs pay 301× less priority than retail (above).
- `FACT` **Zero JIT events** — no add/remove by the same sender/pool/range within 2 blocks
  across 109 `ModifyLiquidity` events.
- `FACT` **3 unique LP addresses** in the window, one of which is the PositionManager.
- `FACT` **95.4% of swaps are the only swap for their pool in their block**; just 25% of blocks
  contain more than one swap at all.
- `FACT` The busiest pool (312 swaps) has near-identical swap sizes (p10 2.11M, p90 2.69M) in a
  53-tick range, and its flow **mean-reverts** (+0.80bps after a sell) rather than trending.

`INFERENCE` **Unichain v4 has essentially no MEV microstructure today.** Any mechanism that
depends on contention — priority auctions, JIT races, intra-block ordering, toxic-flow
detection — has nothing to bite on. This is why seven successive candidates died.

### Mechanisms eliminated, with cause

| Candidate | Killed by |
|---|---|
| Keel runtime guard | Redundant (EVC, Phylax); empty market; off-theme (D-0013) |
| Keel invariant test kit | Off-theme for a fee/MEV hookathon (D-0014) |
| Ballast priority-fee tax | Signal inverted: arbs pay 301× less than retail |
| Nezlobin directional fee | Measured signal mean-reverts, not trends |
| First-of-block surcharge | 95.4% of swaps are already first-of-block |
| JIT protection | OZ ships `LiquidityPenaltyHook` (311 lines, complete) |
| am-AMM auction hook | Already built by **UHI 1st Cohort (2024)** |

### Decision: build Windward

`INFERENCE` Mechanism novelty is not achievable in 30 hours — 10 cohorts, OZ's library, and
production teams have taken every clean idea. The remaining winnable axes are **execution
quality** and **evidence**. Windward takes both, and is correct by construction regardless of
microstructure:

**A volatility-adaptive dynamic-fee hook implementing the optimal LVR-minimising fee from the
2025-26 stochastic-control literature, built on OZ's `BaseDynamicFee`, validated by a twin-pool
simulation harness, and framed by the Unichain microstructure study above.**

- `FACT` OZ `uniswap-hooks` ships fee **base classes** (`BaseDynamicFee`, `BaseOverrideFee`,
  `BaseDynamicAfterFee`) but **no concrete fee strategy**. The strategy layer is unoccupied.
- `FACT` Recent literature exists and is unimplemented on v4: arXiv 2506.02869 "Optimal Dynamic
  Fees in Automated Market Makers"; arXiv 2606.21769 "Optimal Dynamic Fees for AMMs: A
  Stochastic Control Approach to Loss-Versus-Rebalancing".
- `INFERENCE` The hook reads only the pool's own tick history — no oracle, no priority fee, no
  external call, no custom accounting, no returns-delta bits. Lowest possible correctness risk,
  and immune to every failure that killed the previous seven.

### Why this survives the tests that killed the others

It makes **no claim about current Unichain flow.** Its justification is theoretical (LVR is a
structural property of every AMM, not a microstructure artefact) and its validation is a
controlled simulation across regimes I generate. The microstructure study becomes the *framing*
— why the hook cannot rely on contention signals — rather than a load-bearing premise.

---

## D-0017 — Three data-handling errors of mine. D-0016's mean-reversion FACT is WRONG.

- **Date:** 2026-08-28 (Windward audit)
- **Status:** corrections of record. **D-0016's "mean-reverts" claim is retracted.**

### E-1 — Swap direction convention inverted (retracts a D-0016 `FACT`)

`FACT` `lib/v4-core/src/PoolManager.sol:241-250` emits `Swap` with `delta.amount0()`, which is the
**caller's** BalanceDelta — positive means the pool owes the caller, i.e. **the caller received
token0** (a buy). The natspec at `lib/v4-core/src/interfaces/IPoolManager.sol:85` says "the delta
of the currency0 balance of the pool", which is the opposite sign. **The natspec is misleading;
the code is authoritative.**

My analysis classified `amount0 > 0` as `zeroForOne` (a sell). That is inverted.

**Consequence:** D-0016 records, tagged `FACT`, that the busiest pool's flow *"mean-reverts
(+0.80bps after a sell)"*. With the correct convention that observation is **+0.80bps after a
buy — i.e. momentum, not mean reversion.** Independently confirmed: AC(1) of signed swap-to-swap
tick returns is **+0.612** (pool 1) and **+0.374** (pool 2). **That D-0016 `FACT` is retracted.**

### E-2 — int24 tick sign-decoding (fixed in commit `cc58e3e`)

`FACT` 231/745 tick values (31%) were decoded with a 24-bit sign convention; the ABI sign-extends
`int24` across a full 32-byte word, so negative ticks decoded as ~2^256. Fixed. D-0016's
"53-tick range" figure is **unaffected** — pool 1's ticks are positive (22275..22328) and decoded
correctly. Recorded here because commit `cc58e3e` was the only prior record and a decision log is
where this class of error belongs (cf. D-0009, D-0010).

### E-3 — priority-fee denominator (already recorded in D-0016)

Included for completeness: the first priority-fee reading used all transactions as the
denominator rather than swap flow, inverting the conclusion. Corrected within D-0016.

### What this means

`INFERENCE` Three data errors in one session, all in analysis code that was **never committed**.
Every `FACT` in D-0014/15/16 was produced by ad-hoc scratchpad scripts that no longer exist and
cannot be re-run or checked by anyone. That is the root cause, and it is a process failure, not
bad luck: **no analysis that produces a `FACT` may remain uncommitted.** Any study shipped from
this repo must carry its collection and analysis code.

`INFERENCE` The retraction of E-1 **removes the empirical leg of the adversarial reviewer's
strongest argument** — that transient impact from benign flow dominates, so Windward taxes the
good flow. On the corrected data, moves **persist**: Var(permanent@K)/Var(immediate) rises from
3.2 (K=1) to 79 (K=20). The theoretical concern (an out-and-back noise round trip generates two
squared observations for zero LVR, while an informed move generates one) still stands as a
mechanism-level objection, but it is **not** supported by this dataset.

`UNVERIFIED` Whether momentum or mean reversion is a property of Unichain v4 generally. The
sample is 50 minutes in a single trending regime; AC(1)=+0.612 is inflated by a one-directional
drift of 53 ticks. **This dataset cannot settle it.**

---

## D-0018 — Windward kill gate: **KILL the economic thesis.** Keep the code as an instrument.

- **Date:** 2026-08-28 (post-audit kill gate)
- **Status:** **DECIDED.** Three reviewers run; all findings below verified by the main session.
- **Decision:** Kill the claim *"a volatility-scaled fee makes LPs better off."* Do not delete
  `WindwardHook.sol` / `Volatility.sol`; demote them from product to **measurement instrument**.

### Verified by live test (`test/WindwardAttack.t.sol`, 3 passing)

| # | Finding | Evidence |
|---|---|---|
| W-01 **Critical** | The fee is **evadable in the same transaction by the trader it targets.** 30 dust swaps in one block drove the fee from **10000 → 500 pips, a 20× suppression**, for gas. Decay is applied per *observation*, not per unit time, so each no-move swap multiplies the estimate by (1−α). | `test_ATTACK_dustSwapsResetTheFeeToTheFloor` |
| W-02 **High** | **No attacker required.** One ordinary large swap pins the pool at the 1% ceiling — and it is **still at the ceiling seven days later**, because nothing decays with time. | `test_ATTACK_oneHonestLargeSwapPinsPoolAtCeiling` |
| W-03 **High** | Across **40 escalating swaps the hook charged exactly one distinct fee value.** Double integer truncation in `sigma()` destroys the signal. | `test_ATTACK_feeIsA200PipLadderNotACurve` |

### Verified against the real dataset

`FACT` Replaying the shipped algorithm over the real Unichain tick series: the fee sits at the
floor **90.4% / 80.8% / 96.4%** of swaps for the three busiest pools, **never once** reaches the
ceiling, and 52–85% of observations round to zero volatility. **On real flow Windward is
bit-for-bit a static fee.**

`FACT` The headline test `test_windwardEarnsMoreThanStaticFeeOnVolatileFlow` forces identical
volume through both pools and asserts more fee growth. **It proves 10000 > 500.** It contains no
demand elasticity, no LP PnL, and no counterfactual for flow that would have left. It is not
evidence and must not be presented as such.

### Verified by protocol review

`FACT` **F-1 (High):** the constructor checks only that the four returns-delta bits are *clear*.
It never verifies the three action flags are *set*. Deployed at an address missing
`BEFORE_SWAP_FLAG`, a dynamic-fee pool falls back to `slot0.lpFee`, which v4 seeds to **0** —
**every swap is fee-free forever, silently.** `Hooks.validateHookPermissions` exists for exactly
this and was not called.

### My own documentation was false

`FACT` `Volatility.sol:22-29` claims `MIN_DT` "stops a same-second burst … an attacker could use
to drive the fee to its ceiling." `MIN_DT = 1` clamps `dt` **up** to 1, which produces the
**largest** possible observation. The comment asserts a security property the code inverts.
`FACT` `MAX_OBSERVATION` is inert: the maximum reachable `sq` is only 3.15× the cap, so it never
binds for any swap that has ever occurred.
`FACT` The `sqrt` correctness argument is wrong (the initial guess is *below* the root, not
above). The function is correct for a different reason.

### Why this is a kill and not a fix

`INFERENCE` W-01, W-02, W-03 and F-1 are each individually repairable — time-based decay, WAD
precision, `validateHookPermissions`. Two of those repairs were prototyped and do produce a
responsive fee curve on real data (125 distinct values, p10–p90 623–709). **But repairing the
instrument does not establish the claim.** After every fix, the question *"why does this make LPs
better off?"* would still be unanswered: there is no LP-PnL model, no demand-elasticity
assumption, and no dataset capable of supporting one — 50 minutes, one regime, three of my own
data-handling errors (D-0017). With ~25h to the deadline, that evidence cannot be produced, and
the honest prior after seven dead candidates is that it would come back negative.

`INFERENCE` The adversarial reviewer's strongest argument — that the estimator over-weights
transient impact from the flow LPs profit from — **lost its empirical leg** when D-0017 retracted
the mean-reversion finding; on corrected data moves persist. So the mechanism is **not refuted in
theory**. It is refuted **in this implementation, on this data, in this time budget.**

### What ships instead

The **Unichain v4 microstructure study** as the primary artifact, with the hook retained as the
instrument that produces its sharpest result: *"we built the volatility-adaptive fee hook the
ecosystem keeps proposing, and on real Unichain flow it never leaves the fee floor."*

Non-negotiable preconditions, in order:
1. **Commit the collection and analysis code.** Every `FACT` in D-0014/15/16 came from scratchpad
   scripts that no longer exist (D-0017 root cause). Nothing ships until it is reproducible.
2. Widen the sample well beyond 50 minutes; re-run every statistic after the D-0017 fixes.
3. Relabel or delete the tautological headline test.
4. Rewrite `SECURITY.md` / `THREAT_MODEL.md`, which still describe a runtime guard that no longer
   exists. The governing property is no longer "never touches accounting": the **fee override is
   an accounting-affecting lever**, steerable between 500 and 10000 pips by W-01/W-02.

---

## D-0019 — Windward is a HEURISTIC. Retract the "optimal / LVR-minimising" claim.

- **Date:** 2026-08-28 (Block 4, honest claims)
- **Status:** **supersedes the mechanism description in D-0016.**

D-0016 described Windward as *"implementing the optimal LVR-minimising fee from the 2025-26
stochastic-control literature."* **That claim is withdrawn.** It was never true and must not
appear in the repo, the README, or the deck.

`FACT` What the literature models and what Windward measures are different objects:

| The models (Milionis–Moallemi–Roughgarden; arXiv 2506.02869; arXiv 2606.21769) | Windward |
|---|---|
| σ of an **exogenous efficient price** | realised variance of the **pool** price |
| continuous arbitrage, continuous rebalancing | discrete swaps at irregular intervals |
| closed-form optimal fee under stated assumptions | a monotone map `fee = clamp(feeMin + k·σ)` |
| an oracle or an exogenous price process is assumed | pool tick history only |

`INFERENCE` Windward implements **none** of the models' preconditions. It is *motivated by* the
observation that LVR grows with price variance; it does not implement any published optimal
policy, and `feePerSigma` has no derivation — it is a free parameter.

`FACT` The pool-price realised variance Windward measures also contains **transient price impact
from uninformed flow**, which contributes no LVR. An out-and-back noise round trip produces two
squared observations for zero efficient-price movement; a one-way informed move produces one.
The estimator therefore does not cleanly isolate the quantity LVR depends on.

**Standing rule for this repository:** the word *optimal* may not be used to describe Windward
anywhere. Paper titles quoted as citations are exempt. The permitted description is:

> A volatility-adaptive fee **heuristic** for Uniswap v4, computed from the pool's own tick
> history. Motivated by the LVR literature; **not** an implementation of any optimal policy from
> it, and **not** validated as improving LP outcomes.

`INFERENCE` The economic claim remains **unvalidated**. Establishing it would need, at minimum:
an LP-PnL comparison rather than a fee-revenue comparison, an explicit demand-elasticity
assumption for the flow that leaves at a higher fee, and a decomposition showing the fee
correlates with the *permanent* rather than the transient component of price impact. None of
those exists, and the README must say so.

---

## D-0020 — 7-day re-measurement. **Three headline claims did not survive. Retracted.**

- **Date:** 2026-08-28 (Block 2)
- **Status:** supersedes the measurements in D-0016 and D-0017.
- **Sample:** blocks 56549879–57154678, **7.00 days**, **426,807 swaps**, 127,870 liquidity
  events, 232 pools, 6,000 sampled transactions. Previously: 50 minutes, 745 swaps, 40 arbs.
  **573x more swap data.** Reproduce with `analysis/run.sh`; figures read from `data/stats.json`.

### Corrections — every number that changed

| Claim | 50-min sample | 7-day sample | Verdict |
|---|---|---|---|
| Retail pays **301x** the median arb in priority fees | 301x (n=40) | **1.4x** (C1, n=9) / **17.4x** (C2, n=619) | **RETRACTED.** The direction holds; the magnitude was an artefact of a 40-transaction window. Never quote 301x again. |
| % of arbs paying below the retail median | 82% | 100% (C1) / **83.8%** (C2) | Survives |
| JIT events | **0** | **19** | **RETRACTED.** "Zero JIT on Unichain" is false; it was absence of evidence in a 50-minute window. |
| Distinct LP addresses | **3** | **46** | **RETRACTED.** |
| % swaps alone in their block for their pool | 95.4% | **82.7%** | Overstated. Corrected figure still notable. |
| Distinct pools with swaps | 41 | **232** | Corrected |
| Price dynamics | "mean-reverting" (D-0016), then "momentum" (D-0017) | **Pool-dependent**: 2 of the 5 busiest mean-revert (AC(1) −0.139, −0.133; VR<1), 3 trend (AC(1) +0.114 to +0.186; VR>1) | **BOTH earlier claims RETRACTED.** Neither is a property of the chain. |

`INFERENCE` The pattern is consistent: **every claim that over-generalised from the 50-minute
window shrank or reversed.** The surviving qualitative statement is narrow — retail flow entering
via the Universal Router pays a flat 1,450,000 wei default while most arbitrage-classified flow
pays less — and even that is 1.4x–17.4x, not 301x, depending entirely on the classifier.

### Arbitrage classifier — assumptions now stated explicitly

Two classifiers are reported side by side because there is no ground truth:

- **C1, same-pool round trip** (n=9): high precision, but misses multi-pool cyclic arbitrage
  entirely, so it under-counts badly. n=9 is too small to carry a claim.
- **C2, multi-swap non-Universal-Router** (n=619): **known false positives** — a multi-hop retail
  trade routed via any non-UR aggregator (1inch, CoW, Odos, Matcha) is indistinguishable from a
  cyclic arb under this rule, so it over-counts.
- **Retail proxy** = `tx.to == Universal Router` (n=1,705). **Known false positives:**
  sophisticated actors also route through the UR; the observed max UR priority fee is
  464,058,459 wei, 320x the median, which is certainly not retail.

`INFERENCE` The truth lies between C1 and C2. Any headline must quote **both bounds**, never one.

### What this does to the hook's replay

`FACT` The same 426,807 swaps run through both implementations:

| | shipped v1 | repaired |
|---|---|---|
| observations rounding to zero | 44.9–79.6% | **2.7–41.2%** |
| swaps charged at the fee floor | 20.6–79.5% | **0.0%** |
| distinct fee values charged | 21–49 | **437–2,349** |
| fee p10 / median / p90 (busiest pool) | — | 636 / 761 / 1331 pips |

`INFERENCE` This is the one result that strengthened. The W-03 truncation defect is not a
theoretical concern: on real flow the original implementation charged the floor on up to 79.5% of
swaps, and the repair produces a genuinely continuous fee curve. **This is the demo.**

`UNVERIFIED` That the repaired fee curve is *better for LPs*. It is a different curve, measured
on real flow. Nothing here establishes a benefit — see D-0019.
