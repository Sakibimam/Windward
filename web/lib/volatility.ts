/**
 * A faithful TypeScript port of `src/lib/Volatility.sol`.
 *
 * This exists so the simulator on the site runs the SAME arithmetic the deployed contract
 * runs — including its integer truncation — rather than a floating-point impression of it.
 * Everything is BigInt for that reason: the truncation is the point, not a rounding detail.
 *
 * It is pinned to the same fixed vector as the Solidity and Python implementations
 * (`test/VolatilityDifferential.t.sol`, `analysis/test_differential.py`). Run
 * `npm run verify` to check all three still agree. If this file drifts, that check fails.
 */

export const WAD = 1_000_000_000_000_000_000n;
export const MAX_DT = 604_800n; // 7 days
export const MAX_OBSERVATION = 100_000_000n; // 1e8

/** floor(sqrt(x)) for any non-negative BigInt. Mirrors Volatility.sqrt. */
export function sqrt(x: bigint): bigint {
  if (x < 0n) throw new RangeError("sqrt of negative");
  if (x === 0n) return 0n;
  // Initial guess at or below sqrt(x), then Newton until it stops descending.
  let y = 1n;
  let z = x;
  while (z >= 0x100000000n) {
    z >>= 32n;
    y <<= 16n;
  }
  while (z >= 0x100n) {
    z >>= 8n;
    y <<= 4n;
  }
  while (z >= 0x4n) {
    z >>= 2n;
    y <<= 1n;
  }
  let prev = 0n;
  for (let i = 0; i < 128 && y !== prev; i++) {
    prev = y;
    y = (y + x / y) >> 1n;
  }
  const q = x / y;
  return y < q ? y : q;
}

/** `2^(-dt/halfLife)`, WAD-scaled. Mirrors Volatility.decayFactor, interpolation included. */
export function decayFactor(dt: bigint, halfLife: bigint): bigint {
  if (halfLife === 0n) return 0n;
  const n = dt / halfLife;
  if (n >= 64n) return 0n;
  let w = WAD >> n;
  const rem = dt % halfLife;
  if (rem !== 0n) w -= (w * rem) / (2n * halfLife);
  return w;
}

/** Mirrors Volatility.update. `dt === 0` is an identity — the anchor is held, not advanced. */
export function update(
  varianceWad: bigint,
  tickBefore: bigint,
  tickAfter: bigint,
  dt: bigint,
  halfLife: bigint,
): bigint {
  if (dt === 0n) return varianceWad;
  if (dt > MAX_DT) dt = MAX_DT;

  const diff = tickAfter - tickBefore;
  const absDiff = diff < 0n ? -diff : diff;
  const sq = absDiff * absDiff;

  // WAD scaling BEFORE the division. Dividing first is the bug the study found.
  let observationWad = (sq * WAD) / dt;
  const capWad = MAX_OBSERVATION * WAD;
  if (observationWad > capWad) observationWad = capWad;

  const w = decayFactor(dt, halfLife);
  return (w * varianceWad + (WAD - w) * observationWad) / WAD;
}

/** sigma, WAD-scaled, in ticks per sqrt(second). Mirrors Volatility.sigmaWad. */
export function sigmaWad(varianceWad: bigint): bigint {
  return sqrt(varianceWad * WAD);
}

/** Mirrors WindwardHook._feeFor: clamp(feeMin + sigma * feePerSigma, feeMin, feeMax). */
export function feeFor(
  varianceWad: bigint,
  feeMin: bigint,
  feeMax: bigint,
  feePerSigma: bigint,
): bigint {
  const premium = (sigmaWad(varianceWad) * feePerSigma) / WAD;
  const fee = feeMin + premium;
  return fee > feeMax ? feeMax : fee;
}

/** The deployed parameters, read back from chain and recorded in docs/DEPLOYMENT.md. */
export const DEPLOYED = {
  feeMin: 500n,
  feeMax: 10_000n,
  feePerSigma: 200n,
  halfLife: 300n,
  address: "0x609634584d5BD12Ba4216116528e364d385Ad0C0",
  chainId: 1301,
  block: 61_265_509,
} as const;
