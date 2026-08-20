# docs/RECON.md — Phase 0 Reconnaissance Evidence

All output in this file was produced on **2026-08-28** on the machine described below.
Everything here is `FACT` unless explicitly tagged otherwise. Where a claim could not be
verified this session it is tagged `UNVERIFIED` and no value is guessed.

This file is the evidence backing every pin, address, and signature quoted in `CLAUDE.md`.
If the two ever disagree, this file wins and `CLAUDE.md` is wrong.

---

## 1. Claude Code environment

### 1.1 Version and health

`claude --version`:

```
2.1.250 (Claude Code)
```

`claude doctor` (run with stdin closed; the interactive `/doctor` was not available to a
non-interactive tool call — see §1.7):

```
Claude Code doctor

Running: native (2.1.250)
Commit: 2f71b9f41af6
Platform: darwin-arm64
Path: /Users/sakib/.local/share/claude/versions/2.1.250
Config install method: native
Search: OK (bundled)
Auto-updates: enabled
Auto-update channel: latest
Last update attempt: success → 2.1.250 (2026-08-28)
Managed settings (remote): not fetched — requires an Enterprise or Team subscription

Remote Control
Control this session from claude.ai/code or the Claude mobile app

No installation issues found.

For a full setup checkup that can also fix issues, run /doctor in a Claude Code session.
```

### 1.2 Documentation source

`FACT` The Claude Code documentation has moved. `https://docs.claude.com/en/docs/claude-code/*`
returns **301 Moved Permanently** to `https://code.claude.com/docs/en/*`. All configuration
syntax below was read from the new location on 2026-08-28:

- `https://code.claude.com/docs/en/settings`
- `https://code.claude.com/docs/en/permissions`
- `https://code.claude.com/docs/en/hooks`
- `https://code.claude.com/docs/en/sub-agents`
- `https://code.claude.com/docs/en/skills`
- `https://code.claude.com/docs/en/memory`

### 1.3 Settings precedence (verified, `code.claude.com/docs/en/settings`)

Highest priority first:

| # | Level          | File                             | Scope                     |
|---|----------------|----------------------------------|---------------------------|
| 1 | Managed        | `managed-settings.json` / MDM    | Organization              |
| 2 | Command line   | `claude --settings`              | This session              |
| 3 | Project local  | `.claude/settings.local.json`    | You, this project         |
| 4 | Shared project | `.claude/settings.json`          | Everyone in the project   |
| 5 | User           | `~/.claude/settings.json`        | You, every project        |

`FACT` List keys such as `permissions.allow` are **merged across all files**, not overridden.
A `deny` or `ask` rule from any file therefore cannot be cancelled by an `allow` rule elsewhere.

`FACT` `.claude/settings.local.json` is not automatically added to `.gitignore` when a human
creates it by hand — only when Claude Code writes it first. We created it by hand, so we added
it to `.gitignore` ourselves (see §5).

### 1.4 Permission rule syntax (verified, `code.claude.com/docs/en/permissions`)

`FACT` Format is `Tool` or `Tool(specifier)`.

`FACT` Evaluation order is **deny → ask → allow**. First match wins. Specificity is irrelevant.
A broad deny cannot carry allowlist exceptions.

`FACT` A **bare tool name** in `deny` (e.g. `"Bash"`) removes the tool from the model's context
entirely. A **scoped** rule (e.g. `"Bash(rm *)"`) leaves the tool available and blocks matches.
This is why our `deny` list uses scoped rules only.

Bash matching, verbatim from the docs:

- `*` matches any text including spaces. A rule with no `*` matches one exact command.
- Put the `*` **after** the subcommand. `Bash(git log *)` allows only `git log`; `Bash(git *)`
  allows every git command including `git push`.
- A trailing ` *` also matches the bare command: `Bash(ls *)` matches `ls`.
- The space before a trailing `*` is part of the rule. `Bash(ls*)` also matches `lsof`.
- `Bash(ls:*)` is an equivalent spelling of `Bash(ls *)`. The `:*` form is only recognised at
  the end of a pattern.
- `FACT` Compound commands are parsed. Recognised separators: `&&`, `||`, `;`, `|`, `|&`, `&`,
  and newlines. **A rule must match each subcommand independently**, so `Bash(forge build)`
  does not authorise `forge build && curl evil.com`.
- `FACT` Output redirection targets (`>`, `>>`, `2>`) are checked as a **file write** against
  `Edit` rules. `Bash(git commit *)` allows the command, not the redirect target.
- `FACT` These wrappers are stripped before matching: `timeout`, `time`, `nice`, `nohup`,
  `stdbuf`, `command`, `builtin`, zsh `noglob`, and flag-free `xargs`. Environment-runner
  wrappers (`npx`, `docker exec`, `mise exec`, `devbox run`) are **not** stripped, so
  `Bash(npx *)` would authorise anything `npx` runs. We do not use such a rule.
- `FACT` Exec wrappers (`watch`, `setsid`, `ionice`, `flock`) and `find` with `-exec`/`-delete`
  cannot be auto-approved by a prefix rule; they always prompt.

`Read` / `Edit` path rules use **gitignore pattern syntax** with four anchors:

| Pattern       | Meaning                                    |
|---------------|--------------------------------------------|
| `//path`      | Absolute path from filesystem root         |
| `~/path`      | Path from home directory                   |
| `/path`       | Relative to the **settings source** (for a project file: primary working directory) |
| `path`/`./path` | Relative to current directory            |

`FACT` A single leading slash is **not** an absolute path. `Read(/Users/x)` anchors at the
project, not the filesystem. Absolute needs `//`.

`FACT` A bare filename follows gitignore semantics and matches at any depth, so `Read(.env)`
and `Read(**/.env)` are equivalent. This is what makes our `Read(.env)` deny rule cover nested
`.env` files too.

`FACT` A `Read` deny rule **also blocks Edit and Write** on the same path (v2.1.208+ for edits,
v2.1.228+ for writes). We are on 2.1.250, so this holds. `NotebookEdit` is *not* covered.

`FACT` Claude Code only consults `Edit(path)` and `Read(path)` rules for file permissions.
A path rule written for `Write(...)`, `NotebookEdit(...)`, `Glob(...)` or `MultiEdit(...)` is
accepted but **never consulted**, and warns at startup. Our rules therefore use `Edit(...)` and
`Read(...)` only.

`FACT` `WebFetch` rules use a `domain:` prefix matching the hostname.
`WebFetch(domain:*.example.com)` matches subdomains at any depth but **not** `example.com`
itself, so both forms are needed to cover a domain and its subdomains.

`FACT` Read/Edit deny rules apply to built-in file tools **and** to file commands Claude Code
recognises in Bash (`cat`, `head`, `tail`, `sed`). They do **not** apply to arbitrary
subprocesses (a Python or Node script that opens the file itself). This is a real limit of our
`.env` protection and is recorded in `THREAT_MODEL.md`.

### 1.5 Hook configuration (verified, `code.claude.com/docs/en/hooks`)

Schema:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/x.sh", "timeout": 30 }
        ]
      }
    ]
  }
}
```

`FACT` `matcher` is an exact string or `A|B` list when it contains only word characters,
digits, `_`, `-`, spaces, `,` and `|`; otherwise it is treated as an **unanchored JavaScript
regex**.

`FACT` The hook receives JSON on **stdin** containing `session_id`, `cwd`, `permission_mode`,
`hook_event_name`, `tool_name`, `tool_input`, `tool_use_id`.

`FACT` Exit codes: `0` = success (stdout parsed as JSON if it starts with `{`); `2` = blocking
error, which **blocks the tool call** on `PreToolUse`; any other code = non-blocking error.

`FACT` JSON stdout shape for a block:

```json
{ "hookSpecificOutput": { "hookEventName": "PreToolUse",
                          "permissionDecision": "deny",
                          "permissionDecisionReason": "..." } }
```

`permissionDecision` values: `"allow"`, `"deny"`, `"ask"`.

`FACT` **Hook decisions do not bypass permission rules.** A matching `deny` or `ask` rule still
applies even if a hook returns `"allow"`. Conversely a hook exiting 2 blocks the call *before*
permission rules are evaluated, so it overrides an `allow` rule. Our hooks are therefore a
second line of defence, not a replacement for the deny list.

`FACT` `${CLAUDE_PROJECT_DIR}` expands to the project root inside a hook `command`.

### 1.6 Subagents, skills, and rules (verified)

Subagents — `.claude/agents/*.md`, YAML frontmatter. Only `name` and `description` are
required. Fields we use, all confirmed present in the current docs:

| Field             | Values used here                                            |
|-------------------|-------------------------------------------------------------|
| `name`            | lowercase + hyphens, no `:`                                  |
| `description`     | when to delegate                                             |
| `tools`           | comma-separated string **or** YAML list                      |
| `disallowedTools` | removes tools from the inherited pool — **this is how we make reviewers read-only** |
| `model`           | `sonnet` / `opus` / `haiku` / `fable` / full ID / `inherit`   |
| `permissionMode`  | `default`/`acceptEdits`/`auto`/`dontAsk`/`bypassPermissions`/`plan`/`manual` |
| `color`           | red/blue/green/yellow/purple/orange/pink/cyan                |

`INFERENCE` Setting `tools:` to an explicit read-only list is the primary mechanism; we add
`disallowedTools: Write, Edit, NotebookEdit` as belt-and-braces so a future tool addition
cannot silently give a reviewer write access.

Skills — `.claude/skills/<name>/SKILL.md`. `FACT` The directory name is what you type as the
command; frontmatter `name` only sets the display label for personal/project skills.
Frontmatter fields used: `name`, `description`, `disable-model-invocation`, `allowed-tools`.
`FACT` `allowed-tools` grants last only for the turn that invokes the skill.

`FACT` **A project skill whose directory name collides with a built-in skill is silently
shadowed.** Observed directly in session 2: a project skill at
`.claude/skills/security-review/` did **not** appear in the available-skills list, because
Claude Code ships a built-in `security-review`. The two sibling skills created in the same
commit (`verify-before-code`, `release-check`) both appeared immediately. There was no error and
no warning — the skill was simply absent. Renaming the directory to `keel-security-review` made
it available. **Prefix project skills to avoid built-in names.**

Rules — `.claude/rules/*.md`. `FACT` This is a supported mechanism, documented at
`code.claude.com/docs/en/memory#organize-rules-with-claude/rules/`. Files are discovered
recursively. A rule **without** `paths:` frontmatter loads at launch with the same priority as
`.claude/CLAUDE.md`. A rule **with** `paths:` loads only when Claude reads a matching file.

CLAUDE.md — `FACT` loaded from `./CLAUDE.md` or `./.claude/CLAUDE.md` plus every ancestor
directory. `@path` imports expand at launch, max depth 4 hops. Target under 200 lines.
`FACT` Project-root CLAUDE.md survives `/compact`; instructions given only in conversation do not.

### 1.7 Limitations found

`FACT` `/doctor` is an in-session slash command and cannot be invoked from a tool call. The CLI
equivalent `claude doctor` was run instead and its full output is in §1.1. The interactive
`/doctor` may report additional checks; if you want those, run it yourself.

`FACT` `timeout` is not present on this macOS system (`(eval):1: command not found: timeout`),
so it cannot be used as a safety wrapper in scripts or hooks here.

`FACT` A `.claude/settings.local.json` exists one level above this repository at
`/Users/sakib/Desktop/Apps/UniSwap/.claude/settings.local.json`. There is no ancestor
`CLAUDE.md`. Settings from that ancestor directory are **not** loaded for a session started in
`Keel/` (project settings are read from the session's primary working directory), but it is
noted here because a session started in the parent directory would behave differently.

---

## 2. Machine environment

```
$ uname -a
Darwin Sakibs-MacBook-Air.local 25.6.0 Darwin Kernel Version 25.6.0: Fri Jul 31 19:11:03 PDT 2026; root:xnu-12377.161.14~5/RELEASE_ARM64_T8132 arm64

$ sw_vers
ProductName:		macOS
ProductVersion:		26.6.2
BuildVersion:		25G83

$ git --version
git version 2.50.1 (Apple Git-155)

$ node --version
v24.16.0

$ npm --version
11.13.0

$ jq --version
jq-1.7.1-apple

$ forge --version
forge Version: 1.7.1
Commit SHA: 4072e48705af9d93e3c0f6e29e93b5e9a40caed8
Build Timestamp: 2026-05-08T07:54:31.470926000Z (1778226871)
Build Profile: dist

$ cast --version
cast Version: 1.7.1
Commit SHA: 4072e48705af9d93e3c0f6e29e93b5e9a40caed8

$ anvil --version
anvil Version: 1.7.1
Commit SHA: 4072e48705af9d93e3c0f6e29e93b5e9a40caed8

$ which foundryup
/Users/sakib/.foundry/bin/foundryup
```

`FACT` The brief asked for `foundryup --version stable`. That command **installs** the `stable`
channel rather than printing a version. It was deliberately **not run**, because reinstalling
the toolchain mid-recon would invalidate the version evidence above. Foundry 1.7.1 is what this
project is pinned to and what all output in this file was produced with. Shell is `zsh`.

---

## 3. RPC endpoints

### 3.1 What is configured

`FACT` No RPC-related environment variables are set on this machine
(`env | grep -iE 'rpc|alchemy|infura|etherscan|unichain'` → empty).
`FACT` There is no `~/.foundry/foundry.toml`.

### 3.2 Public Unichain endpoint — verified working

```
$ cast chain-id --rpc-url https://mainnet.unichain.org
130

$ cast block-number --rpc-url https://mainnet.unichain.org
57146322
```

### 3.3 Archive availability — verified

`FACT` The public endpoint served **historical state**, not just headers. `eth_call` against
the PoolManager succeeded at every block tested:

```
$ for B in 57146000 50000000 30000000 10000000 1000000; do
    cast call 0x1f98400000000000000000000000000000000004 "owner()(address)" --block $B \
      --rpc-url https://mainnet.unichain.org
  done
block 57146000 -> 0x2BAD8182C09F50c8318d769245beA52C32Be46CD
block 50000000 -> 0x2BAD8182C09F50c8318d769245beA52C32Be46CD
block 30000000 -> 0x2BAD8182C09F50c8318d769245beA52C32Be46CD
block 10000000 -> 0x2BAD8182C09F50c8318d769245beA52C32Be46CD
block 1000000  -> 0x2BAD8182C09F50c8318d769245beA52C32Be46CD
```

`INFERENCE` `https://mainnet.unichain.org` behaves as an archive node for `eth_call` at least
back to block 1,000,000. This makes Phase 8 fork reproduction on Unichain plausible **without**
a paid archive provider.

`UNVERIFIED` Whether that endpoint tolerates the request volume of a fork test suite, and
whether it serves archive `eth_getProof` / debug traces. Rate limiting has not been tested.
Ethereum mainnet archive access has not been tested at all — the Bunni incident spanned
Ethereum and Unichain, so Phase 8 may still need a key. See the ask in `CURRENT_STATE.md`.

---

## 4. Dependency resolution

### 4.1 Live registry queries (verbatim, 2026-08-28)

```
$ git ls-remote --tags https://github.com/Uniswap/v4-core
e50237c43811bd9b526eff40f26772152a42daba	refs/tags/v4.0.0
```

`FACT` `v4.0.0` is the **only** tag on v4-core.

```
$ git ls-remote --heads https://github.com/Uniswap/v4-periphery main master
dce236d4e2057422d0791d9a973a58765eb46f65	refs/heads/main
```

`FACT` `git ls-remote --tags https://github.com/Uniswap/v4-periphery` returned **no output**.
v4-periphery has no tags at all, so it can only be pinned by commit.

```
$ git ls-remote --tags https://github.com/foundry-rs/forge-std   (tail)
...
3b20d60d14b343ee4f908cb8079495c07f5e8981	refs/tags/v1.9.6
77041d2ce690e692d6e03cc812b57d1ddaa4d505	refs/tags/v1.9.7
```

```
$ git ls-remote --tags https://github.com/OpenZeppelin/uniswap-hooks   (tail)
1db96464698ee567521bd2dd65833ff1e1864ac7	refs/tags/v1.0.0
f051c147dbf296b2b854de92970905a880cd1d51	refs/tags/v1.0.0-rc.0
e59fe72c110c3862eec9b332530dce49ca506bbb	refs/tags/v1.1.0
9d1d623d4638d6c30392e1604587173a204e3afa	refs/tags/v1.1.0-rc.0
087974776fb7285ec844ca090eab860bd8430a11	refs/tags/v1.1.0-rc.1
3e9fa228ec0f7fe05a95e09e25442466b459a712	refs/tags/v1.1.0-rc.2
bd5287c4a9f5c22c2393f7587a9b357662916115	refs/tags/v1.1.1
765c70389cdceaea40a01441580b496632d50afe	refs/tags/v1.2
b52f464aa0af8fcd8f16cdad9ae43581deb5cd47	refs/tags/v1.2.0
6ce97fcaa18ddf8b00b29f7bb52293e4fd2214a3	refs/tags/v1.2.0-rc.0
a93376b4874c6c3d3ba1765ddd9a2fda5f97c7fe	refs/tags/v1.2.0-rc.0^{}
7170eec9cdbbdb4a907d14bfe63478cf15d2eab4	refs/tags/v1.2.0-rc.1
acbd604c409a827f7f98c9517236da860c4fca1a	refs/tags/v1.2.1

$ git ls-remote --heads https://github.com/OpenZeppelin/uniswap-hooks main master
31a1393f02528095e539b9e31440192ba1aa02c3	refs/heads/master
```

`FACT` Latest `uniswap-hooks` release tag is `v1.2.1` at `acbd604c409a827f7f98c9517236da860c4fca1a`.
The `^{}` line above is the annotated-tag peel for `v1.2.0-rc.0`.

> **Correction, 2026-08-28 (session 2).** The `refs/tags/v1.2.1` line in the block above was
> originally transcribed with the wrong sha (`7170eec9…`, which is actually `v1.2.0-rc.1`).
> The block above now reflects a live re-query run in session 2:
> `git ls-remote --tags https://github.com/OpenZeppelin/uniswap-hooks | grep -E 'v1\.2'`.
> The prose sha was correct throughout. Logged as an accuracy incident in `DECISIONS.md` D-0009.

**This dependency is deliberately not vendored yet** — see `DECISIONS.md` D-0005.

### 4.2 v4-core resolved from v4-periphery's own submodule pin

As instructed, v4-core is pinned to whatever v4-periphery was built against, not to a tag and
not to any third party's pin.

```
$ curl -sL https://raw.githubusercontent.com/Uniswap/v4-periphery/dce236d4e2057422d0791d9a973a58765eb46f65/.gitmodules
[submodule "lib/v4-core"]
	path = lib/v4-core
	url = https://github.com/Uniswap/v4-core
[submodule "lib/permit2"]
	path = lib/permit2
	url = https://github.com/Uniswap/permit2
```

`lib/` tree of v4-periphery @ `dce236d`, via the GitHub git-trees API:

```
160000 commit cc56ad0f3439c502c246fc5cfcc3db92bb8b7219 permit2
160000 commit 59d3ecf53afa9264a16bba0e38f4c5d2231f80bc v4-core
```

`FACT` v4-periphery `dce236d` pins v4-core at **`59d3ecf53afa9264a16bba0e38f4c5d2231f80bc`**,
whose commit message is `bump to 1.0.2 (#972)`, dated **2025-05-13T17:27:54Z**.

`FACT` That commit is **12 commits ahead of the `v4.0.0` tag** and 0 behind:

```
$ GET /repos/Uniswap/v4-core/compare/e50237c...59d3ecf
status=ahead ahead_by=12 behind_by=0 total_commits=12
```

`INFERENCE` Pinning v4-core to the `v4.0.0` tag would have produced a v4-core that v4-periphery
was never built against. The submodule pin is the correct choice and is what we used.

v4-core `59d3ecf` in turn pins its own dependencies:

```
160000 commit 1de6eecf821de7fe2c908cc48d3ab3dced20717f forge-std
160000 commit dbb6104ce834628e473d2173bbc9d47f81a9eec3 openzeppelin-contracts
160000 commit 4b47a19038b798b4a33d9749d25e570443520647 solmate
```

`INFERENCE` We adopted v4-core's own pins for forge-std, solmate and openzeppelin-contracts
rather than the newest tags (forge-std `v1.9.7`, for example). Mixing a newer forge-std with
v4-core's test harness is exactly the "HEAD of one dependency with an unrelated commit of
another" failure the brief forbids.

### 4.3 Final pin set — recorded and verified locally

```
$ git submodule status
1de6eecf821de7fe2c908cc48d3ab3dced20717f lib/forge-std (v1.9.3-24-g1de6eec)
dbb6104ce834628e473d2173bbc9d47f81a9eec3 lib/openzeppelin-contracts (v5.0.0-12-gdbb6104c)
cc56ad0f3439c502c246fc5cfcc3db92bb8b7219 lib/permit2 (0x000000000022D473030F116dDEE9F6B43aC78BA3-19-gcc56ad0)
4b47a19038b798b4a33d9749d25e570443520647 lib/solmate (v6-200-g4b47a19)
59d3ecf53afa9264a16bba0e38f4c5d2231f80bc lib/v4-core (v4.0.0-12-g59d3ecf5)
dce236d4e2057422d0791d9a973a58765eb46f65 lib/v4-periphery (heads/main)
```

| Dependency               | Pinned commit                              | How it was chosen                        |
|--------------------------|--------------------------------------------|------------------------------------------|
| `v4-periphery`           | `dce236d4e2057422d0791d9a973a58765eb46f65` | `main` HEAD (repo has no tags)           |
| `v4-core`                | `59d3ecf53afa9264a16bba0e38f4c5d2231f80bc` | v4-periphery's own submodule pin         |
| `permit2`                | `cc56ad0f3439c502c246fc5cfcc3db92bb8b7219` | v4-periphery's own submodule pin         |
| `forge-std`              | `1de6eecf821de7fe2c908cc48d3ab3dced20717f` | v4-core's own submodule pin (v1.9.3+24)  |
| `solmate`                | `4b47a19038b798b4a33d9749d25e570443520647` | v4-core's own submodule pin              |
| `openzeppelin-contracts` | `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | v4-core's own submodule pin (v5.0.0+12)  |

`FACT` forge-std at `1de6eec` has **no `lib/` directory and no `.gitmodules`** — `ds-test` is
vendored into `src/`. A `ds-test/` remapping is therefore unnecessary and was omitted.

### 4.4 Compilation evidence — the pins actually work together

`src/CompileCanary.sol` and `test/CompileCanary.t.sol` exist solely to prove this. The canary
imports `IPoolManager`, `IHooks`, `Hooks`, `StateLibrary`, `PoolKey`, `PoolId`, `BalanceDelta`
from v4-core and `SafeCallback` from v4-periphery; the test additionally pulls in
`forge-std/Test.sol` and v4-core's `Deployers` harness and deploys a real `PoolManager`.

```
$ forge build
Compiling 92 files with Solc 0.8.26
Solc 0.8.26 finished in 2.39s
Compiler run successful!

$ forge test -vv
Ran 2 tests for test/CompileCanary.t.sol:CompileCanaryTest
[PASS] test_hookFlagDecoding() (gas: 9677)
[PASS] test_managerDeployed() (gas: 11342)
Suite result: ok. 2 passed; 0 failed; 0 skipped; finished in 7.34ms (1.37ms CPU time)

Ran 1 test suite in 22.57ms (7.34ms CPU time): 2 tests passed, 0 failed, 0 skipped (2 total tests)
```

---

## 5. Secrets check

> **Corrected in session 2.** Session 1 recorded a `git ls-files` result showing `.env.example`
> as the sole match — but `.env.example` **did not exist on disk** and nothing had been
> committed, so that output could not have been produced as shown. The file was created in
> session 2 and every check below was genuinely re-run. Logged with D-0009 as the same class of
> error: evidence that was written down without being produced.

`.gitignore` covers `.env`, `.env.*` (with a `!.env.example` negation), `*.key`, `*.pem`,
`keystore/`, `secrets/`, `.claude/settings.local.json`, `CLAUDE.local.md`, `out/`, `cache/`,
`broadcast/`, `node_modules/`.

Re-run 2026-08-28 (session 2), output redirected to file:

```
$ git ls-files | grep -i -E "\.env|secret|key"
.env.example

$ git check-ignore -v .env .env.local .claude/settings.local.json
.gitignore:9:.env	.env
.gitignore:10:.env.*	.env.local
.gitignore:18:.claude/settings.local.json	.claude/settings.local.json

$ git check-ignore -v .env.example        # the ! negation must un-ignore this one
```

`FACT` The only tracked match is `.env.example`, which holds placeholder values only. It carries
no RPC key and no private key; the deployment section instructs the use of a Foundry keystore
account and explicitly says not to paste a raw key.

`FACT` `git check-ignore` returns nothing for `.env.example` in the output above because the
file is now **tracked** — check-ignore skips tracked paths. Before it was staged, the same
command reported `.gitignore:11:!.env.example`, i.e. the negation matched. Being tracked is
itself the stronger proof that the negation works.

`FACT` `.env` cannot be committed, and this is now enforced at **two** independent layers:

1. **git** — an attempt to stage a throwaway `.env`, run in session 2 before the hook was
   installed, was refused:

   ```
   $ git add .env
   The following paths are ignored by one of your .gitignore files:
   .env
   hint: Use -f if you really want to add them.
   ```

2. **the PreToolUse hook** — after installation, a later attempt to run the same test was
   blocked by `guard-bash.sh` before `git` ever saw it:

   ```
   PreToolUse:Bash hook error: BLOCKED by Keel guard-bash hook: staging a .env file
   (`git add .env`). Only .env.example may be committed.
   ```

   `git add -f` is separately denied by a permission rule in `.claude/settings.json`.

`INFERENCE` The second layer firing during ordinary work is the strongest available evidence
that the hook is genuinely wired in, since it interrupted a real tool call rather than a
harness. Full hook evidence is in `docs/RECON-hooks.md`.

---

## 6. Verified Uniswap v4 facts (source: files on disk at the pins above)

These are the only v4 API facts verified in Phase 0. **Phase 1 does the full sweep** — do not
treat this list as complete.

### 6.1 Hook permission flags — `lib/v4-core/src/libraries/Hooks.sol`

```
27:    uint160 internal constant ALL_HOOK_MASK = uint160((1 << 14) - 1);
29:    uint160 internal constant BEFORE_INITIALIZE_FLAG = 1 << 13;
30:    uint160 internal constant AFTER_INITIALIZE_FLAG = 1 << 12;
32:    uint160 internal constant BEFORE_ADD_LIQUIDITY_FLAG = 1 << 11;
33:    uint160 internal constant AFTER_ADD_LIQUIDITY_FLAG = 1 << 10;
35:    uint160 internal constant BEFORE_REMOVE_LIQUIDITY_FLAG = 1 << 9;
36:    uint160 internal constant AFTER_REMOVE_LIQUIDITY_FLAG = 1 << 8;
38:    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 7;
39:    uint160 internal constant AFTER_SWAP_FLAG = 1 << 6;
41:    uint160 internal constant BEFORE_DONATE_FLAG = 1 << 5;
42:    uint160 internal constant AFTER_DONATE_FLAG = 1 << 4;
44:    uint160 internal constant BEFORE_SWAP_RETURNS_DELTA_FLAG = 1 << 3;
45:    uint160 internal constant AFTER_SWAP_RETURNS_DELTA_FLAG = 1 << 2;
46:    uint160 internal constant AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG = 1 << 1;
47:    uint160 internal constant AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG = 1 << 0;
```

`INFERENCE` Keel's "observe and revert only, never touch accounting" property (brief §Phase 6)
means the hook address must have the four `*_RETURNS_DELTA_FLAG` bits (bits 0–3) **clear**.
That is a checkable, testable property of the deployed address, and Phase 6 must assert it.

### 6.2 `IHooks` callback declarations — `lib/v4-core/src/interfaces/IHooks.sol`

Line numbers of each declaration, at the pinned commit:

```
21:  beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96) -> bytes4
29:  afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick) -> ...
39:  beforeAddLiquidity(...)
55:  afterAddLiquidity(...)
70:  beforeRemoveLiquidity(...)
86:  afterRemoveLiquidity(...)
103: beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData) -> ...
115: afterSwap(...)
130: beforeDonate(...)
145: afterDonate(...)
```

`UNVERIFIED` The exact return tuples of `beforeSwap`, `afterSwap`, and the liquidity callbacks,
and the fee-override encoding. Full signatures with return types are **Phase 1** work — do not
write hook code from the line numbers above alone.

`FACT` Swap parameters live in a type named `SwapParams` imported from
`@uniswap/v4-core/src/types/PoolOperation.sol` (v4-periphery `dce236d` imports that path). They
are **not** `IPoolManager.SwapParams` at these pins. This is a change from older v4 code and is
exactly the kind of stale-training-data error the brief warns about.

### 6.3 `BaseHook` is NOT in v4-periphery at this pin

`FACT` `find lib/v4-periphery/src -name 'BaseHook.sol'` returns **nothing**.
`lib/v4-periphery/src/` contains `base/`, `hooks/permissionedPools/`, `interfaces/`, `lens/`,
`libraries/`, `PositionDescriptor.sol`, `PositionManager.sol`, `UniswapV4DeployerCompetition.sol`,
`V4Router.sol`. There is no `src/utils/` directory.

`INFERENCE` Any tutorial, blog post, or training-data memory that says
`import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol"` is **wrong at this pin**.
Phase 6 must either use OpenZeppelin `uniswap-hooks`' `BaseHook` or implement `IHooks`
directly. This is an open decision recorded as D-0005 in `DECISIONS.md`.

---

## 7. Verified Unichain deployment addresses

Source: `https://developers.uniswap.org/llms.mdx/docs/protocols/v4/deployments`, fetched
2026-08-28. (`https://docs.uniswap.org/contracts/v4/deployments` 301s to
`developers.uniswap.org`, which 303s to the `llms.mdx` path above.)

### Unichain — chain ID 130

| Contract         | Address                                      |
|------------------|----------------------------------------------|
| PoolManager      | `0x1f98400000000000000000000000000000000004` |
| PositionManager  | `0x4529a01c7a0410167c5740c487a8de60232617bf` |
| StateView        | `0x86e8631a016f9068c3f085faf484ee3f5fdee8f2` |
| Quoter           | `0x333e3c607b141b18ff6de9f258db6e77fe7491e0` |
| Universal Router | `0xef740bf23acae26f6492b10de645d6b98dc8eaf3` |

### Unichain Sepolia — chain ID 1301

| Contract         | Address                                      |
|------------------|----------------------------------------------|
| PoolManager      | `0x00b036b58a818b1bc34d502d3fe730db729e62ac` |
| PositionManager  | `0xf969aee60879c54baaed9f3ed26147db216fd664` |
| StateView        | `0xc199f1072a74d4e905aba1a84d9a45e2546b6222` |
| Quoter           | `0x56dcd40a3f2d466f48e7f48bdbe5cc9b92ae4472` |
| PoolSwapTest     | `0x9140a78c1a137c7ff1c151ec8231272af78a99a4` |
| Universal Router | `0xf70536b3bcc1bd1a972dc186a2cf84cc6da6be5d` |

### On-chain cross-check of the Unichain PoolManager

The documentation page is not trusted on its own. The address was confirmed against live chain
state, and independently corroborated by asking a *different* contract what it points at:

```
$ cast code 0x1f98400000000000000000000000000000000004 --rpc-url https://mainnet.unichain.org | wc -c
   48103                      # non-empty; a real deployed contract

$ cast call 0x1f98400000000000000000000000000000000004 "owner()(address)" --rpc-url https://mainnet.unichain.org
0x2BAD8182C09F50c8318d769245beA52C32Be46CD

$ cast call 0x86e8631a016f9068c3f085faf484ee3f5fdee8f2 "poolManager()(address)" --rpc-url https://mainnet.unichain.org
0x1F98400000000000000000000000000000000004
```

`FACT` `StateView.poolManager()` returns the same address the docs list for PoolManager. Two
independent sources agree.

`UNVERIFIED` The Unichain Sepolia addresses. They were read from the same documentation page but
have **not** been checked on-chain. Verify before any testnet deployment in Phase 10.

`UNVERIFIED` `0x2BAD8182C09F50c8318d769245beA52C32Be46CD` — the PoolManager owner. Not yet
identified. It matters for the threat model (the owner controls protocol fees), so Phase 1
should identify it.

---

## 8. Hook firing evidence

One `PreToolUse` hook is installed, matching the `Bash` tool only:
`.claude/hooks/guard-bash.sh`. It blocks exactly three things — `rm` with both recursive and
force flags, force/destructive `git push`, and `git add` of a `.env` file — and nothing else.

Each branch was tested by piping a crafted stdin payload directly to the script, because
issuing the real tool call would have performed the destructive action if the hook had failed.
Both directions are covered: 24 cases that **must** block, and 14 ordinary development commands
that **must not**.

`FACT` **38 passed, 0 failed.** Verbatim output, the harness, the live-firing evidence, and the
hook's known limitations are in **`docs/RECON-hooks.md`**. The harness is vendored at
`.claude/hooks/guard-bash.test.sh` and must be re-run after any change to the hook.

`FACT` The hook was additionally observed blocking two **real** tool calls during session 2 (a
heredoc containing the literal text `rm -rf out`, and a genuine `git add .env` test). See
`docs/RECON-hooks.md` and §5 above.
