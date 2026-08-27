"""Canonical Python model of src/lib/Volatility.sol.

This is a REIMPLEMENTATION, not the deployed Solidity. `analysis/stats.py` replays this
model over historical flow; the contract is what actually runs on chain. The two are held
together by a differential test on a fixed vector:

    analysis/test_differential.py     asserts THIS model reproduces the vector
    test/VolatilityDifferential.t.sol asserts Volatility.sol reproduces the SAME vector

Both files hardcode the same expected numbers, so if either implementation drifts, one of
the two tests fails. Keep the two in sync or the replay stops being evidence about the
contract.

NOTE ON UNITS: the on-chain contract measures `dt` in SECONDS (block.timestamp deltas).
The replay measures `dt` in BLOCKS, because the dataset carries block numbers. Unichain
produces one block per second, so the two coincide there — but that is a substitution, and
it is stated wherever the replay's output is reported.
"""

WAD = 10**18
MAX_DT = 7 * 24 * 3600
MAX_OBSERVATION = 10**8


def decay_factor(dt: int, half_life: int) -> int:
    """2^(-dt/half_life), WAD-scaled. Mirrors Volatility.decayFactor."""
    if half_life == 0:
        return 0
    n = dt // half_life
    if n >= 64:
        return 0
    w = WAD >> n
    rem = dt % half_life
    if rem:
        w -= (w * rem) // (2 * half_life)
    return w


def update(variance_wad: int, tick_before: int, tick_after: int, dt: int, half_life: int) -> int:
    """Mirrors Volatility.update."""
    if dt == 0:
        return variance_wad
    if dt > MAX_DT:
        dt = MAX_DT
    d = abs(tick_after - tick_before)
    obs = (d * d * WAD) // dt
    cap = MAX_OBSERVATION * WAD
    if obs > cap:
        obs = cap
    w = decay_factor(dt, half_life)
    return (w * variance_wad + (WAD - w) * obs) // WAD


def isqrt(x: int) -> int:
    import math
    return math.isqrt(x)


def sigma_wad(variance_wad: int) -> int:
    """Mirrors Volatility.sigmaWad."""
    return isqrt(variance_wad * WAD)


def fee(variance_wad: int, fee_min: int, fee_max: int, fee_per_sigma: int) -> int:
    """Mirrors WindwardHook._feeFor."""
    premium = (sigma_wad(variance_wad) * fee_per_sigma) // WAD
    f = fee_min + premium
    return fee_max if f > fee_max else f


# ---------------------------------------------------------------------------
# The fixed differential vector. Both test files assert against these exact numbers.
# Chosen to exercise: a normal move, a same-second swap (dt==0 identity), a long gap
# (heavy decay), a sub-unit move that the old integer division would have truncated to
# zero, and the observation cap.
# ---------------------------------------------------------------------------
HALF_LIFE = 300
FEE_MIN, FEE_MAX, FEE_PER_SIGMA = 500, 10_000, 200

# (tickBefore, tickAfter, dt)
VECTOR = [
    (0, 10, 1),          # normal move
    (10, 10, 0),         # dt == 0 -> identity
    (10, 12, 25),        # small move over a long gap: old code truncated this to zero
    (12, 12, 3600),      # quiet hour: decay only
    (12, 5000, 1),       # violent move
    (5000, 5000, 86400), # a day of silence
    (5000, 5001, 1),     # tiny move after the gap
    (5001, -900000, 1),  # beyond the tick range -> observation cap binds
]


def run_vector():
    """Returns the running variance after each step, plus the fee at each step."""
    var = 0
    out = []
    for (tb, ta, dt) in VECTOR:
        var = update(var, tb, ta, dt, HALF_LIFE)
        out.append((var, sigma_wad(var), fee(var, FEE_MIN, FEE_MAX, FEE_PER_SIGMA)))
    return out


if __name__ == "__main__":
    print("Reference vector (half_life=300, feeMin=500, feeMax=10000, feePerSigma=200)")
    print(f"{'step':>4} {'tickBefore':>11} {'tickAfter':>10} {'dt':>7} "
          f"{'varianceWad':>26} {'sigmaWad':>22} {'fee':>6}")
    for i, ((tb, ta, dt), (v, s, f)) in enumerate(zip(VECTOR, run_vector())):
        print(f"{i:>4} {tb:>11} {ta:>10} {dt:>7} {v:>26} {s:>22} {f:>6}")
