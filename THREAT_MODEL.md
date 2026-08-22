# THREAT_MODEL.md — Keel

Analysis. `SECURITY.md` holds the policy that follows from it.

**Status: Phase 0 skeleton.** The protocol-level attack vectors below are stated at the level of
detail Phase 0 supports. Phase 4 (invariant design) and Phase 7 (adversarial testing) must
expand §4 and §5 substantially. Anything not yet analysed is marked `UNVERIFIED` rather than
assumed safe.

---

## 1. Assets

What an attacker is trying to obtain or destroy.

| # | Asset | Held by | Loss looks like |
|---|---|---|---|
| A1 | Tokens backing the guarded hook's share claims | PoolManager / the hook | Claims redeemable for more than their backing; last redeemers get nothing. |
| A2 | The integrity of the hook's share↔asset accounting | The hook | Corrupted state that still settles cleanly at the PoolManager. **This is Keel's target.** |
| A3 | Availability of withdrawals | The hook + Keel | **Keel itself can destroy this.** A false positive freezes user funds. Treated as a first-class asset, not an afterthought. |
| A4 | Deployment credentials | The owner's Foundry keystore | Malicious deployment or upgrade under our identity. |
| A5 | The project's evidentiary claims | This repo | A false `FACT` propagating into a deployed decision. |

## 2. Attackers

| # | Attacker | Capability | Motive |
|---|---|---|---|
| T1 | Economic attacker | Arbitrary calls, arbitrary ordering, flash loans, repetition, sandwiching. Can call the hook thousands of times in one transaction. | Extract A1. |
| T2 | Griefer | Same access, no profit requirement | Destroy A3 — make Keel revert on honest users. |
| T3 | Malicious hook author | Writes the guarded hook; Keel is integrated into code they control | Make Keel appear to endorse an unsafe hook. |
| T4 | Malicious token | Controls an ERC-20 in the pool; can reenter, rebase, take fees on transfer, lie about balances | Corrupt Keel's view of "assets" (A2). |
| T5 | Compromised developer machine | Local file and network access | A4, and injecting a false `FACT` into A5. |
| T6 | **Us** | Full write access, time pressure, stale training data | Every asset. Empirically the most active threat so far — see D-0009, D-0010. |

## 3. Trust boundaries

See `SECURITY.md` §2 for the table. The critical boundary: **the guarded hook's accounting is
untrusted input to Keel.** Keel must never derive its notion of "assets" from a number the
guarded hook simply asserts, or it is checking a value against itself.

`UNVERIFIED` What Keel can read that is *not* under the hook's control — PoolManager state via
`StateLibrary`, raw token balances, and little else — is a Phase 4 question and constrains which
invariants are expressible at all. **This is the single most important open question in the
threat model.**

## 4. Attack vectors

### 4.1 Against the guarded protocol (what Keel is meant to catch)

| # | Vector | Status |
|---|---|---|
| V1 | Rounding-direction error compounded over many repetitions to corrupt accounting, then extracted via a swap. | `UNVERIFIED` — the motivating class. Phase 3 must establish it from primary sources. |
| V2 | Mint claims without depositing matching assets. | `UNVERIFIED` — Phase 4. |
| V3 | Burn claims and withdraw more assets than backing. | `UNVERIFIED` — Phase 4. |
| V4 | Donation / direct transfer that inflates apparent backing, then a claim against it. First-depositor share inflation is the classic instance. | `UNVERIFIED` — Phase 4. |
| V5 | Reentrancy through a token callback, observing or acting on a half-updated share↔asset state. | `UNVERIFIED` — Phase 4/7. |
| V6 | Fee-on-transfer or rebasing token making "assets received" ≠ "assets credited". | `UNVERIFIED` — Phase 4 must state whether these are in scope. |

### 4.2 Against Keel itself (what Keel might cause)

| # | Vector | Severity | Status |
|---|---|---|---|
| V7 | **False positive freezes withdrawals.** A legitimate sequence trips the invariant and users cannot exit. | **Critical.** Worse than the bug Keel prevents. An explicit kill condition. | Open. Phase 4 enumerates legitimate scenarios; Phase 7 fuzzes for them. |
| V8 | Griefer engineers a cheap state that makes Keel revert for everyone else (T2). | **Critical** — same outcome as V7, reached deliberately. | Open, Phase 7. |
| V9 | Keel reads a value the attacker controls and is fooled into passing. Evasion. | High | Open, Phase 4. |
| V10 | Gas overhead makes guarded pools uncompetitive, or pushes a swap path over the block gas limit. | Medium, and a kill condition if unreasonable. | Phase 9 measures it. |
| V11 | Keel's own arithmetic has a rounding or overflow bug. | High | Mitigated by `.claude/rules/solidity.md` + review chain. Not yet tested. |
| V12 | Hook address mined against default-profile bytecode but deployed from `via_ir` bytecode → permission bits do not match the deployed code. | High, deployment-breaking | **Mitigated by design:** D-0006 mandates `FOUNDRY_PROFILE=deploy`; on the `release-check` list. |
| V13 | Keel accidentally returns a non-zero delta and alters accounting. | **Critical** | **Mitigated by design:** returns-delta address bits must be clear, asserted by test in Phase 6. `SECURITY.md` §1. |
| V14 | Unbounded loop on the swap path enables gas-limit DoS. | High | Prohibited by rule. Not yet enforced by test. |

### 4.3 Against the development process

| # | Vector | Status |
|---|---|---|
| V15 | Stale training data produces a plausible but wrong API, address, or signature. | **Mitigated:** verify-from-source rule; `docs/RECON.md` §6.2 already caught `SwapParams` moving and `BaseHook` being absent. Ongoing. |
| V16 | Transcription error puts a wrong value into an evidence file. | **Occurred** — D-0009. Mitigation: never hand-transcribe; redirect output to file. |
| V17 | A verified fact is not persisted to the artifact a future session inherits. | **Occurred** — D-0010 (stale submodule index). Mitigation: `git submodule status` in the pre-commit checklist. |
| V18 | Secret exfiltration via a subprocess that Claude Code's Read/Edit deny rules do not cover. | **Accepted risk — see §6.** |
| V19 | A hook or permission rule so brittle it breaks normal development, and gets disabled wholesale — losing all protection. | Mitigated by keeping hooks few, simple, and tested (`docs/RECON-guard-hook.md`). |
| V20 | Owner cannot audit the code, so an error ships silently. | **Structural, unmitigable by the owner.** The review chain and this file are the compensating control. |

## 5. Mitigations map

| Threat | Control | Type |
|---|---|---|
| V13 | Returns-delta address bits clear; asserted by test | Preventive, testable |
| V12 | `FOUNDRY_PROFILE=deploy` for mining + deploy | Procedural, on checklist |
| V7, V8 | Phase 4 false-positive enumeration; Phase 7 fuzz + invariant runs | Detective → kill signal |
| V11, V14 | `.claude/rules/solidity.md`; `security-reviewer` | Preventive |
| V9 | `adversarial-reviewer`, whose sole job is to argue Keel is wrong | Detective |
| A4 | Keystore-only keys; `deny` rules on `.env`; `ask` on any broadcast | Preventive |
| A5 | FACT/INFERENCE/HYPOTHESIS/UNVERIFIED tagging; `docs/RECON.md` as evidence of record | Detective |
| T6 | The entire rule set in `CLAUDE.md` | Preventive |

## 6. Explicitly accepted risks

Accepted deliberately. Each is a decision, not an oversight.

- **R1 — `.env` protection is incomplete.** `FACT` Claude Code's `Read`/`Edit` deny rules cover
  the built-in file tools and the file commands it recognises in Bash (`cat`, `head`, `tail`,
  `sed`), but **not** an arbitrary subprocess (a Python or Node script that opens the file).
  Accepted because closing it fully would mean denying `Bash` outright, which makes the project
  undeliverable. Compensating control: no real secret is in `.env` until Phase 10, and
  deployment keys live in the keystore, never in `.env`.
- **R2 — Uniswap v4 core is trusted.** Not audited by us. Accepted: it is the platform.
- **R3 — Public RPC is trusted for reads.** `https://mainnet.unichain.org` could serve false
  state. Accepted for research; the PoolManager address was cross-checked against a second
  contract's `poolManager()` (`docs/RECON.md` §7). Any address used in a deployment must be
  re-verified from at least two independent sources.
- **R4 — Not audited.** Time-boxed prototype. Must not secure real funds. Stated in the README.
- **R5 — Historical decisions D-0001/D-0002 rest on unverified reasoning.** Accepted because
  both are decisions *not* to build something; nothing downstream depends on them being exactly
  right. Revisit only if either direction is revived.

## 7. Unresolved threats

Open. Not accepted, not mitigated — **must** be closed before any claim that Keel works.

- **U1** Whether a false-positive rate near zero is achievable at all (V7). Kill condition.
- **U2** What Keel can read that is not attacker-controlled (§3). Determines expressibility.
- **U3** Whether rebasing and fee-on-transfer tokens are in scope, or an explicit limitation.
- **U4** Whether the invariant is evadable by an attacker who knows it (V9).
- **U5** Real gas cost (V10).
- **U6** `UNVERIFIED` Identity of the Unichain PoolManager owner,
  `0x2BAD8182C09F50c8318d769245beA52C32Be46CD`. It controls protocol fees. Phase 1.
