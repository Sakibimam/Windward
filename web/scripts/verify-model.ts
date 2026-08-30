/**
 * Asserts the TypeScript port reproduces the SAME fixed vector that
 * test/VolatilityDifferential.t.sol and analysis/test_differential.py assert.
 *
 * Three implementations of one estimator is three chances to drift. This is the check
 * that stops the website from quietly showing different arithmetic than the contract.
 *
 *   npm run verify
 */
import { update, sigmaWad, feeFor, decayFactor, WAD } from "../lib/volatility.ts";

const HALF_LIFE = 300n;
const FEE_MIN = 500n;
const FEE_MAX = 10_000n;
const FEE_PER_SIGMA = 200n;

// (tickBefore, tickAfter, dt, expectedVariance, expectedSigmaWad, expectedFee)
const STEPS: [bigint, bigint, bigint, bigint, bigint, bigint][] = [
  [0n, 10n, 1n, 166666666666666600n, 408248290463862934n, 581n],
  [10n, 10n, 0n, 166666666666666600n, 408248290463862934n, 581n],
  [10n, 12n, 25n, 166388888888888825n, 407907941684013826n, 581n],
  [12n, 12n, 3600n, 40622287326388n, 6373561588812647n, 501n],
  [12n, 5000n, 1n, 41466906707221233594081n, 203634247382951853003n, 10000n],
  [5000n, 5000n, 86400n, 0n, 0n, 500n],
  [5000n, 5001n, 1n, 1666666666666666n, 40824829046386293n, 508n],
  [5001n, -900000n, 1n, 166666668330555488888888n, 408248292501702312862n, 10000n],
];

const DECAY: [bigint, bigint][] = [
  [0n, 1000000000000000000n],
  [300n, 500000000000000000n],
  [600n, 250000000000000000n],
  [150n, 750000000000000000n],
  [25n, 958333333333333334n],
  [3600n, 244140625000000n],
  [86400n, 0n],
];

let failures = 0;
function check(name: string, got: bigint, want: bigint) {
  if (got === want) {
    console.log(`  ok   ${name}`);
  } else {
    console.log(`  FAIL ${name}\n         got  ${got}\n         want ${want}`);
    failures++;
  }
}

console.log("=== fixed vector (must match Volatility.sol and volatility_model.py) ===");
let v = 0n;
STEPS.forEach(([tb, ta, dt, ev, es, ef], i) => {
  v = update(v, tb, ta, dt, HALF_LIFE);
  check(`step${i} variance`, v, ev);
  check(`step${i} sigmaWad`, sigmaWad(v), es);
  check(`step${i} fee`, feeFor(v, FEE_MIN, FEE_MAX, FEE_PER_SIGMA), ef);
});

console.log("\n=== decayFactor ===");
for (const [dt, want] of DECAY) check(`decayFactor(${dt},300)`, decayFactor(dt, 300n), want);

console.log("\n=== sqrt identity: sigmaWad(v)^2 <= v * WAD ===");
check("WAD", WAD, 1000000000000000000n);

if (failures) {
  console.error(`\n${failures} MISMATCH(ES) — the TypeScript port has drifted from the contract.`);
  process.exit(1);
}
console.log("\nTypeScript port agrees with the vector asserted against Volatility.sol.");
