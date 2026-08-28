# SECURITY.md — Windward

**This file was rewritten on 2026-08-28.** It previously described Keel, a runtime accounting
guard that no longer exists (killed in `DECISIONS.md` D-0013). Windward is a different thing with
a different risk profile, and the old properties do not transfer.

---

## 1. What Windward is

A Uniswap v4 hook that sets the LP fee per swap from a time-decayed estimate of the pool's own
realised tick variance. It reads `slot0`, writes two storage slots, and returns a fee.

**It is a heuristic.** It is motivated by the observation that loss-versus-rebalancing grows with
price variance. It is **not** an implementation of any optimal policy from the stochastic-control
literature, and the claim that it improves LP outcomes is **unvalidated** (`DECISIONS.md` D-0019).
The word *optimal* may not be used to describe it.

## 2. The governing property

> **Windward cannot move funds. It can only price them.**

This is narrower than the property the old Keel document asserted, and the difference matters.

**What is structurally guaranteed** — enforced by the protocol, not by our discipline:

- `beforeSwap` returns `BeforeSwapDeltaLibrary.ZERO_DELTA`; `afterSwap` returns `0`.
- The deployed address has all four `*_RETURNS_DELTA_FLAG` bits clear, so v4 **never parses** a
  returned delta (`Hooks.sol:266`, `:301`; `PoolManager.sol:181`, `:224`). Even a returned
  non-zero delta would be discarded.
- The constructor calls `Hooks.validateHookPermissions` with the full 14-flag set, so a
  mis-mined address cannot be deployed at all.
- The hook holds no token balances and has no transfer path. Asserted by test.

**What is NOT guaranteed, and must not be claimed:**

- The **fee override is an accounting-affecting lever.** `Pool.sol:303-307` uses it to decide how
  much value moves from the swapper to the LPs on that swap. Windward steers it between `feeMin`
  and `feeMax`. "Never touches accounting" is false for this contract and was removed.
- A fee that is too high prices honest flow out of the pool. **That is the dominant harm**, and
  it is the analogue of the old project's asymmetry rule: *a false ceiling that prices out honest
  flow is worse than the LVR it prevents.*

## 3. Privileged roles

**None.** No owner, no admin, no governance, no upgrade path, no pause, no setters. All five
parameters are `immutable` and set in the constructor. There is no `delegatecall`, no proxy, and
no assembly outside the `sqrt` bit-scan.

A consequence worth stating plainly: **a badly-parameterised deployment is unrecoverable.** The
constructor validates what it can (`feeMin <= feeMax < MAX_LP_FEE`, `0 < halfLife <= MAX_DT`,
bounded `feePerSigma`, exact permission bits), but `feePerSigma` itself has no principled value.

## 4. Trust boundaries

| Boundary | Trusted? | Notes |
|---|---|---|
| Uniswap v4 `PoolManager` | **Trusted** | Assumed correct. `StateLibrary` reads its storage directly. |
| The pool's tick history | **Semi-trusted** | Written by the PoolManager and not forgeable by a caller — but a caller *can* steer it by trading. See §5. |
| Swappers / LPs / searchers | **Untrusted** | Fully adversarial, can order and repeat their own calls. |
| Pool tokens | **Not reached** | Windward never touches a token. FoT/rebasing/reentrant tokens are structurally out of scope. |
| The deployer | **Untrusted after deployment** | Immutability means they retain no power. |

## 5. Known limitations of the signal

Stated here because they are security-relevant, not merely economic.

- **The tick is steerable.** Anyone can move the tick by trading, and therefore influence the
  fee. Time-based decay bounds how long that influence lasts, and `MAX_OBSERVATION` bounds how
  large one observation can be, but a well-funded actor can still raise a pool's fee by trading
  it. The cost is their own price impact.
- **The fee is set from state that excludes the current swap.** The trader who moves the price
  pays the pre-move fee; the next trader pays the elevated one. This is a property of every
  reactive dynamic fee, and it is a real limitation, not a subtlety.
- **Same-block activity does not update the estimate** (`dt == 0`). This is deliberate — it is
  what closes the dust-swap suppression attack — but it means intra-block volatility is measured
  only at the next block.

## 6. Prohibited

- Using the word *optimal*, or claiming a validated LP benefit, anywhere.
- Presenting `test_sanity_higherFeeOnIdenticalVolumeCollectsMoreFees` as evidence. It proves
  `10000 > 500`.
- Quoting any statistic that did not come from `analysis/stats.py`. No hand-transcription.
- Adding an owner, pause, upgrade path or setter.
- Deploying bytecode built under a profile other than the one the address was mined against.
- `unchecked` arithmetic without a stated bound; string reverts; unbounded loops on the swap path.

## 7. Review status

Three independent reviews were run on 2026-08-28 (`security-reviewer`, `protocol-reviewer`,
`adversarial-reviewer`). Findings and their resolutions are in `DECISIONS.md` D-0018, and each
repair is pinned by a regression test in `test/WindwardAttack.t.sol`.

Closed and proven: **F-1** (permission bits unenforced), **W-01** (dust-swap fee suppression),
**W-02** (ceiling pinned indefinitely), **W-03** (200-pip fee ladder), **W-06**
(`feeMax == MAX_LP_FEE` bricks exact-output swaps), **W-07**, **W-10**, **W-12**.

Accepted, not fixed: the fee is set from pre-swap state (§5); the estimator conflates transient
and permanent price impact (`DECISIONS.md` D-0019).

**Not audited.** This is a hackathon prototype. It must not secure real funds.

## 8. Deployment requirements

1. Testnet only. Mainnet requires explicit owner approval.
2. Built with `FOUNDRY_PROFILE=deploy`, and the address mined against **that** bytecode.
3. Permission bits asserted on-chain post-deploy.
4. Full suite green, including the regression tests in `test/WindwardAttack.t.sol`.
5. `git submodule status` clean.
6. Verified source on the explorer.
7. Gas overhead re-measured (`test/WindwardGas.t.sol`); currently 11,192 per swap, ~15%.
