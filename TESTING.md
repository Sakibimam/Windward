# TESTING.md — Keel

**Status: Phase 0.** Only the build canary exists. This file is the plan and the standing rules;
each phase fills in its section and records evidence.

## Standing rules

- **Never weaken or delete a test to make a suite pass.** Fix the code, or record in
  `DECISIONS.md` why the test was wrong.
- A test that has never failed has proven nothing. For each guard, write the test that fails
  when the guard is removed, and confirm it actually fails.
- Every phase ends with a **green build** and an updated `CURRENT_STATE.md`.
- Record the last passing and last failing test in `CURRENT_STATE.md`. Keep them honest.
- Naming: `test_<behaviour>`, `testFuzz_<behaviour>`, `test_revert_<condition>`,
  `invariant_<property>`.
- `INFERENCE` Both the false-negative and the **false-positive** direction must be tested for
  every invariant. Only testing that the guard catches bad states would miss the project's
  single biggest risk (V7 — a false positive freezing withdrawals).

## Commands

| Purpose | Command |
|---|---|
| Build | `forge build` |
| Test | `forge test` |
| Verbose | `forge test -vvv` |
| Single test | `forge test --match-test <name> -vvv` |
| Deep fuzz / invariant | `FOUNDRY_PROFILE=deep forge test` |
| Coverage | `forge coverage` |
| Gas snapshot | `forge snapshot` |
| Format | `forge fmt` |
| Fork test | `forge test --fork-url $UNICHAIN_RPC_URL` |
| Production build | `FOUNDRY_PROFILE=deploy forge build` |

Profiles are defined in `foundry.toml`. Default: fuzz 1000 runs, invariant 256×128, seed
`0x4b65656c` (deterministic, so evidence is reproducible). `deep`: fuzz 100000 runs,
invariant 2048×256.

---

## 1. Unit tests — `NOT STARTED`

Per-function behaviour of the invariant primitives in isolation. Phase 5.

## 2. Integration tests — `NOT STARTED`

Guard wired into a mock share-accounting hook, exercised through realistic sequences. Phase 5,
extended in Phase 6 against a real `PoolManager` via v4-core's `Deployers` harness.

## 3. Fuzz tests — `NOT STARTED`

Phase 5 and 7. Two directions, both mandatory:

- **Soundness:** no fuzzed sequence reaches a broken backing state without the guard reverting.
- **False positives:** no fuzzed sequence built only from *legitimate* operations causes a
  revert. This is the kill-condition test (V7). It is the more important of the two.

## 4. Invariant tests — `NOT STARTED`

Phase 7. Stateful handler-based runs against the mock and against a real PoolManager.
Handlers must include: repeated tiny withdrawals (the compounding-rounding shape), donations,
fee accrual, and multi-actor interleaving. `fail_on_revert = false` in config — assert the
property explicitly rather than relying on revert-freedom.

## 5. Fork tests — `NOT STARTED`

Phase 8. `FACT` `https://mainnet.unichain.org` served historical `eth_call` back to block
1,000,000 (`docs/RECON.md` §3.3), so Unichain fork tests are plausible without a paid archive
provider. `UNVERIFIED` whether it survives the request volume of a full suite, and whether
Ethereum-mainnet archive access is needed.

## 6. Regression tests — `NOT STARTED`

Every bug found by any reviewer or by fuzzing gets a named, permanent test before it is fixed.
No exceptions.

## 7. Security tests — `NOT STARTED`

Phase 6/7. Explicit assertions, not comments:

- [ ] Hook address has all four `*_RETURNS_DELTA_FLAG` bits (bits 0–3) **clear**. `SECURITY.md` §1.
- [ ] Guard callbacks return zero deltas.
- [ ] Guard holds no token balance in any scenario.
- [ ] Guard has no admin, pause, or upgrade path — asserted by absence of such selectors.
- [ ] Reentrancy: guard behaves correctly when re-entered via a malicious token.
- [ ] No unbounded loop on the swap or liquidity path.
- [ ] Malicious-token suite: fee-on-transfer, rebasing, reentrant, missing return value.

## 8. Gas benchmarks — `NOT STARTED`

Phase 9. `forge snapshot` committed as the baseline. Must report **overhead per guarded
action** — guarded minus unguarded, not an absolute number. If overhead is unreasonable for the
pools that would use it, say so; that is a kill condition (V10).

## 9. Deployment tests — `NOT STARTED`

Phase 10. Script dry-run; post-deploy on-chain assertion of permission bits; source
verification.

---

## Pre-release checklist

Also encoded in the `release-check` skill.

- [ ] `forge build` clean, no warnings introduced by our code
- [ ] `forge test` fully green
- [ ] `FOUNDRY_PROFILE=deep forge test` green
- [ ] `forge fmt --check` clean
- [ ] `forge coverage` reviewed; every uncovered branch explained
- [ ] `forge snapshot` updated and committed
- [ ] Every reviewer finding fixed or explicitly accepted in `THREAT_MODEL.md`
- [ ] `security-reviewer` and `adversarial-reviewer` both run on the final code
- [ ] `git submodule status` clean — no `+` or `-` prefixes (D-0010)
- [ ] `git ls-files | grep -iE '\.env|secret|key'` returns only `.env.example`
- [ ] `CURRENT_STATE.md`, `DECISIONS.md`, `CHANGELOG.md` current
- [ ] Every `FACT` in shipped docs traceable to `docs/RECON.md`
- [ ] README limitations section honest — including whether Phase 8 is a **replay** or a
      **reconstruction**. Never imply a replay that was not performed.
- [ ] Production build under `FOUNDRY_PROFILE=deploy`; hook address mined against **that**
      bytecode (D-0006)
