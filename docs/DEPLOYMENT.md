# docs/DEPLOYMENT.md — Windward on Unichain Sepolia

Testnet deployment evidence. **Every value below was read back from the chain after the fact,
not copied from the deploy script's own output.**

**This is a testnet deployment of an unaudited hackathon prototype. It must not secure real
funds, and nothing here authorises a mainnet deployment.**

---

## Deployment

| Field | Value |
|---|---|
| Network | **Unichain Sepolia** |
| Chain ID | **1301** (`cast chain-id`) |
| Contract | `WindwardHook` |
| **Address** | **`0x609634584d5BD12Ba4216116528e364d385Ad0C0`** |
| **Transaction** | **`0x93b108ef34bd2fedb017ad901271c1cb333138a772387ecb313d9958b4b8cd0c`** |
| Block | 61265509 |
| Timestamp | 1788117937 (2026-08-30 19:25:37 UTC) |
| Deployer (EOA) | `0x30c7eE328B80ce1dc15AC8F75e1FfAf51B9bB9Fb` |
| CREATE2 factory | `0x4e59b44847b379578588920cA78FbF26c0B4956C` |
| Salt | `0x0000000000000000000000000000000000000000000000000000000000005978` |
| Gas used | 1,282,893 |
| Effective gas price | 500,001 wei |
| Cost | 0.000000641447782893 ETH |
| Status | `1` (success) |
| Runtime code | 5,653 bytes |
| Build profile | `FOUNDRY_PROFILE=deploy` (`via_ir = true`, `optimizer_runs = 44444444`) |
| Keystore account | `windward-deployer` |
| Date | 2026-08-30 |

`FACT` This deployment **includes the H-1 fix** (decay on read, `_varianceNow`; `DECISIONS.md`
D-0023). It supersedes `0x7FEe02329eEc22dADEd64642B9ED47cE9b5110c0`, which predates that fix and
must no longer be cited.

`FACT` The receipt's `contractAddress` field is **empty**, and its `to` is the CREATE2 factory.
That is expected, not a problem: the transaction was sent *to* the factory, which performed the
creation internally, so the field that records a top-level `CREATE` is unset. The address is
confirmed by reading code at it.

## Verification, read back from chain

```
cast receipt 0x93b108ef…cd0c --rpc-url https://sepolia.unichain.org
  status 1 · blockNumber 61265509 · gasUsed 1282893 · effectiveGasPrice 500001
  from   0x30c7eE328B80ce1dc15AC8F75e1FfAf51B9bB9Fb
  to     0x4e59b44847b379578588920cA78FbF26c0B4956C   (the CREATE2 factory)

cast code 0x609634584d5BD12Ba4216116528e364d385Ad0C0 --rpc-url https://sepolia.unichain.org
  5,653 bytes present
```

### Source ↔ bytecode equivalence

`FACT` The deployed runtime code was compared byte-for-byte against
`out/WindwardHook.sol/WindwardHook.json` → `deployedBytecode`, rebuilt locally under
`FOUNDRY_PROFILE=deploy`:

- Both are **5,653 bytes**.
- They differ at exactly **111 byte positions**.
- **All 111 fall inside the `immutableReferences` ranges** the compiler records for the five
  `immutable` values. **Zero** differing bytes lie outside an immutable slot.

The immutables are then confirmed individually by calling their getters (below). **The live
contract is this source tree.**

### CREATE2 address derived independently

`FACT` Recomputing `keccak256(0xff ‖ factory ‖ salt ‖ keccak256(initcode))[12:]` from the
broadcast artifact reproduces the address exactly:

```
salt          0x…5978
initcode hash 0x33f2f1ec1da6b4d08b36cc9b2ba0d6694fb88a6b971bbfb422273a0c1f5aacf6
derived       0x609634584d5bd12ba4216116528e364d385ad0c0   ← matches the deployed address
```

### Permission bits, derived from the deployed address

The low 14 bits of the address **are** the hook's permission set (`Hooks.sol:27-47`), and the
constructor's `Hooks.validateHookPermissions` call would have reverted had they not matched.

| Flag | Bit | State |
|---|---|---|
| `AFTER_INITIALIZE_FLAG` | 12 | **set** |
| `BEFORE_SWAP_FLAG` | 7 | **set** |
| `AFTER_SWAP_FLAG` | 6 | **set** |
| `BEFORE_SWAP_RETURNS_DELTA_FLAG` | 3 | **clear** |
| `AFTER_SWAP_RETURNS_DELTA_FLAG` | 2 | **clear** |
| `AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG` | 1 | **clear** |
| `AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG` | 0 | **clear** |

`low-14 bits = 0x10c0 = 4288`, exactly the required pattern.

`FACT` **All four returns-delta bits are clear on the live address**, so v4 never parses a delta
this hook returns — the "cannot move funds" property is enforced by the protocol, on this
deployment, not merely asserted in a test.

### Immutables read from the live contract

| Getter | Value |
|---|---|
| `poolManager()` | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |
| `feeMin()` | 500 (0.05%) |
| `feeMax()` | 10000 (1.00%) |
| `feePerSigma()` | 200 |
| `halfLife()` | 300 s |

`FACT` `poolManager()` matches the Unichain Sepolia PoolManager recorded in `docs/RECON.md` §6
and independently confirmed by `StateView.poolManager()`.

`FACT` The parameters are the ones used throughout the test suite and the study replay, so the
deployed hook is the one the README's figures describe.

### No administrative surface

`FACT` `owner()`, `pause()`, `setFeeMin(uint24)`, `upgradeTo(address)` and
`transferOwnership(address)` all revert — the selectors do not exist. A control call to
`feeMin()` on the same contract returns `500`, so the reverts are the absent selectors and not a
broken endpoint. There is no owner, no pause, no upgrade path and no setter; every parameter is
`immutable`.

## Reproducing the address

```
FOUNDRY_PROFILE=deploy forge script script/Deploy.s.sol:Deploy \
  --rpc-url https://sepolia.unichain.org \
  --account windward-deployer \
  --sender 0x30c7eE328B80ce1dc15AC8F75e1FfAf51B9bB9Fb \
  --broadcast
```

`FOUNDRY_PROFILE=deploy` is **mandatory**: the address is mined against the bytecode that profile
produces, and deploying a different build to a mined address is the D-0006 trap. The script's
`_assertDeployProfile()` guard refuses to run under any other profile.

`FACT` The keystore account is **`windward-deployer`**, with no `0x` prefix — `cast wallet list`
renders it with one, and passing that form fails with `Keystore file … does not exist`. Foundry
prompts for the password on a TTY; with no TTY it aborts with `Device not configured (os error
6)`, so **this step cannot be run unattended**.

Mining is deterministic: the same source under the same profile yields salt `0x…5978` and address
`0x6096…d0C0`. Running the deploy a second time reverts with `CreateCollision` — CREATE2 refusing
to overwrite an existing contract. That is the expected outcome of a repeat run and is what
confirms the first one took effect.

## Superseded deployments

| Address | Block | Why superseded |
|---|---|---|
| `0x7FEe02329eEc22dADEd64642B9ED47cE9b5110c0` | 61165939 | Predates the H-1 fix (D-0023). Prices from an undecayed estimate: a pool driven to the 1% ceiling still quotes 1% a week later, and whoever breaks the silence pays it. Immutable, so it could not be patched. **Do not cite.** |

## Not done

- **Source verification on a block explorer.** Not yet performed. The bytecode equivalence check
  above is the substitute and is stronger in one respect: it is reproducible from this repo alone.
- **Pool initialisation.** No pool has been created against this hook. Any pool that uses it
  must be initialised with the dynamic-fee sentinel (`0x800000`), or `afterInitialize` reverts
  by design.
- **Mainnet.** Explicitly out of scope. `SECURITY.md` §8 requires separate approval.
