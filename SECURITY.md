# SECURITY.md — Keel

Policy. `THREAT_MODEL.md` holds the analysis; this file holds the rules that follow from it.

---

## 1. The governing security property

> **Keel observes and reverts. It never touches accounting.**

Every other rule here serves that one. Keel is a guard placed in the path of user funds. A guard
that can move funds, or that can wrongly refuse to let funds move, is a larger hazard than the
bug it was installed to prevent.

Concretely:

- Keel's hook callbacks return **zero deltas**. `returnDelta = false`, always.
- `INFERENCE` This is enforceable at the **address** level: the hook address must have
  `BEFORE_SWAP_RETURNS_DELTA_FLAG`, `AFTER_SWAP_RETURNS_DELTA_FLAG`,
  `AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG`, and `AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG`
  (address bits 3, 2, 1, 0) **clear**. Source: `docs/RECON.md` §6.1.
- Phase 6 must **assert this in a test**, not merely document it. A comment is not a control.
- Keel holds no token balances and has no token-transfer path.

## 2. Trust boundaries

| Boundary | Trusted? | Notes |
|---|---|---|
| Uniswap v4 `PoolManager` | **Trusted** | Assumed correct. Verified deployment, `docs/RECON.md` §7. If v4 is broken, Keel cannot help. |
| The guarded hook's own accounting | **Untrusted** | This is the thing Keel is checking. Never assume it is self-consistent. |
| Pool tokens (ERC-20s) | **Untrusted** | Rebasing, fee-on-transfer, reentrant (ERC-777-style), missing return values, >18 decimals, revert-on-zero-transfer. Phase 4 must state which are in scope. |
| Swappers / LPs / arbitrageurs | **Untrusted** | Fully adversarial and able to order, repeat, and sandwich their own calls. |
| The hook's deployer/operator | **Untrusted** | May be malicious or compromised. |
| Keel itself | Must be **trust-minimised** | No admin, no upgrade, no pause. See §3. |

## 3. Privileged roles

**Keel has none, by design.**

- No owner, no admin, no governance.
- No upgradeability. No proxy, no `delegatecall` to mutable targets.
- **No pause function.** A pause on a withdrawal path is a fund-freezing switch and reintroduces
  exactly the centralisation risk Keel is supposed to remove.
- No configurable parameters after deployment, unless Phase 4 proves a parameter is unavoidable.
  If one is, it must be `immutable` and set in the constructor, and the choice must be recorded
  in `DECISIONS.md` with the trade-off stated.

If a later phase argues for any privileged role, that is a **security change that materially
increases risk** and requires the owner's explicit approval.

## 4. Prohibited shortcuts

Never do these. If one seems necessary, stop and record the trade-off in `DECISIONS.md` first.

- `--dangerously-skip-permissions`, `bypassPermissions`, or any equivalent.
- Committing `.env`, a private key, a mnemonic, or a keystore file.
- Pasting a private key into a file, a script, an environment variable, or the terminal.
  Deployment uses a Foundry keystore account (`cast wallet import --interactive`).
- `forge update`, or bumping any dependency without re-deriving the pin per D-0004 and re-running
  the build canary.
- Enabling `ffi` (D-0007).
- Weakening or deleting a test to make a suite pass. Fix the code or record why the test was
  wrong.
- `unchecked` arithmetic without a comment stating why overflow is impossible.
- String reverts. Use custom errors.
- Writing an address, signature, version, or commit hash that was not verified this session.
- Marking something `FACT` that was not verified, or promoting a tag without new evidence.
- Deploying bytecode built under a profile other than the one the hook address was mined
  against (D-0006).

## 5. Coding rules

Enforced by `.claude/rules/solidity.md` and by the review chain.

- Checks-Effects-Interactions, always.
- Custom errors, never string reverts.
- **Every division states its rounding direction and who it favours.** Rounding is the failure
  class this project exists to catch; unexamined rounding in the guard would be a bitter irony.
- Explicit overflow reasoning in a comment for every `unchecked` block.
- No unbounded loops on a swap or liquidity path. Griefing and gas-limit DoS.
- No external calls from the guard beyond reads of the PoolManager and the guarded hook.
- Reentrancy: assume every external read can reenter. Keel's checks must be correct even when
  called re-entrantly, or must explicitly prevent it.
- Solidity `0.8.26` pinned exactly; `evm_version = cancun` (D-0006).

## 6. Dependency policy

- Pins are commit-exact and evidenced in `docs/RECON.md` §4.
- v4-core follows v4-periphery's own submodule pin; the rest follow v4-core's (D-0004).
- **Adding a dependency is a scope change** and requires owner approval.
- Any bump must: re-derive the pin from upstream's own submodule tree, re-run the build canary,
  re-run the full suite, and be recorded in `DECISIONS.md`.
- No package installed from npm into the contract build path.

## 7. Secret handling

- `.env` is gitignored and may never be read, printed, or committed. `.env.example` holds
  placeholders only.
- `.claude/settings.local.json` is gitignored — machine-specific RPC URLs and paths live there.
- Deployment keys live in the Foundry keystore, encrypted, referenced by account name.
  The account **name** is not a secret; the key never leaves the keystore.
- `FACT` Claude Code's `Read`/`Edit` deny rules cover the built-in file tools and the file
  commands it recognises in Bash (`cat`, `head`, `tail`, `sed`) — but **not** an arbitrary
  subprocess such as a Python or Node script that opens the file itself. This is a real,
  known limit of the `.env` protection. Recorded in `THREAT_MODEL.md`.

## 8. Review requirements

For any security-sensitive change, run and record every stage:

```
implement → test → security-reviewer → adversarial-reviewer → fix → test again
```

- Your own explanation of your code is **not** evidence that it is correct. Only passing tests
  and independent review are.
- Reviewers are read-only (D-0008). The main session applies fixes.
- `protocol-reviewer` additionally reviews anything touching v4 callbacks, deltas, permission
  bits, or deployment.
- Every finding is either fixed or explicitly accepted in `THREAT_MODEL.md` with a reason.
  Silently dropping a finding is prohibited.

## 9. Deployment requirements

Full list in the `release-check` skill. Non-negotiable minimum:

1. Testnet before mainnet. **Mainnet requires the owner's explicit approval, every time.**
2. Built with `FOUNDRY_PROFILE=deploy`, and the hook address mined against *that* bytecode
   (D-0006).
3. Hook address permission bits asserted on-chain after deployment, including the four
   returns-delta bits being clear (§1).
4. Source verified on the block explorer.
5. Full suite green, including fuzz and invariant runs under the `deep` profile.
6. `git submodule status` clean — no `+`/`-` prefixes (D-0010).
7. `CURRENT_STATE.md` updated with the deployment, and the address recorded with its
   transaction hash.

## 10. Reporting

This is a time-boxed research prototype and is **not audited**. It must not be used to secure
real funds without an independent audit. The README must say so plainly.
