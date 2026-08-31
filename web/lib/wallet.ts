/**
 * Wallet access with viem only — no connector library.
 *
 * Everything a visitor needs (connect, switch to Unichain Sepolia, mint test tokens, approve,
 * swap) is a handful of EIP-1193 calls, so pulling in a connector stack would be weight without
 * benefit. `window.ethereum` is read lazily so the module is safe to import during a static build.
 */
import {
  createWalletClient, custom, type Address, type Hex, type WalletClient,
} from "viem";
import { unichainSepolia } from "./chain";

export const CHAIN_ID = 1301;
export const CHAIN_ID_HEX = "0x515";

type Eip1193 = {
  request: (a: { method: string; params?: unknown[] }) => Promise<unknown>;
  on?: (e: string, h: (...a: unknown[]) => void) => void;
  removeListener?: (e: string, h: (...a: unknown[]) => void) => void;
};

export function provider(): Eip1193 | null {
  if (typeof window === "undefined") return null;
  return (window as unknown as { ethereum?: Eip1193 }).ethereum ?? null;
}

export function hasWallet() {
  return provider() !== null;
}

export function walletClient(account: Address): WalletClient {
  const p = provider();
  if (!p) throw new Error("No wallet found. Install MetaMask or another injected wallet.");
  return createWalletClient({ account, chain: unichainSepolia, transport: custom(p) });
}

export async function connect(): Promise<Address> {
  const p = provider();
  if (!p) throw new Error("No wallet found. Install MetaMask or another injected wallet.");
  const accounts = (await p.request({ method: "eth_requestAccounts" })) as Address[];
  if (!accounts?.length) throw new Error("No account authorised.");
  return accounts[0];
}

export async function currentAccount(): Promise<Address | null> {
  const p = provider();
  if (!p) return null;
  const accounts = (await p.request({ method: "eth_accounts" })) as Address[];
  return accounts?.[0] ?? null;
}

export async function chainId(): Promise<number | null> {
  const p = provider();
  if (!p) return null;
  return Number((await p.request({ method: "eth_chainId" })) as Hex);
}

/** Switch to Unichain Sepolia, adding it to the wallet if it is not there yet. */
export async function ensureChain(): Promise<void> {
  const p = provider();
  if (!p) throw new Error("No wallet found.");
  if ((await chainId()) === CHAIN_ID) return;
  try {
    await p.request({ method: "wallet_switchEthereumChain", params: [{ chainId: CHAIN_ID_HEX }] });
  } catch (e) {
    // 4902 = chain unknown to the wallet. Add it, then the switch above succeeds implicitly.
    if ((e as { code?: number })?.code === 4902) {
      await p.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId: CHAIN_ID_HEX,
          chainName: "Unichain Sepolia",
          nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
          rpcUrls: ["https://sepolia.unichain.org"],
          blockExplorerUrls: ["https://unichain-sepolia.blockscout.com"],
        }],
      });
    } else {
      throw e;
    }
  }
}

export const short = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;
