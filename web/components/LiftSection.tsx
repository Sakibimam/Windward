"use client";

import { useState } from "react";
import BarChart from "./BarChart";
import { pools, yMax, fmt } from "@/lib/data";

export default function LiftSection() {
  const [i, setI] = useState(0);
  const p = pools[i];
  const real = p.real.decileLift.map((d) => d.meanForwardMove);
  const nul = p.shuffledNull.decileLift.map((d) => d.meanForwardMove);
  const lo = p.real.decileLift[0].feeMin;
  const hi = p.real.decileLift[p.real.decileLift.length - 1].feeMax;

  return (
    <>
      <div className="tabs" role="tablist" aria-label="Pool">
        {pools.map((q, k) => (
          <button
            key={q.pool}
            role="tab"
            aria-selected={k === i}
            className={`tab${k === i ? " on" : ""}`}
            onClick={() => setI(k)}
          >
            <em className="mono">{q.pool.slice(0, 8)}…</em>
            <span className="mono">{fmt(q.swaps)} swaps</span>
          </button>
        ))}
      </div>

      <div className="twin">
        <BarChart
          series={real}
          yMax={yMax}
          variant="signal"
          label="Real order"
          caption={`Fee climbs ${lo} → ${hi} pips across the deciles.`}
        />
        <BarChart
          series={nul}
          yMax={yMax}
          variant="noise"
          label="Shuffled"
          caption="Same moves, same gaps, order destroyed."
        />
      </div>

      <div className="verdict">
        <div className="stat">
          <b className="tnum">{p.liftDecile10OverDecile1.toFixed(2)}×</b>
          <span className="mono">top decile / bottom decile</span>
        </div>
        <div className="stat">
          <b className="tnum mute">{p.liftDecile10OverDecile1_shuffledNull.toFixed(2)}×</b>
          <span className="mono">same test, shuffled</span>
        </div>
        <div className="rho mono">
          Spearman ρ vs forward variance
          <br />
          <b>{p.real.spearmanFeeVsForwardVariance}</b> real&nbsp; ·&nbsp;{" "}
          <b className="mute">{p.shuffledNull.spearmanFeeVsForwardVariance}</b> null
        </div>
      </div>
    </>
  );
}
