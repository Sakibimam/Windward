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
