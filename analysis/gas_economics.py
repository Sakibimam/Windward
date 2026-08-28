"""Gas cost in dollars, and the swap size at which the hook's extra fee revenue
covers the extra gas it burns.

    python3 analysis/gas_economics.py

Method — what is on-chain and what is derived:
  * gas price     ON-CHAIN, eth_gasPrice against Unichain mainnet.
  * gas overhead  MEASURED, read from data/gas_overhead.json, which is written by
                  test/WindwardGas.t.sol. Never hardcoded here.
  * pool identity ON-CHAIN and reproducible. The busiest pools use hooks, so their
                  PoolId cannot be reconstructed from a guessed PoolKey. We take one
                  single-swap transaction per pool, pull its receipt, and read the ERC-20
                  Transfer log addresses. That yields the token PAIR without a subgraph
                  or any trusted list.
  * leg order     inferred from the DATA, not from sorting those addresses. Sorting is
                  unreliable here: v4 uses address(0) for NATIVE ETH, which sorts before
                  every ERC-20, and a router that wraps ETH emits a WETH Transfer that
                  looks like a pool currency but is not. Pool 0x3258f4.. is exactly this
                  case - it is native-ETH/USDC, and address-sorting mislabelled it as
                  USDC/WETH, which inflated its median swap size to $50bn and produced a
                  nonsensical ETH price. We instead infer which leg carries 6 decimals
                  from the median magnitude of each leg, which is self-validating.
  * ETH/USD       ON-CHAIN, from the live sqrtPriceX96 of the identified USDC/WETH pool.
                  No external price API.
  * swap sizes    from data/unichain-dataset.json (426,807 swaps), using the
                  6-decimal stablecoin leg as the USD notional.

WHO PAYS WHAT — stated up front, because the comparison mixes parties.
  The GAS is paid by the SWAPPER. The extra FEE REVENUE accrues to the LP. "Breakeven"
  below is a SYSTEM-level question — does the extra fee revenue exceed the extra gas
  burned? — not a claim that any party is made whole. A swapper is strictly worse off
  under the hook: they pay both the gas and the higher fee.
"""

import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import UNICHAIN_RPC, rpc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
STATEVIEW = "0x86e8631a016f9068c3f085faf484ee3f5fdee8f2"

def _load_gas_overhead():
    """Read the overhead MEASURED by test/WindwardGas.t.sol.

    It used to be hardcoded here with a comment pointing at the test. That is exactly the
    hand-transcription that caused D-0009/D-0017: the test asserted only a loose upper
    bound, so a change to the hook could move the real number while this constant silently
    kept the old one. The test now asserts a tight range AND writes its measurement to
    data/gas_overhead.json; this reads it and refuses to invent a fallback.
    """
    path = os.path.join(ROOT, "data", "gas_overhead.json")
    if not os.path.exists(path):
        raise SystemExit(
            "data/gas_overhead.json is missing. Run:\n"
            "    forge test --match-path test/WindwardGas.t.sol\n"
            "This file refuses to guess the gas overhead."
        )
    with open(path) as f:
        return json.load(f)


GAS = _load_gas_overhead()
GAS_OVERHEAD = GAS["gasOverhead"]
STATIC_FEE_PIPS = 500      # baseline for comparison
PIPS = 1_000_000
STABLES = {"USDC", "USD₮0", "USDT", "DAI"}


def cast(args):
    out = subprocess.run(["cast"] + args, capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip())
    return out.stdout.strip()


def token_meta(addr, cache):
    if addr not in cache:
        sym = cast(["call", addr, "symbol()(string)", "--rpc-url", UNICHAIN_RPC]).strip('"')
        dec = int(cast(["call", addr, "decimals()(uint8)", "--rpc-url", UNICHAIN_RPC]))
        cache[addr] = (sym, dec)
    return cache[addr]


def identify_pools(data, top_n=5):
    """Recover each top pool's token pair from Transfer logs in a single-swap tx."""
    import collections
    cnt = collections.Counter(s["pool"] for s in data["swaps"])
    by_tx = collections.defaultdict(list)
    for s in data["swaps"]:
        by_tx[s["tx"]].append(s)

    cache, out = {}, []
    for pool, n in cnt.most_common(top_n):
        tx = next((t for t, ss in by_tx.items() if len(ss) == 1 and ss[0]["pool"] == pool), None)
        if not tx:
            continue
        try:
            rec = rpc("eth_getTransactionReceipt", [tx])
        except Exception:
            continue
        toks = []
        for lg in rec["logs"]:
            if lg["topics"] and lg["topics"][0].lower() == TRANSFER_TOPIC:
                a = lg["address"].lower()
                if a not in toks:
                    toks.append(a)
        if len(toks) < 2:
            continue
        pair = sorted(toks[:2], key=lambda a: int(a, 16))  # currency0 < currency1
        meta = [token_meta(a, cache) for a in pair]
        out.append({"pool": pool, "swaps": n,
                    "currency0": pair[0], "symbol0": meta[0][0], "decimals0": meta[0][1],
                    "currency1": pair[1], "symbol1": meta[1][0], "decimals1": meta[1][1]})
    return out


def infer_legs(data, pool):
    """Return (median|a0|, median|a1|) so callers can infer decimals from magnitude."""
    a0 = sorted(abs(s["amount0"]) for s in data["swaps"] if s["pool"] == pool and s["amount0"])
    a1 = sorted(abs(s["amount1"]) for s in data["swaps"] if s["pool"] == pool and s["amount1"])
    return (a0[len(a0) // 2] if a0 else 0, a1[len(a1) // 2] if a1 else 0)


def usd_sizes(data, p):
    """USD notional per swap from the 6-decimal stablecoin leg.

    Which leg that is comes from the data, not from address ordering. A 6-decimal leg
    carrying $0.01-$10M has a median magnitude of 1e4-1e13; an 18-decimal leg is 1e14+.
    If neither leg looks like a stablecoin, return None rather than guess.
    """
    if not ({p["symbol0"], p["symbol1"]} & STABLES):
        return None
    m0, m1 = infer_legs(data, p["pool"])
    plausible = lambda m: 1e3 < m < 1e14  # noqa: E731
    if plausible(m0) and not plausible(m1):
        leg = "amount0"
    elif plausible(m1) and not plausible(m0):
        leg = "amount1"
    elif m0 and m1:
        leg = "amount0" if m0 < m1 else "amount1"  # the 6dp leg is the smaller one
    else:
        return None
    return sorted(abs(s[leg]) / 10**6 for s in data["swaps"] if s["pool"] == p["pool"] and s[leg])


def main():
    print("=" * 78)
    print("GAS ECONOMICS — what 11,192 gas costs, and the swap size at which it pays for itself")
    print("=" * 78)

    gas_price = int(cast(["gas-price", "--rpc-url", UNICHAIN_RPC]))
    print("\n[on-chain] eth_gasPrice : {:,} wei ({:.6f} gwei)".format(gas_price, gas_price / 1e9))

    with open(os.path.join(ROOT, "data", "unichain-dataset.json")) as f:
        data = json.load(f)
    with open(os.path.join(ROOT, "data", "stats.json")) as f:
        stats = json.load(f)

    pools = identify_pools(data)
    print("\n[on-chain] pool identities, recovered from Transfer logs:")
    for p in pools:
        print(f"   {p['pool'][:18]}..  n={p['swaps']:>7,}  "
              f"{p['symbol0']}({p['decimals0']}dp) / {p['symbol1']}({p['decimals1']}dp)")

    # ETH/USD from the identified USDC/WETH pool's live price
    ethusd = None
    for p in pools:
        if {p["symbol0"], p["symbol1"]} == {"USDC", "WETH"}:
            sp = int(rpc("eth_call", [{"to": STATEVIEW, "data": "0xc815641c" + p["pool"][2:]}, "latest"])[2:66], 16)
            raw = (sp / 2**96) ** 2  # token1_raw per token0_raw
            m0, m1 = infer_legs(data, p["pool"])
            # The 18-decimal (ETH) leg is the one with the large median magnitude.
            eth_is_currency0 = m0 > m1
            # currency0 = ETH(18dp), currency1 = USDC(6dp): USDC per ETH = raw * 1e18 / 1e6
            # currency0 = USDC(6dp), currency1 = ETH(18dp): USDC per ETH = 1e6 / (raw * 1e-18) inverted
            ethusd = raw * 10**12 if eth_is_currency0 else (1 / raw) / 10**12
            print(f"\n[on-chain] ETH/USD from {p['pool'][:14]}.. : ${ethusd:,.2f}"
                  f"   (ETH is currency{'0' if eth_is_currency0 else '1'}, inferred from leg magnitude)")
            if not (100 < ethusd < 100_000):
                print("   REJECTED as implausible - refusing to report a USD figure derived from it.")
                ethusd = None
            break
    if ethusd is None:
        print("\nNo USDC/WETH pool identified; cannot derive ETH/USD on-chain. Aborting rather than guessing.")
        return

    gas_eth = GAS_OVERHEAD * gas_price / 1e18
    gas_usd = gas_eth * ethusd
    print(f"\nWindward gas overhead   : {GAS_OVERHEAD:,} gas "
          f"({GAS['overheadPctOfUnhooked']}% of the harness's {GAS['unhookedSwapGas']:,}-gas unhooked swap)")
    print(f"  source                : data/gas_overhead.json, written by test/WindwardGas.t.sol")
    print(f"  = {gas_eth:.12f} ETH  =  ${gas_usd:.8f} per swap")

    replay = {w["pool"]: w["repaired"] for w in stats["windwardReplay"]}
    print(f"\n{'pool':<20}{'pair':<15}{'median $':>11}"
          f"{'p10 fee':>9}{'be(p10) $':>11}{'above':>8}"
          f"{'med fee':>9}{'be(med) $':>11}{'above':>8}")
    rows = []
    for p in pools:
        sizes = usd_sizes(data, p)
        rep = replay.get(p["pool"])
        if not sizes or not rep:
            continue
        med = sizes[len(sizes) // 2]
        # CONSERVATIVE: the p10 fee, i.e. the fee on the calmest decile of swaps. The
        # median-fee breakeven flatters the result, because the breakeven is compared
        # against the FULL distribution of swap sizes, not just the median-fee ones.
        d_p10 = rep["feeP10"] - STATIC_FEE_PIPS
        d_med = rep["feeMedian"] - STATIC_FEE_PIPS
        if d_p10 <= 0 or d_med <= 0:
            print(f"{p['pool'][:18]:<20}{p['symbol0'] + '/' + p['symbol1']:<15}"
                  f"{med:>11,.2f}   charges no more than static at this percentile")
            continue
        be_p10 = gas_usd / (d_p10 / PIPS)
        be_med = gas_usd / (d_med / PIPS)
        ab_p10 = sum(1 for x in sizes if x > be_p10) / len(sizes)
        ab_med = sum(1 for x in sizes if x > be_med) / len(sizes)
        rows.append({"pool": p["pool"], "pair": f"{p['symbol0']}/{p['symbol1']}",
                     "medianSwapUsd": med, "n": len(sizes),
                     "feeP10Pips": rep["feeP10"], "deltaP10Pips": d_p10,
                     "breakevenP10Usd": be_p10, "shareAboveBreakevenP10": ab_p10,
                     "feeMedianPips": rep["feeMedian"], "deltaMedianPips": d_med,
                     "breakevenMedianUsd": be_med, "shareAboveBreakevenMedian": ab_med})
        print(f"{p['pool'][:18]:<20}{p['symbol0'] + '/' + p['symbol1']:<15}"
              f"{med:>11,.2f}{rep['feeP10']:>9}{be_p10:>11,.4f}{ab_p10:>7.1%}"
              f"{rep['feeMedian']:>9}{be_med:>11,.4f}{ab_med:>7.1%}")

    if rows:
        worst = max(rows, key=lambda r: r["breakevenP10Usd"])
        print("\nInterpretation — CONSERVATIVE (p10 fee) leads:")
        print(f"  Highest p10 breakeven across identified pools: ${worst['breakevenP10Usd']:,.2f}"
              f"  ({worst['pair']}).")
        print(f"  Share of real swaps above it: "
              f"{min(r['shareAboveBreakevenP10'] for r in rows):.1%} to "
              f"{max(r['shareAboveBreakevenP10'] for r in rows):.1%}.")
        best = max(rows, key=lambda r: r["breakevenMedianUsd"])
        print(f"  Optimistic (median fee) equivalent: ${best['breakevenMedianUsd']:,.2f}, "
              f"{min(r['shareAboveBreakevenMedian'] for r in rows):.1%}-"
              f"{max(r['shareAboveBreakevenMedian'] for r in rows):.1%} above.")
        print("\n  The swapper pays the gas AND the higher fee. System-level comparison only.")

    out = {"gasPriceWei": gas_price, "gasOverhead": GAS_OVERHEAD,
           "overheadPctOfUnhooked": GAS["overheadPctOfUnhooked"],
           "unhookedSwapGas": GAS["unhookedSwapGas"], "ethUsd": round(ethusd, 2),
           "gasCostUsd": gas_usd, "staticFeePips": STATIC_FEE_PIPS, "pools": rows}
    with open(os.path.join(ROOT, "data", "gas_economics.json"), "w") as f:
        json.dump(out, f, indent=2)
    print("\nwrote data/gas_economics.json")


if __name__ == "__main__":
    main()
