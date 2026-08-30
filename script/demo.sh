#!/usr/bin/env bash
# Windward demo. One command.
#
# Measured wall-clock: 6.8s cold (immediately after `forge clean`), 0.9s warm.
# NO NETWORK REQUIRED AT ALL. The demo reads only committed artifacts
# (data/stats.json) and runs local Foundry tests, so a fresh clone runs it offline.
# The 202MB raw dataset is NOT needed here - that is only for `analysis/run.sh`.
#
#   script/demo.sh
#
# Runs in seven acts:
#   1. the headline: the fee predicts the next move, and the null that could have refuted it
#   2. the signals that did NOT work, measured on real Unichain flow
#   3. the security findings, and proof each is closed
#   4. the repair, replayed over 426,807 real swaps
#   5. our own headline metrics failing their null
#   6. the hook working end to end against a real PoolManager
#   7. what is still unvalidated
set -euo pipefail
cd "$(dirname "$0")/.."

bold() { printf "\033[1m%s\033[0m\n" "$1"; }
rule() { printf '%.0s─' {1..76}; printf '\n'; }

rule; bold "WINDWARD — a volatility-adaptive fee hook for Uniswap v4"
echo "UHI10 · The Fair Flow Frontier"; rule

if [[ ! -f data/stats.json ]]; then
  echo "data/stats.json missing — run analysis/run.sh first (or --quick)."
  exit 1
fi
if [[ ! -f data/economics.json ]]; then
  echo "data/economics.json missing — run python3 analysis/economics.py --json first."
  exit 1
fi

bold "ACT 1 — the headline: Windward charges more right before the price moves"
python3 - <<'PY'
import json
e = json.load(open("data/economics.json"))
p = e["pools"][0]
r, n = p["real"], p["shuffledNull"]
print(f"  Busiest pool {p['pool'][:14]}..  {p['swaps']:,} swaps.")
print("  Bucket every swap by the fee it was charged, then measure the tick move that")
print("  actually followed. Beside it: the same test on shuffled data (same moves, same")
print("  gaps, order destroyed).")
print()
print(f"  {'fee decile':>11}{'fee range':>15}{'REAL next move':>17}{'SHUFFLED null':>16}")
for a, b in zip(r["decileLift"], n["decileLift"]):
    print(f"  {a['decile']:>11}{str(a['feeMin']) + '-' + str(a['feeMax']):>15}"
          f"{a['meanForwardMove']:>17}{b['meanForwardMove']:>16}")
print()
print(f"  Top decile over bottom decile:   REAL {r['decileLift'][-1]['meanForwardMove'] / r['decileLift'][0]['meanForwardMove']:.2f}x"
      f"      NULL {n['decileLift'][-1]['meanForwardMove'] / n['decileLift'][0]['meanForwardMove']:.2f}x")
print()
print("  Across all five busiest pools:")
lo = min(q["liftDecile10OverDecile1"] for q in e["pools"])
hi = max(q["liftDecile10OverDecile1"] for q in e["pools"])
nlo = min(q["liftDecile10OverDecile1_shuffledNull"] for q in e["pools"])
nhi = max(q["liftDecile10OverDecile1_shuffledNull"] for q in e["pools"])
for q in e["pools"]:
    print(f"    {q['pool'][:14]}..  real {q['liftDecile10OverDecile1']:>6.2f}x"
          f"     null {q['liftDecile10OverDecile1_shuffledNull']:>5.2f}x")
print()
print(f"  REAL {lo:.2f}-{hi:.2f}x versus NULL {nlo:.2f}-{nhi:.2f}x. The fee is tracking real structure.")
PY
echo

bold "ACT 2 — the signals that did not work"
echo "Every contention-based MEV signal, measured on 7 days of real Unichain v4 flow."
python3 - <<'PY'
import json
s = json.load(open("data/stats.json"))
m, pf = s["microstructure"], s["priorityFee"]
print(f"  sample: {m['swaps']:,} swaps · {m['spanDays']} days · {m['distinctPools']} pools")
print()
g = {x["label"]: x for x in pf["groups"]}
r = g["retail (Universal Router)"]
c1 = g["arb C1 (same-pool round trip)"]
c2 = g["arb C2 (multi-swap, non-UR)"]
print(f"  PRIORITY FEE   retail median   {r['median']:>12,} wei   (n={r['n']})")
print(f"                 arb C1 median   {c1['median']:>12,} wei   (n={c1['n']}, conservative)")
print(f"                 arb C2 median   {c2['median']:>12,} wei   (n={c2['n']}, broad)")
print(f"                 -> retail pays {pf.get('retail_over_C1_median_ratio')}x to "
      f"{pf.get('retail_over_C2_median_ratio')}x MORE than arbitrage flow.")
print("                    A priority-keyed fee would tax retail and subsidise arbs. KILLED.")
print()
print(f"  BLOCK POSITION {m['pctSwapsFirstOfBlockForTheirPool']}% of swaps are already alone "
      f"in their block. Nothing to discriminate. KILLED.")
print(f"  JIT            {m['jitEvents']} events in {m['spanDays']} days. Too rare. KILLED.")
print("  DIRECTION      pool-dependent, no chain-wide signal:")
for p in s["priceDynamics"]:
    print(f"                 {p['pool'][:14]}..  AC(1)={p['ac1_signed']:+.3f}  [{p['interpretation']}]")
print()
print("  => Windward depends on NONE of these. It reads only the pool's own tick history.")
PY
echo

bold "ACT 3 — the security findings, and proof each is closed"
echo "Three independent reviews. Each repair is pinned by a regression test."
forge test --match-path "test/WindwardAttack.t.sol" 2>&1 | grep -E "^\[(PASS|FAIL)|Suite result" || true
echo

bold "ACT 4 — the repair, replayed over the same 426,807 real swaps"
python3 - <<'PY'
import json
s = json.load(open("data/stats.json"))
print(f"  {'pool':<18}{'':>4}{'zero obs':>20}{'at fee floor':>20}{'distinct fees':>16}")
for w in s["windwardReplay"]:
    a, b = w["shipped_v1"], w["repaired"]
    print(f"  {w['pool'][:16]}..")
    print(f"      original {a['pctObservationsRoundingToZero']:>17}% "
          f"{a['pctAtFeeFloor']:>18}% {a['distinctFeeValues']:>15}")
    print(f"      repaired {b['pctObservationsRoundingToZero']:>17}% "
          f"{b['pctAtFeeFloor']:>18}% {b['distinctFeeValues']:>15}"
          f"   (fee p10/med/p90 {b['feeP10']}/{b['feeMedian']}/{b['feeP90']})")
print()
print("  The original charged the FEE FLOOR on up to 79.5% of real swaps.")
print("  It was a static fee wearing a dynamic fee's clothes. Found by replay, not by reading.")
PY
echo

bold "ACT 5 — and our OWN headline metrics fail the same null"
python3 - <<'PY'
import json
e = json.load(open("data/economics.json"))
print("  Shuffle each pool's real (move, gap) observations into a random order. Same")
print("  multiset, same heavy tail - only volatility CLUSTERING is destroyed.")
print()
print(f"  {'pool':<14}{'at floor R/N':>16}{'distinct R/N':>18}{'decile-10 lift':>17}{'null lift':>12}")
for p in e["pools"]:
    r, n = p["real"], p["shuffledNull"]
    lr = r["decileLift"][-1]["meanForwardMove"] / max(.01, r["decileLift"][0]["meanForwardMove"])
    ln = n["decileLift"][-1]["meanForwardMove"] / max(.01, n["decileLift"][0]["meanForwardMove"])
    print(f"  {p['pool'][:12]:<14}"
          f"{str(r['spread']['pctAtFeeFloor']) + '% / ' + str(n['spread']['pctAtFeeFloor']) + '%':>16}"
          f"{str(r['spread']['distinctFeeValues']) + ' / ' + str(n['spread']['distinctFeeValues']):>18}"
          f"{lr:>16.2f}x{ln:>11.2f}x")
print()
print("  'At floor' and 'distinct values' SURVIVE the shuffle - the null even wins a pool.")
print("  So neither can tell a good fee from a random one. We demoted our own headline.")
print("  The decile lift does NOT survive: the fee's top decile precedes moves 1.35-6.52x")
print("  larger than its bottom decile, against a null of 0.99-1.13x. That is the claim.")
PY
echo

bold "ACT 6 — the hook, end to end against a real PoolManager"
forge test --match-path "test/WindwardHook.t.sol" 2>&1 | grep -E "^\[(PASS|FAIL)|Suite result" || true
echo

bold "ACT 7 — what is still unvalidated"
cat <<'EOF'
  We measure FEE REVENUE, not LP PnL. There is no demand-elasticity model for the
  flow that leaves at a higher fee. Windward is a HEURISTIC motivated by the LVR
  literature - not an implementation of any optimal policy from it, and nothing here
  shows it makes LPs better off.

  We also found three errors in our own analysis (int24 sign extension, an inverted
  swap-direction convention, a wrong denominator). All three are now pinned by
  regression tests. Three earlier headline claims were retracted outright when the
  sample grew from 50 minutes to 7 days - see DECISIONS.md D-0020.
EOF
rule; bold "Reproduce everything:  analysis/run.sh"; rule
