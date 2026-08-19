---
name: keel-security-review
description: Run the mandatory review chain for any security-sensitive change to Keel — implement, test, security-reviewer, adversarial-reviewer, fix, test again. Use after any change touching accounting, arithmetic, rounding, hook callbacks, or fund flow.
allowed-tools: Read, Grep, Glob, Bash, Task
---

# Security review chain

> Your own explanation of your code is **not** evidence that it is correct.
> Only passing tests and independent review are.

Mandatory for any change touching accounting, arithmetic, rounding, external calls, hook
callbacks, or anything in the path of user funds.

## The chain — record every stage

```
implement → test → security-reviewer → adversarial-reviewer → fix → test again
```

Do not skip a stage because a change looks small. The compounding-rounding failure class this
project exists to catch looks small at every individual step.

### 1. Implement

Follow `.claude/rules/solidity.md`. Every division states its rounding direction and who it
favours.

### 2. Test

```bash
forge build && forge test
```

Both directions for every invariant: it catches the bad state, **and** it does not fire on
legitimate sequences. Confirm each new guard's test actually fails when the guard is removed.

### 3. `security-reviewer`

Dispatch the `security-reviewer` subagent over the diff. It is read-only by design (D-0008) —
it reports, you fix.

### 4. `protocol-reviewer` — if v4 surface is touched

Required if the change touches hook callbacks, deltas, permission bits, `PoolManager`
interaction, or deployment.

### 5. `adversarial-reviewer`

Its job is to argue the project is wrong. Do not dismiss its findings because they are
inconvenient — that is what it is for.

### 6. Fix

Every finding is either **fixed** or **explicitly accepted** in `THREAT_MODEL.md` §6 with a
reason. Silently dropping a finding is prohibited.

Every bug found gets a **named, permanent regression test written before it is fixed**.

### 7. Test again

```bash
forge build && forge test && FOUNDRY_PROFILE=deep forge test
```

A fix is not done until the suite is green again.

### 8. Record

Update `CURRENT_STATE.md`. If the change involved a security trade-off, append to
`DECISIONS.md` — **never weaken security to save time without recording it.**

## Keel's governing property

> **The guard observes and reverts. It never touches accounting.**

Any deviation is critical: a non-zero returned delta, a token transfer, an admin function, a
pause, a state write the guarded protocol depends on.

## The asymmetry

A false positive that freezes withdrawals is **worse** than the bug it prevents, and is an
explicit kill condition. Whenever you find a condition under which the guard reverts, ask
whether an honest user can reach it.
