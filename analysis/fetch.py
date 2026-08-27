"""Collect Unichain v4 data for the microstructure study.

Everything is cached per-chunk under data/raw/ so the pipeline is resumable and so a
re-run is cheap. Delete data/raw/ to force a full refetch.

    python3 analysis/fetch.py --days 7
    python3 analysis/fetch.py --blocks 10000 --tx-sample 500   # quick smoke run

Constraints discovered against the public endpoint (both verified, not assumed):
  * eth_getLogs rejects ranges over 10000 blocks ("block range greater than 10000 max")
  * JSON-RPC batches over 10 items are rejected
Unichain produces one block per second, so 7 days is 604800 blocks = 61 getLogs calls.
"""

import argparse
import json
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (  # noqa: E402
    MODIFY_LIQUIDITY_TOPIC, POOL_MANAGER, SWAP_TOPIC, decode_modify_liquidity,
    decode_swap, rpc, rpc_batch,
)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "data", "raw")
MAX_LOG_RANGE = 10_000
BATCH = 10


def _cache(name, produce):
    path = os.path.join(RAW, name)
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    value = produce()
    os.makedirs(RAW, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(value, f)
    os.replace(tmp, path)
    return value


def _get_logs_adaptive(topic, label, start, end, depth=0):
    """eth_getLogs over [start, end], halving the range on a size rejection.

    The endpoint enforces THREE independent limits, all discovered empirically and none
    of them documented together:
      * "block range greater than 10000 max"   -> a range cap
      * "backend response too large"           -> a RESPONSE-SIZE cap
      * "query exceeds max results 20000"      -> a RESULT-COUNT cap
    The last two bind well inside the 10000-block range cap on dense ranges, so the only
    robust strategy is to halve and retry until the request fits.
    """
    name = f"{label}_{start}_{end}.json"
    path = os.path.join(RAW, name)
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    try:
        got = rpc("eth_getLogs", [{"address": POOL_MANAGER, "topics": [topic],
                                   "fromBlock": hex(start), "toBlock": hex(end)}])
    except RuntimeError as e:
        msg = str(e)
        splittable = ("too large" in msg) or ("range greater" in msg) or ("max results" in msg)
        if splittable and end > start:
            mid = (start + end) // 2
            return (_get_logs_adaptive(topic, label, start, mid, depth + 1)
                    + _get_logs_adaptive(topic, label, mid + 1, end, depth + 1))
        raise
    os.makedirs(RAW, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(got, f)
    os.replace(tmp, path)
    return got


def fetch_logs(topic, label, from_block, to_block):
    """Paginated eth_getLogs over [from_block, to_block], cached per chunk."""
    out = []
    chunks = list(range(from_block, to_block + 1, MAX_LOG_RANGE))
    for i, start in enumerate(chunks):
        end = min(start + MAX_LOG_RANGE - 1, to_block)
        out.extend(_get_logs_adaptive(topic, label, start, end))
        print(f"\r  {label}: chunk {i + 1}/{len(chunks)}  logs so far {len(out)}", end="", flush=True)
    print()
    return out


def fetch_tx_and_base_fees(swaps, sample_size, seed=0xC0FFEE):
    """Fetch gasPrice/`to` per transaction and baseFeePerGas per block.

    Sampled rather than exhaustive: a 7-day window has ~160k swaps, and at 10 items per
    batch an exhaustive fetch would be ~32k requests. The priority-fee analysis needs a
    large sample, not the population. Sampling is at the TRANSACTION level with a fixed
    seed so the result is reproducible.
    """
    tx_hashes = sorted({s["tx"] for s in swaps})
    rng = random.Random(seed)
    if sample_size and len(tx_hashes) > sample_size:
        tx_hashes = sorted(rng.sample(tx_hashes, sample_size))

    txs = {}
    for i in range(0, len(tx_hashes), BATCH):
        chunk = tx_hashes[i:i + BATCH]
        name = f"tx_{chunk[0][:18]}_{len(chunk)}.json"
        got = _cache(name, lambda c=chunk: rpc_batch([("eth_getTransactionByHash", [h]) for h in c]))
        for h, t in zip(chunk, got):
            if t:
                txs[h] = {"gasPrice": int(t.get("gasPrice", "0x0"), 16),
                          "to": (t.get("to") or "CREATE").lower(),
                          "from": t["from"].lower(),
                          "block": int(t["blockNumber"], 16)}
        print(f"\r  txs: {min(i + BATCH, len(tx_hashes))}/{len(tx_hashes)}", end="", flush=True)
        time.sleep(0.02)
    print()

    blocks = sorted({t["block"] for t in txs.values()})
    base = {}
    for i in range(0, len(blocks), BATCH):
        chunk = blocks[i:i + BATCH]
        name = f"blk_{chunk[0]}_{len(chunk)}.json"
        got = _cache(name, lambda c=chunk: rpc_batch([("eth_getBlockByNumber", [hex(b), False]) for b in c]))
        for b, r in zip(chunk, got):
            if r:
                base[str(b)] = int(r["baseFeePerGas"], 16)
        print(f"\r  blocks: {min(i + BATCH, len(blocks))}/{len(blocks)}", end="", flush=True)
        time.sleep(0.02)
    print()
    return txs, base


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=float, default=None, help="window length in days (1 block/sec)")
    ap.add_argument("--blocks", type=int, default=None, help="window length in blocks")
    ap.add_argument("--tx-sample", type=int, default=6000, help="transactions to sample for priority fees")
    ap.add_argument("--end-block", type=int, default=None, help="pin the end block for reproducibility")
    args = ap.parse_args()

    span = args.blocks if args.blocks else int((args.days or 7) * 24 * 3600)
    end = args.end_block or rpc("eth_blockNumber", [])
    if isinstance(end, str):
        end = int(end, 16)
    start = end - span + 1

    print(f"Unichain v4 collection: blocks {start}..{end}  ({span} blocks ~ {span / 86400:.2f} days)")
    print(f"PoolManager {POOL_MANAGER}")

    swap_logs = fetch_logs(SWAP_TOPIC, "swaps", start, end)
    ml_logs = fetch_logs(MODIFY_LIQUIDITY_TOPIC, "modliq", start, end)

    swaps = [decode_swap(l) for l in swap_logs]
    mods = [decode_modify_liquidity(l) for l in ml_logs]
    swaps.sort(key=lambda s: (s["block"], s["logIndex"]))

    print(f"  decoded {len(swaps)} swaps, {len(mods)} liquidity events")
    print("Sampling transactions for priority fees...")
    txs, base = fetch_tx_and_base_fees(swaps, args.tx_sample)

    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    out = {
        "meta": {"startBlock": start, "endBlock": end, "spanBlocks": span,
                 "poolManager": POOL_MANAGER, "txSample": args.tx_sample,
                 "collectedAtUnix": int(time.time())},
        "swaps": swaps, "modifyLiquidity": mods, "txs": txs, "baseFee": base,
    }
    path = os.path.join(ROOT, "data", "unichain-dataset.json")
    with open(path, "w") as f:
        json.dump(out, f)
    print(f"wrote {path}")
    print(f"  swaps={len(swaps)}  liq={len(mods)}  sampledTxs={len(txs)}  blocksWithBaseFee={len(base)}")


if __name__ == "__main__":
    main()
