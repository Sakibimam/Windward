# Rule — Security

`SECURITY.md` is the full policy; `THREAT_MODEL.md` is the analysis. This is the working
shortlist.

## Before writing security-sensitive code

1. Verify the API from source on disk at the pinned commit. Not from memory.
2. State your assumptions explicitly, in the file.
3. Identify the attack surface the change opens.
4. Only then implement.

## Prohibited

- `--dangerously-skip-permissions` / `bypassPermissions`, in any form.
- Committing `.env`, a private key, a mnemonic, or a keystore file.
- Pasting a private key into a file, script, env var, or the terminal. Deployment uses a Foundry
  keystore account (`cast wallet import --interactive`).
- `forge update`, or bumping a dependency without re-deriving the pin (`DECISIONS.md` D-0004)
  and re-running the build canary.
- Enabling `ffi` (D-0007).
- Weakening or deleting a test to make a suite pass.
- Writing an address, signature, version, or commit hash not verified this session.
- Deploying bytecode built under a different profile than the hook address was mined against
  (D-0006).

## The review chain — mandatory for security-sensitive changes

```
implement → test → security-reviewer → adversarial-reviewer → fix → test again
```

Record each stage. **Your own explanation of your code is not evidence that it is correct.**
Only passing tests and independent review are. Reviewers are read-only by design (D-0008).

Every finding is either fixed or explicitly accepted in `THREAT_MODEL.md` §6 with a reason.
Silently dropping a finding is prohibited.

## Never weaken security to save time without recording the trade-off in `DECISIONS.md`.

Time pressure is the standing condition of this project, not an exception to it.

## The asymmetry to keep in mind

A false positive that freezes withdrawals is **worse** than the bug it prevents. Keel sits in
the path of user funds. When choosing between "might miss an attack" and "might freeze honest
users", neither is acceptable — but the second ends the project (`PROJECT.md`, kill conditions).
