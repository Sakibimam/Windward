"use client";

import { useEffect, useState } from "react";
import { readLive, RPC_URL, POOL_ID, HOOK, type Live } from "@/lib/chain";
import type { Hex } from "viem";

/**
 * The deployed hook's current fee, read from chain every few seconds.
 *
 * Read-only on purpose: no wallet, no signature, no transaction. The point is that a visitor
 * can see the contract's real state without trusting anything on this page.
 */
export default function LiveFee() {
  const [live, setLive] = useState<Live | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!POOL_ID) return;
    let alive = true;
    const tick = async () => {
      try {
        const l = await readLive(POOL_ID as Hex);
        if (alive) { setLive(l); setErr(null); }
      } catch (e) {
        if (alive) setErr(e instanceof Error ? e.message : "read failed");
      }
    };
    tick();
    const id = setInterval(tick, 4000);
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

      <p className="mono live-foot">
        Read directly from <code>{HOOK.slice(0, 10)}…{HOOK.slice(-6)}</code> — no wallet, no
        signing. Trade the pool with <code>script/Trade.s.sol</code> and this moves within seconds.
      </p>
    </div>
  );
}
