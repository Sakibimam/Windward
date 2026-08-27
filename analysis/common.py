"""Shared RPC and ABI-decoding helpers for the Unichain v4 microstructure study.

Every number in the study is produced by this package. Nothing here may depend on
a scratchpad script or on hand-transcribed output.

TWO DECODING BUGS WERE FOUND IN THIS PROJECT AND BOTH LIVED HERE. They are documented
inline at their exact sites and pinned by regression tests in `test_decode.py`.
Do not "simplify" either one.
"""

import json
import subprocess

UNICHAIN_RPC = "https://mainnet.unichain.org"
POOL_MANAGER = "0x1f98400000000000000000000000000000000004"
UNIVERSAL_ROUTER = "0xef740bf23acae26f6492b10de645d6b98dc8eaf3"

# keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)")
SWAP_TOPIC = "0x40e9cecb9f5f1f1c5b9c97dec2917b7ee92e57ba5563708daca94dd84ad7112f"
# keccak256("ModifyLiquidity(bytes32,address,int24,int24,int256,bytes32)")
MODIFY_LIQUIDITY_TOPIC = "0xf208f4912782fd25c7f114ca3723a2d5dd6f3bcc3ac8db5af63baa85f711d5ec"


def rpc(method, params, url=UNICHAIN_RPC, timeout=60):
    """Single JSON-RPC call.

    Uses curl rather than urllib because this machine's Python has no CA bundle
    configured (verified: urllib raises CERTIFICATE_VERIFY_FAILED against the
    Unichain endpoint). curl works, so curl is what we use.
    """
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
    out = subprocess.run(
        ["curl", "-s", "-X", "POST", "-H", "Content-Type: application/json", "--data", payload, url],
        capture_output=True, text=True, timeout=timeout,
    )
    r = json.loads(out.stdout)
    if "error" in r:
        raise RuntimeError(f"{method}: {r['error']}")
    return r["result"]


def rpc_batch(calls, url=UNICHAIN_RPC, timeout=120):
    """Batched JSON-RPC. The public Unichain endpoint rejects batches over 10 items
    ("consider using a dedicated API provider"), so callers must chunk to <= 10.
    """
    assert len(calls) <= 10, "Unichain public RPC rejects batches larger than 10"
    payload = json.dumps(
        [{"jsonrpc": "2.0", "id": i, "method": m, "params": p} for i, (m, p) in enumerate(calls)]
    )
    out = subprocess.run(
        ["curl", "-s", "-X", "POST", "-H", "Content-Type: application/json", "--data", payload, url],
        capture_output=True, text=True, timeout=timeout,
    )
    r = json.loads(out.stdout)
    if isinstance(r, dict) and "error" in r:
        raise RuntimeError(f"batch: {r['error']}")
    return [item.get("result") for item in sorted(r, key=lambda x: x["id"])]


# ---------------------------------------------------------------------------
# BUG SITE 1 — signed integer decoding.
# ---------------------------------------------------------------------------
def signed(word_hex):
    """Decode one 32-byte ABI word as a signed integer.

    THE BUG (fixed 2026-08-28, commit cc58e3e, recorded as D-0017 E-2):
        An earlier version decoded int24 with a 24-bit sign convention:
            v - (1 << 24) if v >= (1 << 23) else v
        That is wrong. Solidity's ABI encoder SIGN-EXTENDS int24 across the FULL
        32-byte word, so tick -198087 arrives as 0xfff...fcfb79, not 0xfcfb79.
        The 24-bit convention decoded every negative tick as a number near 2**256.
        231 of 745 tick values (31%) were corrupted, and it went unnoticed because
        the two busiest sampled pools happened to have positive ticks.

    The correct rule is: interpret the whole word as two's-complement int256.
    This is width-agnostic and therefore correct for int24, int128 and int256 alike.
    """
    v = int(word_hex, 16)
    return v - (1 << 256) if v >= (1 << 255) else v


def decode_swap(log):
    """Decode a v4 Swap event.

    Event (verified at lib/v4-core/src/interfaces/IPoolManager.sol:91-100):
        Swap(PoolId indexed id, address indexed sender, int128 amount0, int128 amount1,
             uint160 sqrtPriceX96, uint128 liquidity, int24 tick, uint24 fee)

    BUG SITE 2 — direction convention.
        The natspec at IPoolManager.sol:85 says amount0 is "the delta of the currency0
        balance of the pool". THAT IS WRONG. PoolManager.sol:241-250 emits
        `delta.amount0()`, where `delta` is the CALLER's BalanceDelta (the same value
        passed to _accountPoolBalanceDelta for msg.sender at PoolManager.sol:226).

        So: amount0 > 0  =>  the pool owes the caller token0  =>  the caller RECEIVED
        token0  =>  the caller BOUGHT token0  =>  price of token0 goes UP.

        An earlier analysis treated amount0 > 0 as a SELL of token0, which inverted
        every direction-conditional statistic and produced a spurious "mean reversion"
        finding. Retracted as D-0017 E-1.
    """
    d = log["data"][2:]
    words = [d[i:i + 64] for i in range(0, len(d), 64)]
    return {
        "block": int(log["blockNumber"], 16),
        "logIndex": int(log["logIndex"], 16),
        "tx": log["transactionHash"].lower(),
        "pool": log["topics"][1],
        "sender": "0x" + log["topics"][2][-40:],
        "amount0": signed(words[0]),
        "amount1": signed(words[1]),
        "sqrtPriceX96": int(words[2], 16),
        "liquidity": int(words[3], 16),
        "tick": signed(words[4]),
        "fee": int(words[5], 16),
    }


def caller_bought_token0(swap):
    """True if the caller received token0, i.e. bought token0 and pushed its price up.

    This is the single place the direction convention is expressed. Everything that
    needs a direction must call this rather than re-deriving it from a sign.
    """
    return swap["amount0"] > 0


def decode_modify_liquidity(log):
    """ModifyLiquidity(PoolId indexed id, address indexed sender, int24 tickLower,
    int24 tickUpper, int256 liquidityDelta, bytes32 salt)"""
    d = log["data"][2:]
    words = [d[i:i + 64] for i in range(0, len(d), 64)]
    return {
        "block": int(log["blockNumber"], 16),
        "tx": log["transactionHash"].lower(),
        "pool": log["topics"][1],
        "sender": "0x" + log["topics"][2][-40:],
        "tickLower": signed(words[0]),
        "tickUpper": signed(words[1]),
        "liquidityDelta": signed(words[2]),
    }
