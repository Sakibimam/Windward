# docs/RECON.md — Reconnaissance Evidence

All output in this file was produced on **2026-08-28** on the machine described below.
Everything here is `FACT` unless explicitly tagged otherwise. Where a claim could not be
verified at the time it is tagged `UNVERIFIED` and no value is guessed.

This file is the evidence backing every pin, address, and signature quoted anywhere else in the
repository. **If any other document disagrees with this one, this one wins.**

---


## 1. Machine environment

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

## 2. RPC endpoints

### 2.1 What is configured

`FACT` No RPC-related environment variables are set on this machine
(`env | grep -iE 'rpc|alchemy|infura|etherscan|unichain'` → empty).
`FACT` There is no `~/.foundry/foundry.toml`.

### 2.2 Public Unichain endpoint — verified working

```
$ cast chain-id --rpc-url https://mainnet.unichain.org
130

$ cast block-number --rpc-url https://mainnet.unichain.org
57146322
```

### 2.3 Archive availability — verified

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
back to block 1,000,000. This makes fork reproduction on Unichain plausible **without**
a paid archive provider.

`UNVERIFIED` Whether that endpoint tolerates the request volume of a fork test suite, and
whether it serves archive `eth_getProof` / debug traces. Rate limiting has not been tested.
Ethereum mainnet archive access has not been tested at all — the Bunni incident spanned
Ethereum and Unichain, so a fork-based reproduction may still need a key.

---

## 3. Dependency resolution

### 3.1 Live registry queries (verbatim, 2026-08-28)

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

> **Correction, 2026-08-28.** The `refs/tags/v1.2.1` line in the block above was
> originally transcribed with the wrong sha (`7170eec9…`, which is actually `v1.2.0-rc.1`).
> The block above now reflects a live re-query:
> `git ls-remote --tags https://github.com/OpenZeppelin/uniswap-hooks | grep -E 'v1\.2'`.
> The prose sha was correct throughout. Logged as an accuracy incident in `DECISIONS.md` D-0009.

**This dependency is deliberately not vendored yet** — see `DECISIONS.md` D-0005.

### 3.2 v4-core resolved from v4-periphery's own submodule pin

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

### 3.3 Final pin set — recorded and verified locally

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

### 3.4 Compilation evidence — the pins actually work together

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

## 4. Secrets check

> **Corrected.** An earlier revision of this file recorded a `git ls-files` result showing
> `.env.example` as the sole match — but `.env.example` **did not exist on disk** and nothing had
> been committed, so that output could not have been produced as shown. The file was created and
> every check below genuinely re-run. Logged as D-0009: evidence written down without being
> produced.

`.gitignore` covers `.env`, `.env.*` (with a `!.env.example` negation), `*.key`, `*.pem`,
`keystore/`, `secrets/`, `out/`, `cache/`, `broadcast/`, `node_modules/`.

Re-run 2026-08-28, output redirected to file:

```
$ git ls-files | grep -i -E "\.env|secret|key"
.env.example

$ git check-ignore -v .env .env.local
.gitignore:9:.env	.env
.gitignore:10:.env.*	.env.local

$ git check-ignore -v .env.example        # the ! negation must un-ignore this one
```

`FACT` The only tracked match is `.env.example`, which holds placeholder values only. It carries
no RPC key and no private key; the deployment section instructs the use of a Foundry keystore
account and explicitly says not to paste a raw key.

`FACT` `git check-ignore` returns nothing for `.env.example` in the output above because the
file is now **tracked** — check-ignore skips tracked paths. Before it was staged, the same
command reported `.gitignore:11:!.env.example`, i.e. the negation matched. Being tracked is
itself the stronger proof that the negation works.

`FACT` `.env` cannot be committed. An attempt to stage a throwaway `.env` was refused by git:

```
$ git add .env
The following paths are ignored by one of your .gitignore files:
.env
hint: Use -f if you really want to add them.
```

`git add -f` is additionally blocked by local tooling policy, so the ignore rule cannot be
bypassed by accident.

---

## 5. Verified Uniswap v4 facts (source: files on disk at the pins above)

These are the earliest-verified v4 API facts. **A later full sweep is in `docs/RECON-hooks.md`** — do not
treat this list as complete.

### 5.1 Hook permission flags — `lib/v4-core/src/libraries/Hooks.sol`

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

`INFERENCE` An early design's "observe and revert only, never touch accounting" property
means the hook address must have the four `*_RETURNS_DELTA_FLAG` bits (bits 0–3) **clear**.
That is a checkable, testable property of the deployed address, and the test suite asserts it.

### 5.2 `IHooks` callback declarations — `lib/v4-core/src/interfaces/IHooks.sol`

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
and the fee-override encoding. Full signatures with return types are in `docs/RECON-hooks.md` — do not
write hook code from the line numbers above alone.

`FACT` Swap parameters live in a type named `SwapParams` imported from
`@uniswap/v4-core/src/types/PoolOperation.sol` (v4-periphery `dce236d` imports that path). They
are **not** `IPoolManager.SwapParams` at these pins. This is a change from older v4 code and is
exactly the kind of stale-training-data error the brief warns about.

### 5.3 `BaseHook` is NOT in v4-periphery at this pin

`FACT` `find lib/v4-periphery/src -name 'BaseHook.sol'` returns **nothing**.
`lib/v4-periphery/src/` contains `base/`, `hooks/permissionedPools/`, `interfaces/`, `lens/`,
`libraries/`, `PositionDescriptor.sol`, `PositionManager.sol`, `UniswapV4DeployerCompetition.sol`,
`V4Router.sol`. There is no `src/utils/` directory.

`INFERENCE` Any tutorial, blog post, or training-data memory that says
`import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol"` is **wrong at this pin**.
The hook must either use OpenZeppelin `uniswap-hooks`' `BaseHook` or implement `IHooks`
directly. This is an open decision recorded as D-0005 in `DECISIONS.md`.

---

## 6. Verified Unichain deployment addresses

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

> **Verified 2026-08-28 (Block 6 prep).** `cast chain-id` -> **1301**. PoolManager
> `0x00b036b58a818b1bc34d502d3fe730db729e62ac` has 48021 hex chars of code, and **two
> independent deployed contracts confirm it**: `StateView(0xc199f107...).poolManager()` and
> `PositionManager(0xf969aee6...).poolManager()` both return
> `0x00B036B58a818B1BC34d502D3fE730Db729e62AC`. No longer `UNVERIFIED`.

`UNVERIFIED` `0x2BAD8182C09F50c8318d769245beA52C32Be46CD` — the PoolManager owner. Not yet
identified. It matters for the threat model (the owner controls protocol fees), so later work
should identify it.

---
