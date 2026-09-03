"use client";

import { useCallback, useEffect, useState } from "react";
import type { Address, Hex } from "viem";
import {
  readLive, HOOK, POOL_ID, TOKEN0, TOKEN1, SWAP_ROUTER,
  poolKey, swapConfigured, erc20Abi, swapRouterAbi, MIN_SQRT_PRICE,
} from "@/lib/chain";
import {
  connect, currentAccount, ensureChain, hasWallet, walletClient, walletPublicClient, short,
} from "@/lib/wallet";

type Step = "idle" | "minting" | "approving" | "swapping";

const AMOUNT = 200n * 10n ** 18n; // large enough to move the tick on the seeded pool
const MINT = 1_000_000n * 10n ** 18n;

export default function SwapPanel() {
  const [account, setAccount] = useState<Address | null>(null);
  const [step, setStep] = useState<Step>("idle");
  const [msg, setMsg] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [fee, setFee] = useState<{ before: number; after: number } | null>(null);
  const [bal, setBal] = useState<bigint | null>(null);
  const [ethBal, setEthBal] = useState<bigint | null>(null);
  // null = not checked yet. false = the tokens are not on the wallet's chain.
  const [onRightChain, setOnRightChain] = useState<boolean | null>(null);
  // `window.ethereum` does not exist during the static render, so wallet presence can only be
  // decided after mount. Without this a visitor WITH a wallet sees "No wallet detected".
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  /**
   * The pool and its tokens live on exactly one chain. If the wallet is pointed somewhere else
   * every read returns "0x" and every write is a no-op against an empty address — the swap
   * confirms, costs gas and does nothing. One `getCode` distinguishes that from a real failure,
   * so the panel can say which network is wrong instead of throwing a decode error.
   */
  const checkChain = useCallback(async () => {
    if (!TOKEN0) return false;
    try {
      const code = await walletPublicClient().getCode({ address: TOKEN0 as Address });
      const ok = Boolean(code && code !== "0x");
      setOnRightChain(ok);
      return ok;
    } catch {
      setOnRightChain(false);
      return false;
    }
  }, []);

  const refreshBalance = useCallback(async (a: Address) => {
    if (!TOKEN0) return;
    if (!(await checkChain())) { setBal(null); setEthBal(null); return; }
    try {
      const [b, eth] = await Promise.all([
        walletPublicClient().readContract({
          address: TOKEN0 as Address, abi: erc20Abi, functionName: "balanceOf", args: [a],
        }),
        walletPublicClient().getBalance({ address: a }),
      ]);
      setBal(b);
      setEthBal(eth);
    } catch {
      setBal(null);
      setEthBal(null);
    }
  }, [checkChain]);

  const assertDeployed = useCallback(async () => {
    if (!(await checkChain())) {
      throw new Error(
        "The test tokens are not deployed on the network your wallet is connected to.",
      );
    }
  }, [checkChain]);

  useEffect(() => {
    currentAccount().then((a) => {
      if (a) { setAccount(a); refreshBalance(a); }
    }).catch(() => {});
  }, [refreshBalance]);

  const run = async (fn: () => Promise<void>) => {
    setErr(null);
    try { await fn(); } catch (e) {
      const m = e instanceof Error ? e.message : String(e);
      setErr(m.split("\n")[0].slice(0, 180));
    } finally { setStep("idle"); }
  };

  const onConnect = () => run(async () => {
    const a = await connect();
    await ensureChain();
    setAccount(a);
    await refreshBalance(a);
  });

  const onMint = () => run(async () => {
    if (!account) return;
    await assertDeployed();
    setStep("minting"); setMsg("Minting test tokens…");
    const w = walletClient(account);
    for (const t of [TOKEN0, TOKEN1] as Address[]) {
      const h = await w.writeContract({
        address: t, abi: erc20Abi, functionName: "mint",
        args: [account, MINT], chain: undefined, account,
      });
      await walletPublicClient().waitForTransactionReceipt({ hash: h });
    }
    setMsg("Test tokens minted.");
    await refreshBalance(account);
  });

  const onSwap = () => run(async () => {
    if (!account) return;
    await assertDeployed();
    const wpc = walletPublicClient();
    const before = await readLive(POOL_ID as Hex, wpc);

    const allowance = await wpc.readContract({
      address: TOKEN0 as Address, abi: erc20Abi, functionName: "allowance",
      args: [account, SWAP_ROUTER],
    });
    const w = walletClient(account);

    if (allowance < AMOUNT) {
      setStep("approving"); setMsg("Approving the router…");
      const h = await w.writeContract({
        address: TOKEN0 as Address, abi: erc20Abi, functionName: "approve",
        args: [SWAP_ROUTER, 2n ** 255n], chain: undefined, account,
      });
      await walletPublicClient().waitForTransactionReceipt({ hash: h });
    }

    setStep("swapping"); setMsg("Swapping…");
    const hash = await w.writeContract({
      address: SWAP_ROUTER, abi: swapRouterAbi, functionName: "swap",
      args: [
        poolKey(),
        { zeroForOne: true, amountSpecified: -AMOUNT, sqrtPriceLimitX96: MIN_SQRT_PRICE + 1n },
        { takeClaims: false, settleUsingBurn: false },
        "0x",
      ],
      chain: undefined, account,
    });
    await walletPublicClient().waitForTransactionReceipt({ hash });

    const after = await readLive(POOL_ID as Hex, wpc);
    setFee({ before: before.fee, after: after.fee });
    setMsg(
      after.fee === before.fee
        ? "Swap landed, fee unchanged — it probably shared a block with the last one (dt = 0, ignored by design). Wait a few seconds and swap again."
        : "Swap landed. The fee moved.",
    );
    await refreshBalance(account);
  });

  if (!swapConfigured()) {
    return (
      <div className="live idle">
        <p className="mono">
          Trading is not configured. Run <code>script/SeedPool.s.sol</code>, then set{" "}
          <code>NEXT_PUBLIC_TOKEN0</code>, <code>NEXT_PUBLIC_TOKEN1</code> and{" "}
          <code>NEXT_PUBLIC_POOL_ID</code> — see <code>web/.env.example</code>.
        </p>
      </div>
    );
  }

  const busy = step !== "idle";

  return (
    <div className="swap">
      <div className="swap-head">
        <div>
          <span className="mono lbl">Trade the live pool</span>
          <p className="swap-sub">
            Two throwaway ERC-20s on Unichain Sepolia. Mint yourself some, swap, and watch the
            hook reprice. Nothing here touches real value.
          </p>
        </div>
        {account ? (
          <span className="acct mono">{short(account)}</span>
        ) : (
          <button className="btn" onClick={onConnect} disabled={mounted && !hasWallet()}>
            {!mounted ? "Connect wallet" : hasWallet() ? "Connect wallet" : "No wallet detected"}
          </button>
        )}
      </div>

      {account && onRightChain === false && (
        <div className="swap-warn">
          <p>
            <strong>Wrong network for this pool.</strong> The test tokens have no code at{" "}
            <code>{short(TOKEN0 as string)}</code> on the chain your wallet is connected to, so a
            swap here would confirm, cost gas and do nothing.
          </p>
          <p className="mono">
            Seed the pool on that network:{" "}
            <code>forge script script/SeedPool.s.sol:SeedPool --rpc-url &lt;rpc&gt; --broadcast</code>
            {" "}— then put the printed addresses in <code>web/.env.local</code>.
          </p>
        </div>
      )}

      {account && ethBal === 0n && (
        <div className="swap-warn" style={{ marginBottom: "1rem" }}>
          <p>
            <strong>Unichain Sepolia Testnet Gas Required:</strong> Minting tokens and swapping are free, but the testnet sequencer requires a tiny fraction of testnet ETH for transaction gas.
          </p>
          <p style={{ marginTop: "0.5rem" }}>
            Get free testnet ETH:{" "}
            <a href="https://faucet.ethglobal.com/" target="_blank" rel="noreferrer" style={{ textDecoration: "underline" }}>
              ETHGlobal Faucet
            </a>{" "}
            ·{" "}
            <a href="https://thirdweb.com/unichain-sepolia-testnet/" target="_blank" rel="noreferrer" style={{ textDecoration: "underline" }}>
              Thirdweb Faucet
            </a>{" "}
            ·{" "}
            <a href="https://superbridge.app/unichain-sepolia" target="_blank" rel="noreferrer" style={{ textDecoration: "underline" }}>
              Superbridge (Bridge Sepolia ETH)
            </a>
          </p>
        </div>
      )}

      {account && (
        <>
          <div className="swap-actions">
            <button className="btn ghost" onClick={onMint} disabled={busy || onRightChain === false}>
              {step === "minting" ? "Minting…" : "Mint test tokens"}
            </button>
            <button className="btn" onClick={onSwap} disabled={busy || bal === 0n || onRightChain === false}>
              {step === "approving" ? "Approving…" : step === "swapping" ? "Swapping…" : "Swap 200 WTA"}
            </button>
            {bal !== null && (
              <span className="mono bal">
                {(Number(bal / 10n ** 15n) / 1000).toLocaleString()} WTA
                {ethBal !== null && ` · ${(Number(ethBal / 10n ** 14n) / 10000).toFixed(4)} test ETH`}
              </span>
            )}
          </div>

          {fee && (
            <div className="swap-result">
              <div><span className="mono lbl">Fee before</span><b className="tnum alt">{fee.before}</b></div>
              <span className="arrow" aria-hidden="true">→</span>
              <div><span className="mono lbl">Fee after</span><b className="tnum">{fee.after}</b></div>
              <span className="mono delta">
                {fee.after === fee.before ? "no change" : `${fee.after > fee.before ? "+" : ""}${fee.after - fee.before} pips`}
              </span>
            </div>
          )}
        </>
      )}

      {msg && !err && <p className="mono swap-msg">{msg}</p>}
      {err && <p className="mono swap-err">{err}</p>}
      <p className="mono swap-foot">
        Router <code>{short(SWAP_ROUTER)}</code> · hook <code>{short(HOOK)}</code>. v4 requires a
        router: swaps go through <code>unlockCallback</code>, never straight to the PoolManager.
      </p>
    </div>
  );
}
