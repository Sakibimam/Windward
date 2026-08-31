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
