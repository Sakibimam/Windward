# docs/GAS.md — does Windward pay for its own gas?

Extracted from the README. **Nothing here is abridged.** Figures come from
`data/gas_overhead.json` (written by `test/WindwardGas.t.sol`) and `data/gas_economics.json`
(written by `analysis/gas_economics.py`).

## The answer

**Short answer: yes, and it is not close enough to be interesting.** Overhead is **12,221 gas per
swap** (17% of the harness's 71,259-gas unhooked swap), which at Unichain's
0.0015 gwei is **$0.000046**. A swap must clear about **$0.81** before the LP's
extra fee income exceeds the extra gas the swapper burns, and **98.1–99.8%** of real swaps do.

That headline uses the **conservative p10 fee** — the fee charged on the calmest decile of swaps.
On the optimistic median-fee basis the breakeven is $0.33 and 99.0–99.9% clear it: the
breakeven more than doubles while the percentages barely move, which is why the gas question is
not where the risk in this design lives.

| pool | pair | median swap | breakeven (p10 fee) | % of swaps above |
|---|---|---|---|---|
| `0xc4f393…` | USDC/HYPE | $113.62 | $0.34 | 99.8% |
| `0x75b192…` | USDC/SOL | $0.92 | $0.61 | 98.9% |
| `0x3258f4…` | USDC/WETH | $124.59 | $0.81 | 98.1% |
| `0x04b7dd…` | WETH/USD₮0 | $103.04 | $0.71 | 99.0% |

**This is an accounting identity across two different parties, not a welfare result.** The swapper
pays both the gas and the higher fee, so a swapper is strictly worse off. "vs static 500" assumes
the counterfactual pool charges 500 pips — nothing in the dataset establishes these pools' actual
fees, and 500 is the hook's own `feeMin`. It also assumes the same flow still arrives at a higher
fee (Limitations #2).

The 12,221 figure is asserted to a range in `test/WindwardGas.t.sol` and written to
`data/gas_overhead.json`, which `analysis/gas_economics.py` reads — never transcribed by hand
(D-0017). It is a local Foundry harness measurement with synthetic swap sizes, not a mainnet
number. ETH/USD is a single live `sqrtPriceX96` spot read ($2,509.35 in the committed run): one
pool, one instant, no TWAP, so **every dollar figure here moves between runs** and is only as
current as `data/gas_economics.json`. Reproduce: `python3 analysis/gas_economics.py`.
