"""Does the Windward fee carry any economic information, or only arithmetic variety?

    python3 analysis/economics.py            # human-readable
    python3 analysis/economics.py --json     # writes data/economics.json

This script exists because of a specific objection raised in adversarial review:

    The README's headline metrics -- "sits at the floor 0.0% of the time" and "takes
    437-2,349 distinct values" -- describe the SPREAD of the fee, not its CORRECTNESS.
    A fee drawn from a random number generator would also never sit at the floor and
    would also take thousands of distinct values. Neither metric can distinguish a fee
    that tracks volatility from one that does not.

So the metrics are tested against a null that is designed to reproduce them by accident.

THE NULL. For each pool we take the real, ordered sequence of observations (d, dt),
where d = |tick_i - tick_{i-1}| and dt = block gap, and we SHUFFLE THEIR ORDER with a
fixed seed. This preserves the marginal distribution of moves and of gaps EXACTLY --
same multiset, same heavy tail, same median, same maximum. The only thing destroyed is
the time ordering, i.e. volatility clustering: the tendency of large moves to arrive
near other large moves.

    A metric that survives the shuffle is measuring the shape of the move distribution.
    A metric that collapses under the shuffle is measuring clustering, which is the only
    thing an adaptive fee could possibly exploit.

THE POSITIVE TEST. Predictiveness. At swap i the hook charges fee_i, computed from
history strictly BEFORE i. The interval that swap i opens then realises some volatility.
If the fee is informative, fee_i should be higher when the NEXT interval turns out to be
volatile. We report:

  - Spearman rank correlation between fee_i and the realised forward variance d^2/dt.
    Rank, not Pearson, because tick moves are heavy-tailed and Pearson would be dominated
    by a handful of outliers.
  - DECILE LIFT: bucket swaps by the fee they were charged, and report the median
    realised forward move in each bucket. This is the statistic that matters. A
    correlation of 0.05 is "significant" at n=400,000 and still economically worthless;
    a lift table shows the actual size of the effect.

Both are computed on the real series AND on the shuffled null, so the null gives the
value each statistic takes when clustering is absent by construction.

UNITS: dt is a BLOCK delta. Unichain produces one block per second, so it coincides with
the contract's SECOND delta on this chain.

SCOPE: the top `--top` busiest pools, matching analysis/stats.py's replay scope.

WHAT THIS DOES NOT SHOW. Nothing here is LP profit. A fee that correlates with forward
volatility is a necessary condition for the LVR story, not a sufficient one: it says the
fee is charged at the right TIMES, not that the resulting revenue exceeds the adverse
selection it is meant to offset, and not that the flow would have stayed at that price.
See README "What this does not show".
"""

import argparse
import collections
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import volatility_model as vm  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

WAD = 10**18
SEED = 0x4B65656C  # the project's fixed fuzz seed, reused so runs are reproducible


def fee_series(obs, fee_min=500, fee_max=10000, fee_per_sigma=200, half_life=300):
    """Run the SHIPPED (v4) estimator over a list of (d, dt) observations.

    Returns the fee charged at each observation, computed from state strictly BEFORE it --
    the same ordering the contract uses, where the trader who moves the price pays the
    pre-move fee.
    """
    var = 0
    fees = []
    for d, dt in obs:
        # Decay on read (finding H-1): the contract decays the stored estimate forward to the
        # current timestamp before pricing, without writing it. See WindwardHook._varianceNow.
        dtr = min(dt, 7 * 86400)
        vread = (vm.decay_factor(dtr, half_life) * var) // WAD if dtr else var
        fees.append(min(fee_max, fee_min + (math.isqrt(vread * WAD) * fee_per_sigma) // WAD))
        if dt == 0:
            continue  # dt==0 identity, matching the contract
        dtc = dtr
        obs_wad = min((d * d * WAD) // dtc, 10**8 * WAD)
        w = vm.decay_factor(dtc, half_life)
        var = (w * var + (WAD - w) * obs_wad) // WAD
    return fees


def spread_metrics(fees, fee_min=500, fee_max=10000):
    c = collections.Counter(fees)
    fs = sorted(fees)
    return {
        "pctAtFeeFloor": round(100 * c[fee_min] / len(fees), 1),
        "pctAtFeeCeiling": round(100 * c[fee_max] / len(fees), 1),
        "distinctFeeValues": len(c),
        "feeP10": fs[len(fs) // 10],
        "feeMedian": fs[len(fs) // 2],
        "feeP90": fs[9 * len(fs) // 10],
        "feeMean": round(sum(fees) / len(fees), 1),
    }


def _ranks(xs):
    """Average ranks, ties shared. Needed for Spearman without scipy."""
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    r = [0.0] * len(xs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            r[order[k]] = avg
        i = j + 1
    return r


def spearman(xs, ys):
    """Rank correlation. Returns None if either series is constant (rank undefined)."""
    if len(xs) < 3:
        return None
    rx, ry = _ranks(xs), _ranks(ys)
    n = len(rx)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    dx = math.sqrt(sum((a - mx) ** 2 for a in rx))
    dy = math.sqrt(sum((b - my) ** 2 for b in ry))
    if dx == 0 or dy == 0:
        return None
    return num / (dx * dy)


def decile_lift(fees, forward):
    """Median realised forward move, bucketed by the fee that was charged.

    The economically meaningful question: when Windward charges more, does more actually
    happen next? Reported as medians because the move distribution is heavy-tailed.
    """
    pairs = sorted(zip(fees, forward), key=lambda p: p[0])
    n = len(pairs)
    out = []
    for k in range(10):
        lo, hi = k * n // 10, (k + 1) * n // 10
        chunk = pairs[lo:hi]
        if not chunk:
            continue
        f = [p[0] for p in chunk]
        m = sorted(p[1] for p in chunk)
        out.append({
            "decile": k + 1,
            "feeMin": f[0], "feeMax": f[-1],
            # The median is reported but is nearly useless here: tick moves are small
            # integers, so the median is 1 or 2 in every decile regardless of the effect.
            # The mean and p90 are what resolve a heavy-tailed lift.
            "medianForwardMove": m[len(m) // 2],
            "meanForwardMove": round(sum(m) / len(m), 2),
            "p90ForwardMove": m[9 * len(m) // 10],
            "n": len(m),
        })
    return out


def analyse(data, top_n=5):
    byp = collections.defaultdict(list)
    for s in data["swaps"]:
        byp[s["pool"]].append(s)

    results = []
    for pid, rows in sorted(byp.items(), key=lambda kv: -len(kv[1]))[:top_n]:
        if len(rows) < 100:
            continue
        rows.sort(key=lambda r: (r["block"], r["logIndex"]))

        # The real, ordered observation stream.
        obs = []
        for a, b in zip(rows, rows[1:]):
            obs.append((abs(b["tick"] - a["tick"]), b["block"] - a["block"]))

        # The null: identical multiset of (d, dt), time ordering destroyed.
        shuffled = list(obs)
        random.Random(SEED).shuffle(shuffled)

        real_fees = fee_series(obs)
        null_fees = fee_series(shuffled)

        # Forward realised move: the move over the interval each swap OPENS. fee[i] is
        # charged before observation i lands, so obs[i] IS that forward interval.
        fwd_real = [d for d, _ in obs]
        fwd_null = [d for d, _ in shuffled]
        # Forward realised variance, the quantity the estimator is trying to track.
        fvar_real = [(d * d) / max(1, dt) for d, dt in obs]
        fvar_null = [(d * d) / max(1, dt) for d, dt in shuffled]

        def lift(dl):
            """Top-decile mean forward move over bottom-decile. Persisted so the README never
            has to recompute a ratio by hand (D-0017)."""
            return round(dl[-1]["meanForwardMove"] / dl[0]["meanForwardMove"], 4)

        results.append({
            "pool": pid,
            "swaps": len(rows),
            "observations": len(obs),
            "liftDecile10OverDecile1": lift(decile_lift(real_fees, fwd_real)),
            "liftDecile10OverDecile1_shuffledNull": lift(decile_lift(null_fees, fwd_null)),
            "real": {
                "spread": spread_metrics(real_fees),
                "spearmanFeeVsForwardMove": round(spearman(real_fees, fwd_real) or 0.0, 4),
                "spearmanFeeVsForwardVariance": round(spearman(real_fees, fvar_real) or 0.0, 4),
                "decileLift": decile_lift(real_fees, fwd_real),
            },
            "shuffledNull": {
                "spread": spread_metrics(null_fees),
                "spearmanFeeVsForwardMove": round(spearman(null_fees, fwd_null) or 0.0, 4),
                "spearmanFeeVsForwardVariance": round(spearman(null_fees, fvar_null) or 0.0, 4),
                "decileLift": decile_lift(null_fees, fwd_null),
            },
        })
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--top", type=int, default=5)
    ap.add_argument("--dataset", default=os.path.join(ROOT, "data", "unichain-dataset.json"))
    args = ap.parse_args()

    with open(args.dataset) as f:
        data = json.load(f)

    res = analyse(data, top_n=args.top)

    if args.json:
        out = os.path.join(ROOT, "data", "economics.json")
        with open(out, "w") as f:
            json.dump({"seed": SEED, "pools": res}, f, indent=1)
        print("wrote", out)
        return

    for p in res:
        print("=" * 78)
        print(f"pool {p['pool'][:18]}...  {p['swaps']} swaps, {p['observations']} observations")
        print("-" * 78)
        print(f"{'':34}{'REAL':>18}{'SHUFFLED NULL':>20}")
        r, n = p["real"], p["shuffledNull"]
        for k in ("pctAtFeeFloor", "distinctFeeValues", "feeMedian", "feeP90", "feeMean"):
            print(f"  {k:<32}{str(r['spread'][k]):>18}{str(n['spread'][k]):>20}")
        print(f"  {'spearman(fee, fwd move)':<32}{r['spearmanFeeVsForwardMove']:>18}"
              f"{n['spearmanFeeVsForwardMove']:>20}")
        print(f"  {'spearman(fee, fwd variance)':<32}{r['spearmanFeeVsForwardVariance']:>18}"
              f"{n['spearmanFeeVsForwardVariance']:>20}")
        print("  decile lift: realised forward tick move, bucketed by the fee charged")
        print(f"    {'decile':>7}{'fee range':>16}{'REAL mean':>12}{'REAL p90':>10}"
              f"{'NULL mean':>12}{'NULL p90':>10}")
        for a, b in zip(r["decileLift"], n["decileLift"]):
            print(f"    {a['decile']:>7}{str(a['feeMin']) + '-' + str(a['feeMax']):>16}"
                  f"{a['meanForwardMove']:>12}{a['p90ForwardMove']:>10}"
                  f"{b['meanForwardMove']:>12}{b['p90ForwardMove']:>10}")
        top, bot = r["decileLift"][-1], r["decileLift"][0]
        ntop, nbot = n["decileLift"][-1], n["decileLift"][0]
        print(f"  LIFT (decile 10 mean / decile 1 mean):"
              f"   REAL {top['meanForwardMove'] / max(0.01, bot['meanForwardMove']):.2f}x"
              f"   NULL {ntop['meanForwardMove'] / max(0.01, nbot['meanForwardMove']):.2f}x")


if __name__ == "__main__":
    main()
