"""Compute every statistic in the Unichain v4 microstructure study.

    python3 analysis/stats.py            # human-readable tables
    python3 analysis/stats.py --json     # machine-readable, written to data/stats.json

Every number quoted in the README, the deck or DECISIONS.md must come from here.
No hand-transcription: the writeup reads data/stats.json.
"""

import argparse
import collections
import json
import math
import os
import statistics as st
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import UNIVERSAL_ROUTER, caller_bought_token0  # noqa: E402
import volatility_model as vm  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---------------------------------------------------------------------------
# Arbitrage classification
# ---------------------------------------------------------------------------
# There is no ground truth for "this was an arbitrage". Two classifiers are reported
# side by side so the reader can see how much the headline depends on the choice.
#
# C1 SAME-POOL ROUND TRIP (conservative, high precision):
#     a transaction containing two or more swaps in the SAME pool in OPPOSITE directions.
#     A retail trade has no reason to buy and sell the same pair in one transaction, so
#     false positives should be rare. It will MISS multi-pool cyclic arbitrage entirely,
#     so it under-counts.
#
# C2 MULTI-SWAP NON-ROUTER (broad, lower precision):
#     two or more swaps in one transaction, not entered through the Universal Router.
#     FALSE POSITIVE RISK, stated explicitly: a multi-hop retail trade routed through any
#     aggregator that is not the Universal Router (1inch, CoW, Odos, Matcha) looks
#     identical to a cyclic arb under this rule. This classifier over-counts.
#
# RETAIL proxy: tx.to == Universal Router.
#     FALSE POSITIVE RISK: sophisticated actors can and do route through the Universal
#     Router. Treat "retail" as "flow entering through the canonical retail path", not as
#     "provably uninformed".
def classify_txs(swaps):
    by_tx = collections.defaultdict(list)
    for s in swaps:
        by_tx[s["tx"]].append(s)

    c1, c2, retail = set(), set(), set()
    for tx, ss in by_tx.items():
        by_pool = collections.defaultdict(list)
        for s in ss:
            by_pool[s["pool"]].append(s)
        for _pool, ps in by_pool.items():
            if len(ps) >= 2:
                dirs = {caller_bought_token0(p) for p in ps}
                if len(dirs) > 1:
                    c1.add(tx)
                    break
    return by_tx, c1, c2, retail


def priority_fee_analysis(data):
    swaps, txs, base = data["swaps"], data["txs"], data["baseFee"]
    by_tx, c1, _, _ = classify_txs(swaps)

    rows = []
    for tx, info in txs.items():
        bf = base.get(str(info["block"]))
        if bf is None:
            continue
        ss = by_tx.get(tx, [])
        rows.append({
            "tx": tx,
            "prio": info["gasPrice"] - bf,
            "to": info["to"],
            "nswaps": len(ss),
            "npools": len({s["pool"] for s in ss}),
            "c1_roundtrip": tx in c1,
        })

    def summarise(label, sel, note):
        g = [r["prio"] for r in rows if sel(r)]
        if not g:
            return {"label": label, "n": 0, "note": note}
        g.sort()
        return {
            "label": label, "n": len(g), "note": note,
            "min": g[0], "p25": g[len(g) // 4], "median": g[len(g) // 2],
            "p75": g[3 * len(g) // 4], "p90": g[int(len(g) * 0.9)], "max": g[-1],
            "pct_zero": round(100 * sum(1 for x in g if x <= 0) / len(g), 2),
            "mean": int(sum(g) / len(g)),
        }

    retail = summarise("retail (Universal Router)", lambda r: r["to"] == UNIVERSAL_ROUTER,
                       "FP risk: sophisticated actors also route through the UR")
    arb1 = summarise("arb C1 (same-pool round trip)", lambda r: r["c1_roundtrip"],
                     "conservative; misses multi-pool cyclic arbitrage")
    arb2 = summarise("arb C2 (multi-swap, non-UR)", lambda r: r["nswaps"] >= 2 and r["to"] != UNIVERSAL_ROUTER,
                     "FP risk: multi-hop retail via non-UR aggregators looks identical")
    allrows = summarise("all sampled swap txs", lambda r: True, "")

    out = {"groups": [retail, arb1, arb2, allrows], "sampledTxs": len(rows)}
    for arb in (arb1, arb2):
        if arb.get("n") and retail.get("n") and arb.get("median") is not None:
            m = max(arb["median"], 1)
            out[f"retail_over_{arb['label'].split()[1]}_median_ratio"] = round(retail["median"] / m, 1)
            grp = [r["prio"] for r in rows if (r["c1_roundtrip"] if arb is arb1
                                               else (r["nswaps"] >= 2 and r["to"] != UNIVERSAL_ROUTER))]
            below = sum(1 for x in grp if x < retail["median"])
            out[f"pct_{arb['label'].split()[1]}_below_retail_median"] = round(100 * below / len(grp), 1)
    return out


def microstructure(data):
    swaps, mods = data["swaps"], data["modifyLiquidity"]
    meta = data["meta"]
    pools = collections.Counter(s["pool"] for s in swaps)

    # first-of-block share, per pool
    seen_first = 0
    by_block = collections.defaultdict(list)
    for s in swaps:
        by_block[s["block"]].append(s)
    for _b, ss in by_block.items():
        seen = set()
        for s in sorted(ss, key=lambda x: x["logIndex"]):
            if s["pool"] not in seen:
                seen_first += 1
            seen.add(s["pool"])

    # JIT: same sender+pool+range adds then removes within 2 blocks
    key = lambda e: (e["sender"], e["pool"], e["tickLower"], e["tickUpper"])  # noqa: E731
    byk = collections.defaultdict(list)
    for e in mods:
        byk[key(e)].append(e)
    jit = 0
    for _k, es in byk.items():
        es.sort(key=lambda x: x["block"])
        for i, a in enumerate(es):
            if a["liquidityDelta"] <= 0:
                continue
            for b in es[i + 1:]:
                if b["liquidityDelta"] < 0:
                    if b["block"] - a["block"] <= 2:
                        jit += 1
                    break

    return {
        "startBlock": meta["startBlock"], "endBlock": meta["endBlock"],
        "spanBlocks": meta["spanBlocks"], "spanDays": round(meta["spanBlocks"] / 86400, 2),
        "swaps": len(swaps), "liquidityEvents": len(mods),
        "distinctPools": len(pools),
        "distinctLpSenders": len({e["sender"] for e in mods}),
        "distinctSwapRouters": len({s["sender"] for s in swaps}),
        "blocksWithSwaps": len(by_block),
        "pctSwapsFirstOfBlockForTheirPool": round(100 * seen_first / len(swaps), 1) if swaps else 0,
        "jitEvents": jit,
        "swapsPerDay": round(len(swaps) / (meta["spanBlocks"] / 86400)),
        "top5PoolShare": round(100 * sum(n for _, n in pools.most_common(5)) / len(swaps), 1) if swaps else 0,
        "top5SwapCount": sum(n for _, n in pools.most_common(5)),
        **_move_and_gap_distribution(swaps),
    }


def _move_and_gap_distribution(swaps, top_n=5):
    """Per-swap |tick move| and inter-swap BLOCK gap, over the pools the replay covers.

    The README previously asserted "1-6 tick moves over 1-13 second gaps" with nothing
    computing either. These are the real percentiles. Gaps are in BLOCKS: the dataset
    carries block numbers, and Unichain produces one block per second, so blocks and
    seconds coincide there - but the measured quantity is blocks.
    """
    byp = collections.defaultdict(list)
    for s in swaps:
        byp[s["pool"]].append(s)
    moves, gaps = [], []
    for _pid, rows in sorted(byp.items(), key=lambda kv: -len(kv[1]))[:top_n]:
        rows.sort(key=lambda r: (r["block"], r["logIndex"]))
        for a, b in zip(rows, rows[1:]):
            moves.append(abs(b["tick"] - a["tick"]))
            gaps.append(b["block"] - a["block"])
    if not moves:
        return {}
    moves.sort()
    gaps.sort()
    q = lambda v, p: v[min(int(len(v) * p), len(v) - 1)]  # noqa: E731
    return {
        "tickMoveP10": q(moves, .10), "tickMoveMedian": q(moves, .50), "tickMoveP90": q(moves, .90),
        "blockGapP10": q(gaps, .10), "blockGapMedian": q(gaps, .50), "blockGapP90": q(gaps, .90),
        "pctSameBlockConsecutiveSwaps": round(100 * sum(1 for g in gaps if g == 0) / len(gaps), 1),
        "moveGapSampleSize": len(moves),
    }


def price_dynamics(data, min_swaps=200, top_n=5):
    """Momentum vs mean reversion, per pool. Uses the pinned direction convention."""
    byp = collections.defaultdict(list)
    for s in data["swaps"]:
        byp[s["pool"]].append(s)
    out = []
    for pid, rows in sorted(byp.items(), key=lambda kv: -len(kv[1]))[:top_n]:
        if len(rows) < min_swaps:
            continue
        rows.sort(key=lambda r: (r["block"], r["logIndex"]))
        t = [r["tick"] for r in rows]
        r1 = [t[i + 1] - t[i] for i in range(len(t) - 1)]
        if len(r1) < 50 or st.pvariance(r1) == 0:
            continue
        m = st.mean(r1)
        num = sum((r1[i] - m) * (r1[i + 1] - m) for i in range(len(r1) - 1))
        den = sum((x - m) ** 2 for x in r1)
        ac1 = num / den if den else 0.0

        def vr(k):
            rk = [t[i + k] - t[i] for i in range(len(t) - k)]
            v1, vk = st.pvariance(r1), st.pvariance(rk)
            return round(vk / (k * v1), 3) if v1 else None

        # direction-conditional next-swap return, using the PINNED convention
        after_buy, after_sell = [], []
        for i in range(len(rows) - 1):
            d = t[i + 1] - t[i]
            (after_buy if caller_bought_token0(rows[i]) else after_sell).append(d)
        out.append({
            "pool": pid, "swaps": len(rows),
            "tickMin": min(t), "tickMax": max(t), "tickSpan": max(t) - min(t),
            "ac1_signed": round(ac1, 3),
            "varianceRatio": {str(k): vr(k) for k in (2, 4, 8, 16)},
            "meanNextTickAfterBuy": round(st.mean(after_buy), 3) if after_buy else None,
            "meanNextTickAfterSell": round(st.mean(after_sell), 3) if after_sell else None,
            "interpretation": "momentum" if ac1 > 0.05 else ("mean-reverting" if ac1 < -0.05 else "no signal"),
        })
    return out


def windward_replay(data, fee_min=500, fee_max=10000, fee_per_sigma=200, top_n=5):
    """What fee would the estimator have charged on real flow, and WHICH repair did what.

    SCOPE: this replays the `top_n` busiest pools only, NOT the whole dataset. The
    replayed swap count is reported explicitly so it can never be confused with the
    dataset total.

    MODEL, NOT CONTRACT: the "full" arm calls `analysis/volatility_model.py`, a Python
    reimplementation of src/lib/Volatility.sol. The two are pinned to a fixed vector by
    `analysis/test_differential.py` and `test/VolatilityDifferential.t.sol`.

    UNITS: `dt` here is a BLOCK delta; the contract uses a SECOND delta. Unichain produces
    one block per second, so they coincide there. Stated wherever this output is reported.

    ABLATION. Four arms isolate which of the five changes produced which effect:
      v1_original       integer (dTick^2)/dt, sqrt(var//WAD), per-observation EMA
                        alpha=0.3, dt clamped to [1,3600], observation cap 1e12
      v2_wad_only       + WAD carried through the division AND the sqrt. Nothing else.
      v3_wad_plus_decay + time-based decay (half-life 300) replacing the EMA
      v4_full           + dt==0 identity, the 1e8 observation cap, and DECAY ON READ
                        (== the contract)
    """
    WAD = 10**18
    ALPHA_V1 = 3 * 10**17
    HALF_LIFE = 300

    byp = collections.defaultdict(list)
    for s in data["swaps"]:
        byp[s["pool"]].append(s)

    out = []
    for pid, rows in sorted(byp.items(), key=lambda kv: -len(kv[1]))[:top_n]:
        if len(rows) < 100:
            continue
        rows.sort(key=lambda r: (r["block"], r["logIndex"]))

        def arm(mode):
            var, lt, lts = 0, rows[0]["tick"], rows[0]["block"]
            fees, zeros, considered = [], 0, 0
            for r in rows[1:]:
                raw_dt = r["block"] - lts
                if mode == "v1":
                    fees.append(min(fee_max, fee_min + math.isqrt(var // WAD) * fee_per_sigma))
                elif mode == "v4":
                    # DECAY ON READ (finding H-1). The shipped contract decays the stored
                    # estimate forward to the current timestamp before pricing, so a quiet
                    # pool quotes a falling fee with no trade required. Read-only: `var`
                    # itself is not written here, exactly as in `_varianceNow`.
                    rd = min(raw_dt, 7 * 86400)
                    vr = (vm.decay_factor(rd, HALF_LIFE) * var) // WAD if rd else var
                    fees.append(min(fee_max, fee_min + (math.isqrt(vr * WAD) * fee_per_sigma) // WAD))
                else:
                    fees.append(min(fee_max, fee_min + (math.isqrt(var * WAD) * fee_per_sigma) // WAD))
                if mode == "v4" and raw_dt == 0:
                    continue  # dt==0 identity; anchor held
                dt = max(1, min(3600, raw_dt)) if mode in ("v1", "v2", "v3") else min(raw_dt, 7 * 86400)
                d = abs(r["tick"] - lt)
                considered += 1
                if mode == "v1":
                    obs = min((d * d) // dt, 10**12)
                    if obs == 0:
                        zeros += 1
                    var = obs * ALPHA_V1 + (var * (WAD - ALPHA_V1)) // WAD
                else:
                    cap = (10**12 if mode == "v2" else 10**8) * WAD
                    obs = min((d * d * WAD) // dt, cap)
                    if obs == 0:
                        zeros += 1
                    if mode == "v2":
                        var = (obs * ALPHA_V1 + var * (WAD - ALPHA_V1)) // WAD
                    else:
                        w = vm.decay_factor(dt, HALF_LIFE)
                        var = (w * var + (WAD - w) * obs) // WAD
                lt, lts = r["tick"], r["block"]
            c = collections.Counter(fees)
            fs = sorted(fees)
            return {
                # NB: denominator is observations actually CONSIDERED by this arm, so the
                # v4 arm's dt==0 skips do not flatter its zero-observation rate.
                "pctObservationsRoundingToZero": round(100 * zeros / max(1, considered), 1),
                "observationsConsidered": considered,
                "pctAtFeeFloor": round(100 * c[fee_min] / len(fees), 1),
                "pctAtFeeCeiling": round(100 * c[fee_max] / len(fees), 1),
                "distinctFeeValues": len(c),
                "feeP10": fs[len(fs) // 10], "feeMedian": fs[len(fs) // 2],
                "feeP90": fs[9 * len(fs) // 10], "feeMax": fs[-1],
            }

        out.append({"pool": pid, "swaps": len(rows),
                    "shipped_v1": arm("v1"), "ablation_wadOnly": arm("v2"),
                    "ablation_wadPlusDecay": arm("v3"), "repaired": arm("v4")})

    return out


def swap_weighted_floor(replay):
    """Swap-weighted fee-floor share across the replayed pools, per arm.

    Persisted rather than left for prose to compute: every figure the README quotes must be
    readable out of data/stats.json, never arrived at by hand (D-0017).
    """
    total = sum(p["swaps"] for p in replay)
    if not total:
        return {}
    return {
        "swaps": total,
        "shipped_v1_pctAtFeeFloor": round(sum(p["shipped_v1"]["pctAtFeeFloor"] * p["swaps"] for p in replay) / total, 1),
        "repaired_pctAtFeeFloor": round(sum(p["repaired"]["pctAtFeeFloor"] * p["swaps"] for p in replay) / total, 1),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--dataset", default=os.path.join(ROOT, "data", "unichain-dataset.json"))
    args = ap.parse_args()

    with open(args.dataset) as f:
        data = json.load(f)

    result = {
        "microstructure": microstructure(data),
        "priorityFee": priority_fee_analysis(data),
        "priceDynamics": price_dynamics(data),
        "windwardReplay": (_wr := windward_replay(data)),
        "windwardReplaySwapWeighted": swap_weighted_floor(_wr),
    }

    if args.json:
        path = os.path.join(ROOT, "data", "stats.json")
        with open(path, "w") as f:
            json.dump(result, f, indent=2)
        print(f"wrote {path}")
        return

    m = result["microstructure"]
    print("=" * 78)
    print("UNICHAIN v4 MICROSTRUCTURE  |  blocks {startBlock}..{endBlock}  ({spanDays} days)".format(**m))
    print("=" * 78)
    for k in ("swaps", "swapsPerDay", "distinctPools", "top5PoolShare", "liquidityEvents",
              "distinctLpSenders", "distinctSwapRouters", "blocksWithSwaps",
              "pctSwapsFirstOfBlockForTheirPool", "jitEvents"):
        print(f"  {k:38s} {m[k]}")

    print("\n--- PRIORITY FEES (wei above base) ---")
    pf = result["priorityFee"]
    print(f"  sampled swap transactions: {pf['sampledTxs']}")
    for g in pf["groups"]:
        if not g.get("n"):
            print(f"  {g['label']:34s} n=0")
            continue
        print(f"  {g['label']:34s} n={g['n']:<6} med={g['median']:<12} p90={g['p90']:<12} "
              f"max={g['max']:<12} zero={g['pct_zero']}%")
        if g["note"]:
            print(f"      note: {g['note']}")
    for k, v in pf.items():
        if k.startswith("retail_over_") or k.startswith("pct_"):
            print(f"  {k:38s} {v}")

    print("\n--- PRICE DYNAMICS (pinned direction convention) ---")
    for p in result["priceDynamics"]:
        print(f"  {p['pool'][:16]}.. n={p['swaps']:<6} span={p['tickSpan']:<7} "
              f"AC(1)={p['ac1_signed']:+.3f} [{p['interpretation']}]  VR={p['varianceRatio']}")

    print("\n--- WHAT THE HOOK WOULD HAVE CHARGED ON REAL FLOW ---")
    print("    v1 = original implementation | rep = after the 2026-08-28 repairs")
    for w in result["windwardReplay"]:
        a, b = w["shipped_v1"], w["repaired"]
        print(f"  {w['pool'][:16]}.. n={w['swaps']}")
        print(f"      v1 : zeroObs={a['pctObservationsRoundingToZero']:>5}%  atFloor={a['pctAtFeeFloor']:>5}%  "
              f"distinct={a['distinctFeeValues']}")
        print(f"      rep: zeroObs={b['pctObservationsRoundingToZero']:>5}%  atFloor={b['pctAtFeeFloor']:>5}%  "
              f"distinct={b['distinctFeeValues']}  fee p10/med/p90={b['feeP10']}/{b['feeMedian']}/{b['feeP90']}")


if __name__ == "__main__":
    main()
