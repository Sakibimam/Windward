#!/usr/bin/env bash
# Reproduce every number in the Unichain v4 microstructure study, from a fresh clone.
#
#   analysis/run.sh              # 7-day window, pinned end block
#   analysis/run.sh --quick      # 20k blocks / 200-tx sample: a SMOKE TEST, not a
#                                reproduction of the 7-day figures
#
# The end block is pinned in analysis/PINNED_END_BLOCK so a re-run reads the same
# chain range and produces identical numbers. Raw responses are cached per chunk under
# data/raw/, so a second run costs no network. Delete data/raw/ to force a refetch.
set -euo pipefail

cd "$(dirname "$0")/.."

DAYS=7
TXS=6000
if [[ "${1:-}" == "--quick" ]]; then
  DAYS=""
  TXS=200
fi

echo "==> 1/4  decoder regression tests"
echo "         (int24 sign extension, D-0017 E-2; Swap direction convention, D-0017 E-1)"
python3 analysis/test_decode.py

echo
echo "==> 2/4  collect (cached; delete data/raw/ to refetch)"
END_BLOCK="$(cat analysis/PINNED_END_BLOCK)"
if [[ -z "$DAYS" ]]; then
  python3 analysis/fetch.py --blocks 20000 --tx-sample "$TXS" --end-block "$END_BLOCK"
else
  python3 analysis/fetch.py --days "$DAYS" --tx-sample "$TXS" --end-block "$END_BLOCK"
fi

echo
echo "==> 3/4  statistics"
python3 analysis/stats.py
python3 analysis/stats.py --json

echo
echo "==> 4/4  economic test: shuffle null and fee predictiveness"
echo "         (does the fee track volatility, or only produce arithmetic variety?)"
python3 analysis/economics.py
python3 analysis/economics.py --json

echo
echo "==> rebuilding the demo page from the committed data"
python3 analysis/make_demo_page.py

echo
echo "Done. Machine-readable results: data/stats.json, data/economics.json"
echo "Gas figures come from data/gas_overhead.json (written by test/WindwardGas.t.sol)"
echo "and data/gas_economics.json (python3 analysis/gas_economics.py)."
