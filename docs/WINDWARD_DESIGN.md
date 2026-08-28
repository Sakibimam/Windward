# docs/WINDWARD_DESIGN.md

The frozen design. Implement only what is described here.

---

## 1. Problem

A static LP fee is wrong in both directions. It overcharges swappers when the market is calm, and
undercharges when the price is moving — which is exactly when passive LPs are being picked off by
arbitrageurs. Loss-versus-rebalancing grows with the variance of the price; a constant fee does
not.

Windward makes the fee track realised volatility, using only state the pool already has.

## 2. Assumptions, and which are verified

| # | Assumption | Status |
|---|---|---|
| A1 | A Uniswap tick is a log return: `price = 1.0001^tick`, so `d(ln p) = d(tick)·ln(1.0001)`, `ln(1.0001) = 9.9995e-5` | **Verified** |
| A2 | The post-swap tick is committed to `slot0` before `afterSwap` runs | **Verified** — `Pool.sol:439` precedes `PoolManager.sol:221` |
| A3 | A fee returned from `beforeSwap` with `OVERRIDE_FEE_FLAG` applies to that swap only | **Verified** — `Pool.sol:303-305`; `slot0.lpFee` is never written |
| A4 | The tick cannot be forged by a caller (only steered by trading) | **Verified** — written by the PoolManager |
| A5 | Realised pool-price variance is a useful proxy for the variance that drives LVR | **UNVERIFIED — this is the load-bearing economic assumption.** See §9 |
| A6 | Raising the fee with volatility improves LP outcomes net of lost flow | **UNVERIFIED.** No elasticity model exists |

**A5 and A6 are why this is a heuristic.** The stochastic-control literature models σ of an
*exogenous efficient price* under continuous arbitrage. Windward measures the realised variance
of the *pool* price, which also contains transient impact from uninformed flow. They are
different objects. Nothing here is optimal, and the word is banned from this repository
(`DECISIONS.md` D-0019).

## 3. Mathematical model

Let `τ` be the tick, `t` seconds, and `H` the half-life in seconds.

**Observation.** Between two timestamped observations separated by `dt > 0`:

```
obs = (Δτ)² / dt              [tick² per second]
```

capped at `MAX_OBSERVATION = 1e8` (a ~10,000-tick move in one second).

**Decay.** Weight retained by the previous estimate:

```
w(dt) = 2^(−dt/H)
```

Exact halvings for the integer part of `dt/H`, linear interpolation across the remainder. The
interpolation understates the true exponential by at most ~6% and is monotone non-increasing in
`dt` — the property that matters, since a longer gap must never retain more weight.

**Update.**

```
var' = w·var + (1 − w)·obs
```

**`dt = 0` is an identity**: `var' = var`, and the caller must *not* advance its stored tick or
timestamp. No time has elapsed, so there is no variance-per-unit-time to measure. Leaving the
anchor in place means a move split into same-block slices is measured in full at the next
timestamped observation instead of being erased. This is what closes the dust-swap attack.

**Sigma.** `σ = sqrt(var)`, carried WAD-scaled as `sqrt(var·WAD)`, in **ticks per √second**.
Not log-return units — the ~1e-4 factor from A1 is absorbed into `feePerSigma`. Not annualised.

**Fee.**

```
fee = clamp(feeMin + feePerSigma·σ, feeMin, feeMax)     [pips, 1e6 = 100%]
```

All divisions round **down**, biasing the fee toward the swapper. A fee slightly too low costs
LPs a little revenue; a fee too high prices honest flow out of the pool, which is worse.

## 4. State machine

Per pool: `(varianceWad, lastTick, lastTimestamp, initialized)`.

```
afterInitialize  ── require dynamic-fee pool ──▶ seed (0, tick, now, true)
                    else revert

beforeSwap       ── read varianceWad ──▶ return fee | OVERRIDE_FEE_FLAG
                    (state unchanged; view)

afterSwap  ─┬─ !initialized      ──▶ revert NotInitialized
            ├─ dt == 0           ──▶ return, state UNCHANGED (anchor held)
            └─ dt  > 0           ──▶ read slot0.tick
                                     var ← update(var, lastTick, tick, dt, H)
                                     lastTick ← tick;  lastTimestamp ← now
```

## 5. Parameters

| Name | Meaning | Constraint (enforced in constructor) |
|---|---|---|
| `feeMin` | fee floor, pips | `feeMin <= feeMax` |
| `feeMax` | fee ceiling, pips | `< MAX_LP_FEE` (1e6). At exactly 1e6, v4 reverts every exact-output swap |
| `feePerSigma` | pips per tick/√s | `<= type(uint128).max`, so the premium cannot overflow |
| `halfLife` | decay half-life, seconds | `0 < H <= MAX_DT` (7 days) |

All `immutable`. **`feePerSigma` has no derivation** — it is a free parameter, and a bad choice is
unrecoverable because the contract is immutable.

## 6. Permissions

`AFTER_INITIALIZE | BEFORE_SWAP | AFTER_SWAP`. All four `*_RETURNS_DELTA` bits clear.
The constructor calls `Hooks.validateHookPermissions` with the full 14-flag struct — checking only
the returns-delta bits left three silent failure modes, including a permanently fee-free pool.

## 7. Data model (the study)

`analysis/` is the only source of statistics. `fetch.py` collects and caches; `stats.py` computes
and writes `data/stats.json`; the writeup reads that file. **No number may be hand-transcribed.**

The collector handles three undocumented endpoint limits by adaptive halving: a 10,000-block
range cap, a response-size cap, and a 20,000-result cap.

## 8. Attack model

See `THREAT_MODEL.md`. Closed and regression-tested: dust-swap suppression, indefinite ceiling,
same-block slicing, silent mis-deployment, exact-output DoS, truncation, overflow.
Open and accepted: the tick is steerable by trading; the fee is set from pre-swap state; the
estimator conflates transient and permanent impact.

## 9. Limitations

1. **The LP benefit is unvalidated** (A5, A6). Fee revenue is not LP PnL. No elasticity model.
2. **The fee is charged to the trader after the mover.** Property of every reactive dynamic fee.
3. **Transient impact is taxed like permanent impact.** An out-and-back noise round trip produces
   two squared observations for zero LVR; a one-way informed move produces one.
4. **Steerable.** A funded actor can raise a pool's fee by trading it, paying their own impact.
5. **Gas is not yet measured.**
6. **The study is one chain, one window, a public RPC, and a sampled tx set.**

## 10. Test requirements

- Security properties: returns-delta bits clear; holds no tokens; `onlyPoolManager`;
  static-fee pool rejected.
- Regression, one per closed finding: `test/WindwardAttack.t.sol`.
- Library: sqrt is `floor(sqrt(x))` (fuzzed); decay monotone non-increasing and bounded (fuzzed);
  variance capped (fuzzed); `dt = 0` identity; small moves over long gaps survive.
- Convention: `test/SwapEventConvention.t.sol` pins the Swap sign convention to the protocol.
- Decoder: `analysis/test_decode.py` pins both historical decode bugs.
- **Forbidden:** any test asserting that a higher fee on identical forced volume collects more
  fees, presented as evidence. That is arithmetic. The one that exists is labelled a sanity check.
