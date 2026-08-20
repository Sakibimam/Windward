# docs/RECON-hooks.md — PreToolUse hook evidence

Companion to `docs/RECON.md` §8. Produced 2026-08-28 (Phase 0, session 2).

## What is installed

One `PreToolUse` hook, matching the `Bash` tool only:
`.claude/hooks/guard-bash.sh`, wired in `.claude/settings.json`.

It blocks exactly three things and nothing else:

| # | Blocked | Escape hatch |
|---|---|---|
| 1 | `rm` carrying **both** a recursive and a force flag | plain `rm -r` and plain `rm -f` still work |
| 2 | `git push` with any force or destructive flag (`--force`, `-f`, `--force-with-lease`, `--mirror`, `--delete`) | ordinary `git push` still works |
| 3 | `git add` of a `.env` file at any depth | `.env.example` is explicitly permitted |

`INFERENCE` The hook is deliberately tiny. A hook that fires during ordinary development gets
switched off wholesale, and a switched-off hook protects nothing (`THREAT_MODEL.md` V19). Every
other restriction is expressed as a `deny` or `ask` permission rule in `.claude/settings.json`
instead, where it is declarative and cannot have logic bugs.

## Mechanism (verified, `code.claude.com/docs/en/hooks`, see `docs/RECON.md` §1.5)

- Payload arrives as JSON on **stdin**; the command is at `.tool_input.command`.
- **Exit 0** allows, **exit 2** blocks the tool call and returns stderr to the model.
- `FACT` A hook exiting 2 blocks *before* permission rules are evaluated, so it overrides even
  an `allow` rule. It is a second line of defence, not a replacement for the deny list.
- The command line is split on `&&`, `||`, `;`, `|`, `&` so a dangerous call hidden after a
  separator is still inspected, and env-var assignments and wrappers (`env`, `nohup`, `time`,
  `nice`, `stdbuf`, `command`, `builtin`, `noglob`) are stepped over before the command name is
  read.
- `FACT` `timeout(1)` is absent on this machine (`docs/RECON.md` §1.7) and is therefore not used
  inside the script. The 10-second limit is set by the `timeout` field in the hook config, which
  Claude Code enforces.

## Live firing evidence

`FACT` The hook was observed firing against a **real** tool call, not only in the harness. While
writing the test harness in session 2, a `Bash` call whose heredoc body contained the literal
text `rm -rf out` was blocked end-to-end by Claude Code:

```
PreToolUse:Bash hook error: [${CLAUDE_PROJECT_DIR}/.claude/hooks/guard-bash.sh]: BLOCKED by
Keel guard-bash hook: recursive+force delete (` rm -rf out'`). Plain `rm -r` is still permitted.
If this is genuinely required, ask the product owner to run it manually.
```

This confirms three things at once: the hook is registered, `${CLAUDE_PROJECT_DIR}` expands
correctly, and exit code 2 actually blocks the call.

### Known limitation — `L1`

`FACT` The hook inspects the **entire command string**, including heredoc payloads. Writing a
file whose *content* mentions a blocked command is therefore blocked too, as the incident above
shows. This is a false positive in the strict sense.

`INFERENCE` It is accepted rather than fixed. Distinguishing "text inside a heredoc" from "a
command about to run" requires parsing shell grammar in the hook, and a subtly wrong parser
would create a *security* false negative — far worse than the mild inconvenience. The workaround
is to write such files with the `Write` tool, which this hook does not match. Recorded because a
future session will hit it and should not conclude the hook is broken.

## Test suite

Each branch was exercised by piping a crafted payload directly to the script, rather than by
issuing the real tool call — issuing a real `rm -rf` to test the hook would perform the deletion
if the hook failed. Both directions are covered: commands that **must** be blocked, and ordinary
development commands that **must not** be.

Harness: `hooktest.sh` (session scratchpad). Verbatim output below, redirected to file — never
hand-transcribed (`DECISIONS.md` D-0009).

```

### Check 1 - rm recursive+force
ok    expect=BLOCK got=BLOCK exit=2  rm -rf
        $ rm -rf out
        > BLOCKED by Keel guard-bash hook: recursive+force delete (`rm -rf out`). Plain `rm -r` is still permitted.
ok    expect=BLOCK got=BLOCK exit=2  rm -fr (flag order swapped)
        $ rm -fr out
        > BLOCKED by Keel guard-bash hook: recursive+force delete (`rm -fr out`). Plain `rm -r` is still permitted.
ok    expect=BLOCK got=BLOCK exit=2  rm -r -f (split flags)
        $ rm -r -f out
        > BLOCKED by Keel guard-bash hook: recursive+force delete (`rm -r -f out`). Plain `rm -r` is still permitted.
ok    expect=BLOCK got=BLOCK exit=2  rm -Rf (capital R)
        $ rm -Rf out
        > BLOCKED by Keel guard-bash hook: recursive+force delete (`rm -Rf out`). Plain `rm -r` is still permitted.
ok    expect=BLOCK got=BLOCK exit=2  rm --recursive --force
        $ rm --recursive --force out
        > BLOCKED by Keel guard-bash hook: recursive+force delete (`rm --recursive --force out`). Plain `rm -r` is still permitted.
ok    expect=BLOCK got=BLOCK exit=2  hidden after &&
        $ forge build && rm -rf out
        > BLOCKED by Keel guard-bash hook: recursive+force delete (` rm -rf out`). Plain `rm -r` is still permitted.
ok    expect=BLOCK got=BLOCK exit=2  hidden after ;
        $ echo hi ; rm -rf /tmp/x
        > BLOCKED by Keel guard-bash hook: recursive+force delete (` rm -rf /tmp/x`). Plain `rm -r` is still permitted.
ok    expect=BLOCK got=BLOCK exit=2  behind nohup wrapper
        $ nohup rm -rf out
        > BLOCKED by Keel guard-bash hook: recursive+force delete (`nohup rm -rf out`). Plain `rm -r` is still permitted.
ok    expect=BLOCK got=BLOCK exit=2  absolute path target
        $ rm -rf /
        > BLOCKED by Keel guard-bash hook: recursive+force delete (`rm -rf /`). Plain `rm -r` is still permitted.
ok    expect=ALLOW got=ALLOW exit=0  rm -r without force
        $ rm -r out
ok    expect=ALLOW got=ALLOW exit=0  rm -f single file
        $ rm -f notes.txt
ok    expect=ALLOW got=ALLOW exit=0  plain rm
        $ rm cache/x
ok    expect=ALLOW got=ALLOW exit=0  unrelated --force flag
        $ forge build --force

### Check 2 - force git push
ok    expect=BLOCK got=BLOCK exit=2  git push --force
        $ git push --force origin main
        > BLOCKED by Keel guard-bash hook: force/destructive git push (`git push --force origin main`).
ok    expect=BLOCK got=BLOCK exit=2  git push -f
        $ git push -f origin main
        > BLOCKED by Keel guard-bash hook: force git push (`git push -f origin main`).
ok    expect=BLOCK got=BLOCK exit=2  git push --force-with-lease
        $ git push --force-with-lease
        > BLOCKED by Keel guard-bash hook: force/destructive git push (`git push --force-with-lease`).
ok    expect=BLOCK got=BLOCK exit=2  git push --force-with-lease=ref
        $ git push --force-with-lease=main origin
        > BLOCKED by Keel guard-bash hook: force/destructive git push (`git push --force-with-lease=main origin`).
ok    expect=BLOCK got=BLOCK exit=2  git push --mirror
        $ git push --mirror origin
        > BLOCKED by Keel guard-bash hook: force/destructive git push (`git push --mirror origin`).
ok    expect=BLOCK got=BLOCK exit=2  git push --delete
        $ git push --delete origin main
        > BLOCKED by Keel guard-bash hook: force/destructive git push (`git push --delete origin main`).
ok    expect=BLOCK got=BLOCK exit=2  force push after &&
        $ forge test && git push -f
        > BLOCKED by Keel guard-bash hook: force git push (` git push -f`).
ok    expect=ALLOW got=ALLOW exit=0  ordinary git push
        $ git push origin main
ok    expect=ALLOW got=ALLOW exit=0  git push -u (not force)
        $ git push -u origin main
ok    expect=ALLOW got=ALLOW exit=0  git log with %f format
        $ git log --format=%f

### Check 3 - staging .env
ok    expect=BLOCK got=BLOCK exit=2  git add .env
        $ git add .env
        > BLOCKED by Keel guard-bash hook: staging a .env file (`git add .env`). Only .env.example may be committed.
ok    expect=BLOCK got=BLOCK exit=2  git add .env.local
        $ git add .env.local
        > BLOCKED by Keel guard-bash hook: staging a .env file (`git add .env.local`). Only .env.example may be committed.
ok    expect=BLOCK got=BLOCK exit=2  git add nested .env
        $ git add config/.env
        > BLOCKED by Keel guard-bash hook: staging a .env file (`git add config/.env`). Only .env.example may be committed.
ok    expect=BLOCK got=BLOCK exit=2  git add .env among other paths
        $ git add src/Foo.sol .env
        > BLOCKED by Keel guard-bash hook: staging a .env file (`git add src/Foo.sol .env`). Only .env.example may be committed.
ok    expect=ALLOW got=ALLOW exit=0  git add .env.example
        $ git add .env.example
ok    expect=ALLOW got=ALLOW exit=0  git add -A
        $ git add -A
ok    expect=ALLOW got=ALLOW exit=0  git add a source file
        $ git add src/Keel.sol

### Non-interference - ordinary development must pass untouched
ok    expect=ALLOW got=ALLOW exit=0  forge build
        $ forge build
ok    expect=ALLOW got=ALLOW exit=0  forge test verbose
        $ forge test -vvv
ok    expect=ALLOW got=ALLOW exit=0  chained build+test
        $ forge build && forge test
ok    expect=ALLOW got=ALLOW exit=0  git commit
        $ git commit -m 'feat: add guard'
ok    expect=ALLOW got=ALLOW exit=0  cast call
        $ cast call 0x1f98400000000000000000000000000000000004 'owner()(address)'
ok    expect=ALLOW got=ALLOW exit=0  grep pipeline
        $ grep -r BEFORE_SWAP lib/v4-core/src | head -5
ok    expect=ALLOW got=ALLOW exit=0  forge snapshot
        $ forge snapshot
ok    expect=ALLOW got=ALLOW exit=0  empty command field
        $ 

TOTAL: 38 passed, 0 failed
```

`FACT` **38 passed, 0 failed.** 24 must-block cases and 14 must-allow cases.

The harness is kept in the repo at `.claude/hooks/guard-bash.test.sh`. Re-run it after any
change to the hook:

```
.claude/hooks/guard-bash.test.sh "$PWD/.claude/hooks/guard-bash.sh"
```

It exits non-zero with the number of failures, so it can gate a change.

## What the hook does NOT protect against

Stated plainly so no one over-trusts it.

- `FACT` It only matches the `Bash` tool. File writes through `Write`/`Edit` are governed by the
  permission rules in `.claude/settings.json`, not by this hook.
- `FACT` It inspects the literal command string. A command constructed at runtime inside a
  script the hook allows (a Python or shell script that itself deletes files) is invisible to
  it. This is the same class of gap as `THREAT_MODEL.md` R1 and is accepted for the same reason.
- It is not a sandbox. It is a guard against the three specific accidents judged most likely and
  most costly in this project.
