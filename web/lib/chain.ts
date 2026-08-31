/**
 * Live reads from the deployed hook.
 *
 * Everything here is read-only: `currentFee` and `currentSigmaWad` on the hook, and `getSlot0`
 * on v4's StateView to tell whether a pool actually exists yet. No wallet, no signing, no
 * transaction — a visitor sees real chain state without connecting anything.
 *
 * Point it at a local fork or at Unichain Sepolia with NEXT_PUBLIC_RPC_URL, and give it a pool
 * with NEXT_PUBLIC_POOL_ID. Both are baked at build time; see .env.example.
 */
import { createPublicClient, http, defineChain, type Address, type Hex } from "viem";

export const unichainSepolia = defineChain({
  id: 1301,
  name: "Unichain Sepolia",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: ["https://sepolia.unichain.org"] } },
});

/** Verified on chain — docs/DEPLOYMENT.md and docs/RECON.md §6. */
export const HOOK: Address = "0x609634584d5BD12Ba4216116528e364d385Ad0C0";
export const STATE_VIEW: Address = "0xc199F1072a74D4e905ABa1A84d9a45E2546B6222";

export const RPC_URL = process.env.NEXT_PUBLIC_RPC_URL ?? "https://sepolia.unichain.org";
export const POOL_ID = (process.env.NEXT_PUBLIC_POOL_ID ?? "") as Hex | "";

export const client = createPublicClient({
  chain: unichainSepolia,
  transport: http(RPC_URL),
});

export const hookAbi = [
  {
    type: "function",
    name: "currentFee",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ type: "uint24" }],
  },
  {
    type: "function",
    name: "currentSigmaWad",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [{ type: "uint256" }],
  },
] as const;

export const stateViewAbi = [
  {
    type: "function",
    name: "getSlot0",
    stateMutability: "view",
    inputs: [{ name: "poolId", type: "bytes32" }],
    outputs: [
      { name: "sqrtPriceX96", type: "uint160" },
      { name: "tick", type: "int24" },
      { name: "protocolFee", type: "uint24" },
      { name: "lpFee", type: "uint24" },
    ],
  },
] as const;

export type Live = {
  fee: number;
  sigma: number;
  tick: number;
  block: bigint;
  initialised: boolean;
};

export async function readLive(poolId: Hex): Promise<Live> {
  const [fee, sigma, slot0, block] = await Promise.all([
    client.readContract({ address: HOOK, abi: hookAbi, functionName: "currentFee", args: [poolId] }),
    client.readContract({
      address: HOOK, abi: hookAbi, functionName: "currentSigmaWad", args: [poolId],
    }),
    client.readContract({
      address: STATE_VIEW, abi: stateViewAbi, functionName: "getSlot0", args: [poolId],
    }),
    client.getBlockNumber(),
  ]);
  return {
    fee: Number(fee),
    sigma: Number((sigma * 100n) / 10n ** 18n) / 100,
    tick: slot0[1],
    block,
    // A pool that was never initialised has a zero price.
    initialised: slot0[0] !== 0n,
  };
}

/* --------------------------------------------------------------- pool config
 * Set by `forge script script/SeedPool.s.sol:SeedPool`, which prints all three.
 * See web/.env.example.
 */
export const TOKEN0 = (process.env.NEXT_PUBLIC_TOKEN0 ?? "") as Address | "";
export const TOKEN1 = (process.env.NEXT_PUBLIC_TOKEN1 ?? "") as Address | "";
export const SWAP_ROUTER: Address =
  (process.env.NEXT_PUBLIC_SWAP_ROUTER as Address) ??
  "0x9140a78c1A137c7fF1c151EC8231272aF78a99A4";

export const TICK_SPACING = 60;
export const DYNAMIC_FEE_FLAG = 0x800000;
export const MIN_SQRT_PRICE = 4295128739n;
export const MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342n;

export const poolKey = () =>
  ({
    currency0: TOKEN0 as Address,
    currency1: TOKEN1 as Address,
    fee: DYNAMIC_FEE_FLAG,
    tickSpacing: TICK_SPACING,
    hooks: HOOK,
  }) as const;

export const swapConfigured = () => Boolean(TOKEN0 && TOKEN1 && POOL_ID);

export const erc20Abi = [
  { type: "function", name: "mint", stateMutability: "nonpayable",
    inputs: [{ name: "to", type: "address" }, { name: "value", type: "uint256" }], outputs: [] },
  { type: "function", name: "approve", stateMutability: "nonpayable",
    inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }],
    outputs: [{ type: "bool" }] },
  { type: "function", name: "balanceOf", stateMutability: "view",
    inputs: [{ name: "a", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view",
    inputs: [{ name: "o", type: "address" }, { name: "s", type: "address" }],
    outputs: [{ type: "uint256" }] },
] as const;

export const swapRouterAbi = [
  {
    type: "function",
    name: "swap",
    stateMutability: "payable",
    inputs: [
      { name: "key", type: "tuple", components: [
        { name: "currency0", type: "address" },
        { name: "currency1", type: "address" },
        { name: "fee", type: "uint24" },
        { name: "tickSpacing", type: "int24" },
        { name: "hooks", type: "address" },
      ]},
      { name: "params", type: "tuple", components: [
        { name: "zeroForOne", type: "bool" },
        { name: "amountSpecified", type: "int256" },
        { name: "sqrtPriceLimitX96", type: "uint160" },
      ]},
      { name: "testSettings", type: "tuple", components: [
        { name: "takeClaims", type: "bool" },
        { name: "settleUsingBurn", type: "bool" },
      ]},
      { name: "hookData", type: "bytes" },
    ],
    outputs: [{ type: "int256" }],
  },
] as const;
