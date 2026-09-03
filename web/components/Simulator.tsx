"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { update, feeFor, sigmaWad, DEPLOYED, WAD } from "@/lib/volatility";

/**
 * A live tape running the DEPLOYED contract's arithmetic in the browser.
 *
 * Every fee shown here comes from lib/volatility.ts, a BigInt port of Volatility.sol pinned to
 * the same fixed vector as the Solidity and Python implementations (`npm run verify`). It is the
 * contract's integer truncation, not a floating-point impression of it.
 */

type Regime = "calm" | "normal" | "burst";

const REGIMES: Record<Regime, { label: string; move: [number, number]; gap: [number, number] }> = {
  calm: { label: "Calm", move: [0, 1], gap: [3, 9] },
  normal: { label: "Normal", move: [0, 4], gap: [1, 5] },
  burst: { label: "Volatile", move: [6, 42], gap: [1, 2] },
};

const KEEP = 96;
const STATIC_FEE = 500;

/** Deterministic PRNG, so the demo is the same every time it is shown. */
function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

export default function Simulator() {
  const [regime, setRegime] = useState<Regime>("normal");
  const [running, setRunning] = useState(true);
  const [pts, setPts] = useState<number[]>([STATIC_FEE]);
  const [readout, setReadout] = useState({ fee: 500, sigma: "0.00", moved: 0 });

  const st = useRef({ variance: 0n, tick: 0n, rand: rng(0x57494e44), scripted: 0 });
  const regimeRef = useRef(regime);
  regimeRef.current = regime;

  const step = useCallback(() => {
    const s = st.current;
    const r = REGIMES[regimeRef.current];
    const [mLo, mHi] = r.move;
    const [gLo, gHi] = r.gap;

    const mag = Math.round(mLo + s.rand() * (mHi - mLo));
    const dir = s.rand() < 0.5 ? -1 : 1;
    const dt = BigInt(Math.max(1, Math.round(gLo + s.rand() * (gHi - gLo))));
    const next = s.tick + BigInt(mag * dir);

    s.variance = update(s.variance, s.tick, next, dt, DEPLOYED.halfLife);
    s.tick = next;

    const fee = Number(feeFor(s.variance, DEPLOYED.feeMin, DEPLOYED.feeMax, DEPLOYED.feePerSigma));
    const sig = Number((sigmaWad(s.variance) * 100n) / WAD) / 100;

    setPts((p) => [...p.slice(-(KEEP - 1)), fee]);
    setReadout({ fee, sigma: sig.toFixed(2), moved: mag });
  }, []);

  useEffect(() => {
    if (!running) return;
    const id = setInterval(step, 130);
    return () => clearInterval(id);
  }, [running, step]);

  const reset = () => {
    st.current = { variance: 0n, tick: 0n, rand: rng(0x57494e44), scripted: 0 };
    setPts([STATIC_FEE]);
    setReadout({ fee: 500, sigma: "0.00", moved: 0 });
  };

  // Chart geometry
  const W = 760;
  const H = 260;
  const padL = 46;
  const padB = 26;
  const padT = 18;
  const top = Math.max(1200, Math.max(...pts) * 1.18);
  const x = (i: number) => padL + (i / Math.max(1, KEEP - 1)) * (W - padL - 12);
  const y = (v: number) =>
    H - padB - ((v - STATIC_FEE) / (top - STATIC_FEE)) * (H - padB - padT);

  const line = pts.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(" ");
  const area = `${line} L${x(pts.length - 1).toFixed(1)},${H - padB} L${x(0).toFixed(1)},${H - padB} Z`;
  const pct = ((readout.fee / STATIC_FEE - 1) * 100).toFixed(0);

  return (
    <div className="sim">
      <div className="sim-head">
        <div className="sim-read">
          <span className="mono lbl">Fee this swap</span>
          <b className="tnum">
            {(readout.fee / 10000).toFixed(3)}
            <em>%</em>
          </b>
          <span className="mono sub">
            {readout.fee} pips · {pct === "0" ? "at" : `+${pct}% over`} the {STATIC_FEE}-pip floor
          </span>
        </div>
        <div className="sim-read alt">
          <span className="mono lbl">σ (ticks/√s)</span>
          <b className="tnum">{readout.sigma}</b>
          <span className="mono sub">last move {readout.moved} ticks</span>
        </div>
        <div className="sim-ctl">
          {(Object.keys(REGIMES) as Regime[]).map((k) => (
            <button
              key={k}
              className={`chip${regime === k ? " on" : ""}`}
              onClick={() => setRegime(k)}
            >
              {REGIMES[k].label}
            </button>
          ))}
          <button className="chip ghost" onClick={() => setRunning((v) => !v)}>
            {running ? "Pause" : "Play"}
          </button>
          <button className="chip ghost" onClick={reset}>
            Reset
          </button>
        </div>
      </div>

      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Fee responding to simulated volatility">
        <defs>
          <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--signal)" stopOpacity="0.22" />
            <stop offset="100%" stopColor="var(--signal)" stopOpacity="0" />
          </linearGradient>
        </defs>

        {[0, 0.25, 0.5, 0.75, 1].map((g) => {
          const v = STATIC_FEE + g * (top - STATIC_FEE);
          return (
            <g key={g}>
              <line x1={padL} y1={y(v)} x2={W - 12} y2={y(v)} stroke="var(--rule-2)" />
              <text x={padL - 8} y={y(v) + 3.5} textAnchor="end" className="axis-t">
                {(v / 10000).toFixed(2)}%
              </text>
            </g>
          );
        })}

        <line
          x1={padL}
          y1={y(STATIC_FEE)}
          x2={W - 12}
          y2={y(STATIC_FEE)}
          stroke="var(--noise)"
          strokeWidth="1.5"
          strokeDasharray="5 4"
        />
        <text x={W - 14} y={y(STATIC_FEE) - 7} textAnchor="end" className="axis-t">
          static 0.05% tier
        </text>

        <path d={area} fill="url(#fade)" />
        <path d={line} fill="none" stroke="var(--signal)" strokeWidth="2" strokeLinejoin="round" />
        {pts.length > 1 && (
          <circle cx={x(pts.length - 1)} cy={y(pts[pts.length - 1])} r="3.5" fill="var(--signal)" />
        )}
      </svg>

      <p className="sim-foot mono">
        Running <code>Volatility.sol</code> arithmetic in BigInt. feeMin {String(DEPLOYED.feeMin)},
        feeMax {String(DEPLOYED.feeMax)}, feePerSigma {String(DEPLOYED.feePerSigma)}, halfLife{" "}
        {String(DEPLOYED.halfLife)}s. Same parameters as the deployed hook. Seeded, so it replays
        identically.
      </p>
    </div>
  );
}
