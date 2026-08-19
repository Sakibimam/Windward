---
name: verify-before-code
description: Run before writing any code that touches an external API — Uniswap v4, OpenZeppelin, forge-std, or any deployed address. Verifies every signature, import path, constant, and address against source on disk at the pinned commit, instead of from memory.
allowed-tools: Read, Grep, Glob, Bash
---

# Verify before code

> Never write an API call, import path, function signature, struct field, version number, commit
> hash, or contract address you have not verified this session.

Training data on Uniswap v4 is badly stale — v4 changed repeatedly before release, so most
tutorials, blog posts, and remembered snippets are wrong for our pins. Two confirmed instances
are already recorded in `docs/RECON.md` §6.

Pins (`docs/RECON.md` §4.3): v4-core `59d3ecf5`, v4-periphery `dce236d4`, forge-std `1de6eecf`,
solmate `4b47a190`, openzeppelin-contracts `dbb6104c`, permit2 `cc56ad0f`.

## Procedure

### 1. Locate the real declaration

```bash
grep -rn "function beforeSwap" lib/v4-core/src/interfaces/IHooks.sol
grep -rn "SwapParams" lib/v4-core/src/types/PoolOperation.sol
find lib/v4-core/src -name '*.sol' | xargs grep -ln "library StateLibrary"
```

Read the actual file. Do not stop at the search hit — read the full declaration including the
**return tuple**, which is where v4 signatures most often differ from memory.

### 2. Verify the import path resolves

The path in your `import` must match `remappings.txt`:

```bash
cat remappings.txt
ls lib/v4-periphery/src/                    # confirm the directory exists
find lib -name 'BaseHook.sol'               # returns NOTHING at our pin — this is real
```

### 3. Record it

Append to `docs/RECON.md` §6 with **file path and line number**, at the pinned commit:

```
lib/v4-core/src/libraries/Hooks.sol:38    uint160 internal constant BEFORE_SWAP_FLAG = 1 << 7;
```

**Never hand-transcribe.** Redirect output to the file (`DECISIONS.md` D-0009).

### 4. For a deployed address — two independent sources

Documentation alone is not sufficient.

```bash
cast code <address> --rpc-url https://mainnet.unichain.org | wc -c     # non-empty?
cast call <other-contract> "poolManager()(address)" --rpc-url ...      # does a second contract agree?
```

Only addresses in `docs/RECON.md` §7 may be used. **Never invent an address.**

### 5. Compile the assumption

If a signature is load-bearing, write the smallest possible contract that imports and calls it,
and build. `src/CompileCanary.sol` is the Phase 0 example. A passing `forge build` is stronger
evidence than any amount of reading.

## Stopping rule

**If you cannot verify it, write `UNVERIFIED` and stop.**

Stopping is correct behaviour. Guessing is the worst available outcome, because the product
owner is not a Solidity programmer and will not catch it.

## Then, and only then

Before implementing: state your assumptions explicitly → identify the attack surface → propose a
design → update the documentation → implement → test → review adversarially → update
`CURRENT_STATE.md`.
