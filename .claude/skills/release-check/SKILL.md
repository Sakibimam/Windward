---
name: release-check
description: Pre-deployment checklist for Keel. Run before any testnet or mainnet deployment, and before presenting the project as finished. Mainnet always requires the owner's explicit approval.
allowed-tools: Read, Grep, Glob, Bash
---

# Release check

Run every item. Report each as pass or fail with its evidence. **Do not deploy on a failed
item.**

## 1. Build and test

```bash
forge build
forge test
FOUNDRY_PROFILE=deep forge test
forge fmt --check
forge coverage
forge snapshot
```

- [ ] `forge build` clean, no new warnings from our code
- [ ] `forge test` fully green
- [ ] `FOUNDRY_PROFILE=deep forge test` green (fuzz 100k, invariant 2048×256)
- [ ] `forge fmt --check` clean
- [ ] Coverage reviewed; every uncovered branch explained
- [ ] `forge snapshot` updated and committed

## 2. Security

- [ ] `security-reviewer` run on final code; every finding fixed or accepted in
      `THREAT_MODEL.md` §6
- [ ] `adversarial-reviewer` run on final code; verdict recorded
- [ ] `protocol-reviewer` run on all v4-facing code
- [ ] No admin, owner, pause, or upgrade path exists — asserted by test, not by comment
- [ ] Guard holds no token balance in any scenario
- [ ] **Hook address has all four `*_RETURNS_DELTA_FLAG` bits (bits 0–3) clear**, asserted by
      test (`SECURITY.md` §1)
- [ ] Every regression test from every finding is present and passing

## 3. Dependencies and repository hygiene

```bash
git submodule status
git ls-files | grep -i -E '\.env|secret|key'
git status --short
```

- [ ] `git submodule status` clean — **any `+` or `-` prefix blocks the release** (D-0010)
- [ ] Pins match `docs/RECON.md` §4.3 exactly
- [ ] Secrets grep returns **only** `.env.example`
- [ ] No `.env`, key, or keystore file tracked
- [ ] Working tree clean

## 4. Evidence and documentation

- [ ] Every `FACT` in shipped docs is traceable to `docs/RECON.md`
- [ ] No `UNVERIFIED` claim is relied on by anything being deployed
- [ ] `CURRENT_STATE.md`, `DECISIONS.md`, `CHANGELOG.md` current
- [ ] README limitations section is honest, and states that Keel is **not audited**
- [ ] README says plainly whether the Phase 8 artifact is a **replay** or a **reconstruction**.
      **Never imply a replay that was not performed.**
- [ ] The scope restriction is stated: Keel targets only hooks with share-like claims

## 5. Deployment mechanics

- [ ] Built with `FOUNDRY_PROFILE=deploy` (`via_ir = true`, `optimizer_runs = 44444444`)
- [ ] **Hook address mined against that same `deploy`-profile bytecode** — mining against
      default-profile bytecode produces a hook whose address does not match its code (D-0006)
- [ ] Target addresses verified in `docs/RECON.md` §7. Unichain Sepolia addresses are currently
      `UNVERIFIED` — verify on-chain before testnet use
- [ ] No private key in any file, script, or environment variable — keystore account only
- [ ] Script dry-run reviewed before broadcast

## 6. Approval gates

- [ ] **Testnet before mainnet.** Always.
- [ ] **Mainnet deployment requires the owner's explicit approval, every time.** Prior approval
      does not carry over.
- [ ] After deployment: permission bits asserted on-chain, source verified on the explorer,
      address and transaction hash recorded in `CURRENT_STATE.md`

## 7. Honesty gate

Ask directly, and answer in writing:

- Does the README overstate what Keel does?
- Is any kill condition (`PROJECT.md`) currently true and unreported?
- Would the `adversarial-reviewer` agree with how this project is being presented?

If any answer is uncomfortable, fix the presentation before shipping — not after.
