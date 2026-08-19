# Rule — Testing

`TESTING.md` holds the plan and the checklist. This is the standing discipline.

## Rules

1. **Never weaken or delete a test to make a suite pass.** Fix the code, or record in
   `DECISIONS.md` why the test was wrong.
2. **A test that has never failed has proven nothing.** For each guard, write the test that
   fails when the guard is removed, and confirm it actually fails before moving on.
3. **Test both directions of every invariant.**
   - *Soundness:* the guard catches the bad state.
   - *False positives:* the guard does **not** fire on legitimate sequences.
   The second is more important. It is a kill condition (`THREAT_MODEL.md` V7).
4. **Every bug found by a reviewer or by fuzzing gets a named, permanent regression test**
   before it is fixed. No exceptions.
5. **Every phase ends with a green build.** Never leave broken code and continue.
6. Keep `CURRENT_STATE.md`'s last-passing and last-failing test fields honest.

## Naming

`test_<behaviour>` · `testFuzz_<behaviour>` · `test_revert_<condition>` · `invariant_<property>`

## Commands

| Purpose | Command |
|---|---|
| Build | `forge build` |
| Test | `forge test` |
| One test, verbose | `forge test --match-test <name> -vvv` |
| Deep fuzz / invariant | `FOUNDRY_PROFILE=deep forge test` |
| Coverage | `forge coverage` |
| Gas | `forge snapshot` |
| Format | `forge fmt` |
| Fork | `forge test --fork-url $UNICHAIN_RPC_URL` |

Fuzzing uses a fixed seed (`0x4b65656c`) so that evidence is reproducible. If a fuzz failure is
found, capture the counterexample into a named unit test immediately — do not rely on the seed
to reproduce it later.

## Gas

Report **overhead per guarded action** — guarded minus unguarded — never an absolute number
alone. An absolute number is not interpretable and cannot be checked against the kill condition.
