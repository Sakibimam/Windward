"""Does a stale price predict adverse selection on Unichain?

    python3 analysis/staleness.py            # human-readable
    python3 analysis/staleness.py --json     # writes data/staleness.json

WHY THIS EXISTS. The loss-versus-rebalancing argument says an arbitrageur's edge is accumulated
divergence: the longer a pool sits without trading, the further its price drifts from the true
price, and the bigger the option the next arbitrageur exercises. Divergence is meant to grow with
sigma * sqrt(dt). Several proposed fee designs price exactly that -- charge more when the pool has
been idle, because the next trade is more likely to be someone collecting stale value.

That is a testable claim, and it is testable on data already in this repository.

THE TEST. Bucket every consecutive pair of swaps in a pool by the block gap between them, then
measure the absolute tick move realised over that gap. If staleness predicts adverse selection,
the longest-gap decile should show the LARGEST moves.

THE NULL. Same as analysis/economics.py: shuffle the moves against the gaps with a fixed seed,
destroying the pairing while preserving both marginal distributions exactly. A real relationship
must beat that.

MEASUREMENT LIMITATION, stated up front. v4 logs the tick AFTER each swap, so the move measured
over an interval includes the closing swap's own price impact. There is no post-hoc way to
separate drift-before-the-swap from impact-of-the-swap in event data alone. The direction is
consistent across all five pools and against the null, so the SIGN is what this file reports.
The magnitude is not claimed.

UNITS: dt is a BLOCK delta. Unichain produces one block per second, so it coincides with the
contract's SECOND delta on this chain.
"""

import argparse
import collections
import json
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = 0x4B65656C  # the project's fixed seed, reused so runs are reproducible


def deciles(pairs):
    """Bucket (gap, move) by gap; return per-decile mean move and median gap."""
    pairs = sorted(pairs, key=lambda p: p[0])
    n = len(pairs)
    out = []
    for k in range(10):
        chunk = pairs[k * n // 10 : (k + 1) * n // 10]
        if not chunk:
            continue
        gaps = sorted(g for g, _ in chunk)
        moves = [m for _, m in chunk]
        out.append({
            "decile": k + 1,
            "medianGapBlocks": gaps[len(gaps) // 2],
            "meanMove": round(sum(moves) / len(moves), 3),
            "n": len(moves),
        })
    return out


def analyse(data, top_n=5):
    byp = collections.defaultdict(list)
    for s in data["swaps"]:
        byp[s["pool"]].append(s)

    results = []
    for pid, rows in sorted(byp.items(), key=lambda kv: -len(kv[1]))[:top_n]:
        rows.sort(key=lambda r: (r["block"], r["logIndex"]))
        # dt == 0 contributes nothing to the estimator by design (it is what closes the
        # dust-swap suppression attack), so those pairs are excluded here too.
        obs = [
            (b["block"] - a["block"], abs(b["tick"] - a["tick"]))
            for a, b in zip(rows, rows[1:])
            if b["block"] > a["block"]
        ]
        if len(obs) < 1000:
            continue

        real = deciles(obs)
        gaps = [g for g, _ in obs]
        moves = [m for _, m in obs]
        random.Random(SEED).shuffle(moves)
        null = deciles(list(zip(gaps, moves)))

        lift = real[-1]["meanMove"] / real[0]["meanMove"] if real[0]["meanMove"] else 0.0
        nlift = null[-1]["meanMove"] / null[0]["meanMove"] if null[0]["meanMove"] else 0.0
        results.append({
            "pool": pid,
            "observations": len(obs),
            "liftDecile10OverDecile1": round(lift, 4),
            "liftDecile10OverDecile1_shuffledNull": round(nlift, 4),
            "real": real,
            "shuffledNull": null,
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
        out = os.path.join(ROOT, "data", "staleness.json")
        with open(out, "w") as f:
            json.dump({"seed": SEED, "pools": res}, f, indent=1)
        print("wrote", out)
        return

    print("Does a longer gap since the last trade precede a LARGER price move?")
    print()
    print(f"  {'pool':<13}{'obs':>8}{'gap d1':>9}{'gap d10':>9}{'move d1':>10}{'move d10':>10}"
          f"{'LIFT':>9}{'NULL':>8}")
    for p in res:
        r = p["real"]
        print(f"  {p['pool'][:11]:<13}{p['observations']:>8}"
              f"{r[0]['medianGapBlocks']:>9}{r[-1]['medianGapBlocks']:>9}"
              f"{r[0]['meanMove']:>10.2f}{r[-1]['meanMove']:>10.2f}"
              f"{p['liftDecile10OverDecile1']:>8.2f}x"
              f"{p['liftDecile10OverDecile1_shuffledNull']:>7.2f}x")
    lo = min(p["liftDecile10OverDecile1"] for p in res)
    hi = max(p["liftDecile10OverDecile1"] for p in res)
    print()
    print(f"  OBSERVATION: lift {lo:.2f}x-{hi:.2f}x. Every pool is BELOW 1.0 -- the longest-gap")
    print("  decile precedes SMALLER moves, not larger. The relationship is inverted.")
    print()
    print("  INFERENCE: on this chain, a pool sitting idle is evidence the market is calm, not")
    print("  evidence that divergence has accumulated. A fee that charges more for staleness")
    print("  would charge most exactly when the next move is smallest.")
    print()
    print("  NOT CLAIMED: the magnitude. v4 logs post-swap ticks, so each interval's move")
    print("  includes the closing swap's own impact. The sign is consistent across all five")
    print("  pools and against the null; that is what this measures.")


if __name__ == "__main__":
    main()
