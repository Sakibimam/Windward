"""Regression tests for the two decoding bugs found in this project.

These exist so those specific errors can never silently return. Run with:
    python3 analysis/test_decode.py
Exits non-zero on failure, so it can gate the pipeline.

D-0017 E-2: int24 sign extension. Negative ticks decoded as ~2**256.
D-0017 E-1: Swap event direction convention. amount0 > 0 is a BUY, not a sell.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import signed, decode_swap, caller_bought_token0  # noqa: E402

FAILURES = []


def check(name, got, want):
    if got == want:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name}\n         got  {got}\n         want {want}")
        FAILURES.append(name)


def enc_int(v):
    """Encode a signed integer the way Solidity's ABI encoder does: sign-extended
    across a full 32-byte word."""
    return format(v & ((1 << 256) - 1), "064x")


print("=== D-0017 E-2: int24 sign extension ===")

# The exact value that exposed the bug: a real tick from Unichain pool 0x3258f4...
check("tick -198087 round-trips", signed(enc_int(-198087)), -198087)
check("tick -264921 round-trips", signed(enc_int(-264921)), -264921)
check("tick +22303 round-trips", signed(enc_int(22303)), 22303)
check("tick 0 round-trips", signed(enc_int(0)), 0)
check("int24 min round-trips", signed(enc_int(-8388608)), -8388608)
check("int24 max round-trips", signed(enc_int(8388607)), 8388607)

# The specific corruption: the OLD 24-bit convention on a sign-extended word.
_word = enc_int(-198087)
_buggy = int(_word, 16)
_buggy = _buggy - (1 << 24) if _buggy >= (1 << 23) else _buggy
check("the old 24-bit decode really was broken (sanity)", _buggy > 10**70, True)
check("and the fix does not reproduce it", signed(_word) < 0 and abs(signed(_word)) < 10**7, True)

# int128 amounts must use the same rule.
check("amount -1234567890123456789 round-trips", signed(enc_int(-1234567890123456789)), -1234567890123456789)
check("int256 min round-trips", signed(enc_int(-(1 << 255))), -(1 << 255))

print()
print("=== D-0017 E-1: Swap direction convention ===")


def fake_swap_log(amount0, amount1, tick):
    return {
        "blockNumber": "0x1",
        "logIndex": "0x0",
        "transactionHash": "0x" + "11" * 32,
        "topics": ["0x" + "00" * 32, "0x" + "aa" * 32, "0x" + "00" * 12 + "bb" * 20],
        "data": "0x" + enc_int(amount0) + enc_int(amount1) + enc_int(2**96)
                + enc_int(10**18) + enc_int(tick) + enc_int(3000),
    }


# amount0 > 0 => pool owes the caller token0 => caller RECEIVED token0 => BUY of token0.
# PoolManager.sol:241-250 emits delta.amount0(), the caller's delta. The natspec at
# IPoolManager.sol:85 ("delta of the ... balance of the pool") is misleading.
s_buy = decode_swap(fake_swap_log(amount0=+1000, amount1=-1000, tick=5))
check("amount0 > 0 is classified as a BUY of token0", caller_bought_token0(s_buy), True)

s_sell = decode_swap(fake_swap_log(amount0=-1000, amount1=+1000, tick=-5))
check("amount0 < 0 is classified as a SELL of token0", caller_bought_token0(s_sell), False)

# A buy and a sell must never classify the same way. This is the assertion that would
# have caught the inverted convention.
check("buy and sell are distinguishable", caller_bought_token0(s_buy) != caller_bought_token0(s_sell), True)

# Negative tick must survive decode_swap, not just signed().
s_neg = decode_swap(fake_swap_log(amount0=-1, amount1=1, tick=-198087))
check("decode_swap preserves a negative tick", s_neg["tick"], -198087)
check("decode_swap preserves a negative amount0", s_neg["amount0"], -1)

print()
if FAILURES:
    print(f"FAILED: {len(FAILURES)} check(s): {FAILURES}")
    sys.exit(1)
print("All decode regression tests passed.")
