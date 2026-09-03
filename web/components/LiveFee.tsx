"use client";

import { useEffect, useRef, useState } from "react";
import { readLive, RPC_URL, POOL_ID, HOOK, type Live } from "@/lib/chain";
import type { Hex } from "viem";

/** One poll of the deployed hook. `swap` marks a sample that landed after the visitor traded. */
type Sample = { fee: number; t: number; swap: boolean };

const POLL_MS = 4000;
const KEEP = 90; // 6 minutes of history at the poll interval

/**
 * The deployed hook's current fee, read from chain every few seconds and PLOTTED over time.
 *
 * Read-only on purpose: no wallet, no signature, no transaction. The point is that a visitor can
 * see the contract's real state without trusting anything on this page.
 *
 * The chart is the argument, not decoration. A single number cannot show the two things that
 * make this hook different from a static fee: that trading pushes the fee up, and that it comes
 * back down on elapsed time alone, with nobody trading and no keeper poking it. Both are only
 * visible as a shape over time, so the samples are kept rather than overwritten.
 */
export default function LiveFee() {
  const [live, setLive] = useState<Live | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [hist, setHist] = useState<Sample[]>([]);
  // Set by SwapPanel when a swap confirms, so the next sample can be marked on the chart.
  const swapPending = useRef(false);

  useEffect(() => {
    const onSwap = () => { swapPending.current = true; };
    window.addEventListener("windward:swap", onSwap);
    return () => window.removeEventListener("windward:swap", onSwap);
  }, []);

  useEffect(() => {
    if (!POOL_ID) return;
    let alive = true;
    const tick = async () => {
      try {
        const l = await readLive(POOL_ID as Hex);
        if (!alive) return;
        setLive(l); setErr(null);
        if (l.initialised) {
          const marked = swapPending.current;
          swapPending.current = false;
          setHist((h) => [...h, { fee: l.fee, t: Date.now(), swap: marked }].slice(-KEEP));
        }
      } catch (e) {
        if (alive) setErr(e instanceof Error ? e.message : "read failed");
      }
    };
    tick();
    const id = setInterval(tick, POLL_MS);
    return () => { alive = false; clearInterval(id); };
  }, []);

  const host = (() => { try { return new URL(RPC_URL).host; } catch { return RPC_URL; } })();

  if (!POOL_ID) {
    return (
      <div className="live idle">
        <p className="mono">
          No pool configured. Create one with{" "}
          <code>forge script script/SeedPool.s.sol:SeedPool</code>, then set{" "}
          <code>NEXT_PUBLIC_POOL_ID</code> and <code>NEXT_PUBLIC_RPC_URL</code> — see{" "}
          <code>web/.env.example</code>. Pools in v4 are permissionless; the hook simply had none
          yet.
        </p>
      </div>
    );
  }

  return (
    <div className="live">
      <div className="live-head">
        <span className={`pulse${live && !err ? " on" : ""}`} aria-hidden="true" />
        <span className="mono lbl">
          {err ? "read failed" : live ? `live · block ${live.block}` : "connecting…"}
        </span>
        <span className="mono host">{host}</span>
      </div>

      {err ? (
        <p className="mono live-err">{err}</p>
      ) : !live ? (
        <p className="mono live-err">Reading the hook…</p>
      ) : !live.initialised ? (
        <p className="mono live-err">
          That pool id has no price yet — it was never initialised on this RPC.
        </p>
      ) : (
        <div className="live-grid">
          <div>
            <span className="mono lbl">Fee right now</span>
            <b className="tnum">
              {(live.fee / 10000).toFixed(3)}
              <em>%</em>
            </b>
            <span className="mono sub">{live.fee} pips</span>
          </div>
          <div>
            <span className="mono lbl">σ on chain</span>
            <b className="tnum alt">{live.sigma.toFixed(2)}</b>
            <span className="mono sub">ticks/√s</span>
          </div>
          <div>
            <span className="mono lbl">Pool tick</span>
            <b className="tnum alt">{live.tick}</b>
            <span className="mono sub">from StateView</span>
          </div>
        </div>
      )}

      {hist.length > 1 && <LiveChart hist={hist} />}

      <p className="mono live-foot">
        Read directly from <code>{HOOK.slice(0, 10)}…{HOOK.slice(-6)}</code> — no wallet, no
        signing. Every point is one poll of <code>currentFee</code>. Swap below, or run{" "}
        <code>script/Trade.s.sol</code>, and the line moves within seconds.
      </p>
    </div>
  );
}

const W = 720;
const H = 132;
const PAD_L = 46;
const PAD_R = 14;
const PAD_T = 12;
const PAD_B = 18;

/**
 * The fee over time.
 *
 * The floor is pinned at 500 pips so the dashed static-fee line always means the same thing, but
 * the top of the axis fits the data. Pinning the top at the 1% ceiling instead is more literal
 * and much worse: a real 40-pip move renders as a flat line on the floor, which reads as "this
 * does nothing". The gridlines carry real percentages and the caption states the ceiling, so a
 * fitted axis cannot be mistaken for a run at the maximum.
 */
function LiveChart({ hist }: { hist: Sample[] }) {
  const lo = 500;
  const peak = Math.max(...hist.map((s) => s.fee));
  // Fit the top to the data with headroom, but never claim a range narrower than 300 pips —
  // otherwise sampling noise on a resting pool fills the panel.
  const hi = Math.min(10_000, Math.max(650, Math.round((peak * 1.2) / 25) * 25));
  const zoomed = hi < 10_000;
  const n = hist.length;

  const x = (i: number) => PAD_L + (i / Math.max(1, n - 1)) * (W - PAD_L - PAD_R);
  const y = (fee: number) => {
    const c = Math.min(hi, Math.max(lo, fee));
    return PAD_T + (1 - (c - lo) / (hi - lo)) * (H - PAD_T - PAD_B);
  };

  const line = hist.map((s, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(s.fee).toFixed(1)}`).join(" ");
  const area = `${line} L${x(n - 1).toFixed(1)},${(H - PAD_B).toFixed(1)} L${x(0).toFixed(1)},${(H - PAD_B).toFixed(1)} Z`;

  const first = hist[0].fee;
  const last = hist[n - 1].fee;
  const delta = last - first;
  const span = Math.round(((hist[n - 1].t - hist[0].t) / 1000));

  return (
    <div className="live-chart">
      <svg viewBox={`0 0 ${W} ${H}`} role="img"
        aria-label={`Fee charged by the deployed hook over the last ${span} seconds`}>
        <defs>
          <linearGradient id="liveFade" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--signal)" stopOpacity="0.20" />
            <stop offset="100%" stopColor="var(--signal)" stopOpacity="0" />
          </linearGradient>
        </defs>

        {[0, 0.5, 1].map((f) => {
          const g = lo + f * (hi - lo);
          return (
            <g key={f}>
              <line x1={PAD_L} y1={y(g)} x2={W - PAD_R} y2={y(g)} stroke="var(--rule-2)" />
              <text x={PAD_L - 8} y={y(g) + 3.5} textAnchor="end" className="axis-t">
                {(g / 10000).toFixed(3)}%
              </text>
            </g>
          );
        })}

        {/* The floor: what a static 0.05% pool would charge for all of this. */}
        <line x1={PAD_L} y1={y(lo)} x2={W - PAD_R} y2={y(lo)}
          stroke="var(--noise)" strokeWidth="1" strokeDasharray="4 4" opacity="0.7" />

        <path d={area} fill="url(#liveFade)" />
        <path d={line} fill="none" stroke="var(--signal)" strokeWidth="2"
          strokeLinejoin="round" strokeLinecap="round" />

        {hist.map((s, i) =>
          s.swap ? (
            <g key={i}>
              <line x1={x(i)} y1={PAD_T} x2={x(i)} y2={H - PAD_B}
                stroke="var(--violet-2)" strokeWidth="1" strokeDasharray="3 3" />
              <text x={x(i)} y={PAD_T - 2} textAnchor="middle" className="axis-t">your swap</text>
            </g>
          ) : null,
        )}

        <circle cx={x(n - 1)} cy={y(last)} r="3.5" fill="var(--signal)" />
      </svg>

      <p className="mono live-chart-foot">
        {span}s of chain history · {n} reads ·{" "}
        {delta === 0 ? "flat" : `${delta > 0 ? "+" : ""}${delta} pips`} since this page opened.
        Dashed line is the 0.05% floor a static pool would have charged throughout.
        {zoomed && " Axis fitted to the range shown; the hook's ceiling is 1%."}
      </p>
    </div>
  );
}
