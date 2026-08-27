"""Python half of the differential test against src/lib/Volatility.sol.

    python3 analysis/test_differential.py

Asserts that `analysis/volatility_model.py` — the model `analysis/stats.py` replays over
historical flow — reproduces the same fixed vector that `test/VolatilityDifferential.t.sol`
asserts the CONTRACT reproduces. The expected numbers below are duplicated verbatim in that
Solidity file on purpose: if either implementation drifts, one of the two tests fails.

Without this pair, the study's headline numbers would be a property of a model of the hook
rather than of the hook itself.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from volatility_model import (  # noqa: E402
    FEE_MAX, FEE_MIN, FEE_PER_SIGMA, HALF_LIFE, decay_factor, fee, sigma_wad, update,
)

FAILURES = []


def check(name, got, want):
    if got == want:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}\n         got  {got}\n         want {want}")
        FAILURES.append(name)


# (tickBefore, tickAfter, dt, expectedVariance, expectedSigmaWad, expectedFee)
STEPS = [
    (0, 10, 1, 166666666666666600, 408248290463862934, 581),
    (10, 10, 0, 166666666666666600, 408248290463862934, 581),
    (10, 12, 25, 166388888888888825, 407907941684013826, 581),
    (12, 12, 3600, 40622287326388, 6373561588812647, 501),
    (12, 5000, 1, 41466906707221233594081, 203634247382951853003, 10000),
    (5000, 5000, 86400, 0, 0, 500),
    (5000, 5001, 1, 1666666666666666, 40824829046386293, 508),
    (5001, -900000, 1, 166666668330555488888888, 408248292501702312862, 10000),
]

print("=== fixed vector (must match test/VolatilityDifferential.t.sol exactly) ===")
v = 0
for i, (tb, ta, dt, ev, es, ef) in enumerate(STEPS):
    v = update(v, tb, ta, dt, HALF_LIFE)
    check(f"step{i} variance", v, ev)
    check(f"step{i} sigmaWad", sigma_wad(v), es)
    check(f"step{i} fee", fee(v, FEE_MIN, FEE_MAX, FEE_PER_SIGMA), ef)

print()
print("=== decayFactor ===")
for dt, want in [(0, 1000000000000000000), (300, 500000000000000000), (600, 250000000000000000),
                 (150, 750000000000000000), (25, 958333333333333334),
                 (3600, 244140625000000), (86400, 0)]:
    check(f"decayFactor({dt},300)", decay_factor(dt, 300), want)

print()
if FAILURES:
    print(f"FAILED: {len(FAILURES)} check(s)")
    sys.exit(1)
print("Python model agrees with the vector asserted against Volatility.sol.")
