/**
 * Three scenarios, rendered from the real estimator.
 *
 * This is a server component: the series below are produced at build time by the same BigInt
 * port of `Volatility.sol` that drives the live simulator, using the deployed parameters. The
 * shapes are model output, not drawings — if the mechanism changed, these curves would change
 * with it.
 */
import { update, feeFor, decayFactor, DEPLOYED, WAD } from "@/lib/volatility";

const { feeMin, feeMax, feePerSigma, halfLife } = DEPLOYED;
const fee = (v: bigint) => Number(feeFor(v, feeMin, feeMax, feePerSigma));
const pct = (pips: number) => (pips / 10_000).toFixed(2);

/** Walk a tick path, one observation per `dt` seconds, collecting the fee after each. */
function walk(moves: number[], dt: bigint): number[] {
  let variance = 0n;
  let tick = 0n;
  const out: number[] = [fee(variance)];
  for (const m of moves) {
    const next = tick + BigInt(m);
    variance = update(variance, tick, next, dt, halfLife);
    tick = next;
    out.push(fee(variance));
  }
  return out;
}

/** A pool left completely alone: no trades, only elapsed time. */
function settle(from: bigint, steps: number, dtEach: bigint): number[] {
  const out: number[] = [];
  let v = from;
  for (let i = 0; i <= steps; i++) {
    out.push(fee(v));
    v = (decayFactor(dtEach, halfLife) * v) / WAD;
  }
  return out;
}

const calm = walk([1, -1, 1, -1, 2, -1, 1, -2, 1, -1, 1, -1], 12n);

/** A stress regime: ±320-tick swings, one every second. */
const rough = Array.from({ length: 12 }, (_, i) => (i % 2 ? -1 : 1) * (320 + ((i * 7) % 23)));
const wild = walk(rough, 1n);

// Take the wild pool's end state, then stop trading entirely.
let hot = 0n;
{
  let tick = 0n;
  for (const m of rough) {
    const next = tick + BigInt(m);
    hot = update(hot, tick, next, 1n, halfLife);
    tick = next;
  }
}
const quiet = settle(hot, 12, 260n);

const SCENARIOS = [
  {
    key: "calm",
    label: "Quiet market",
    series: calm,
    note: "A tick or two, minutes apart. The fee stays at its floor.",
  },
  {
    key: "wild",
    label: "Violent market",
    series: wild,
    note: "Hundreds of ticks, every second. The fee climbs toward its ceiling.",
  },
  {
    key: "settle",
    label: "Left alone",
    series: quiet,
    note: "Nobody trades at all. Elapsed time alone brings it back down.",
  },
];

const W = 260;
const H = 74;

function path(series: number[]) {
  const lo = Number(feeMin);
  const hi = Number(feeMax);
  const span = hi - lo || 1;
  return series
    .map((v, i) => {
      const x = (i / (series.length - 1)) * W;
      const y = H - ((v - lo) / span) * H;
      return `${i === 0 ? "M" : "L"}${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
}

export default function FeeStates() {
  return (
    <div className="states">
      {SCENARIOS.map((s) => {
        const end = s.series[s.series.length - 1];
        return (
          <figure key={s.key} className={`state ${s.key}`}>
            <figcaption>
              <span className="mono state-label">{s.label}</span>
              <span className="state-fee tnum">
                {pct(end)}<i>%</i>
              </span>
            </figcaption>
            <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`${s.label}: fee ends at ${pct(end)} percent`}>
              <path className="state-line" d={path(s.series)} fill="none" />
            </svg>
            <p>{s.note}</p>
          </figure>
        );
      })}
    </div>
  );
}
