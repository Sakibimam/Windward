"use client";

import { useCallback, useEffect, useState } from "react";
import type { Address, Hex } from "viem";
import {
  client, readLive, HOOK, POOL_ID, TOKEN0, TOKEN1, SWAP_ROUTER,
  poolKey, swapConfigured, erc20Abi, swapRouterAbi, MIN_SQRT_PRICE,
} from "@/lib/chain";
import { connect, currentAccount, ensureChain, hasWallet, walletClient, short } from "@/lib/wallet";

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
  // `window.ethereum` does not exist during the static render, so wallet presence can only be
  // decided after mount. Without this a visitor WITH a wallet sees "No wallet detected".
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const refreshBalance = useCallback(async (a: Address) => {
    if (!TOKEN0) return;
    const b = await client.readContract({
      address: TOKEN0 as Address, abi: erc20Abi, functionName: "balanceOf", args: [a],
    });
    setBal(b);
  }, []);

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
    setStep("minting"); setMsg("Minting test tokens…");
    const w = walletClient(account);
    for (const t of [TOKEN0, TOKEN1] as Address[]) {
      const h = await w.writeContract({
        address: t, abi: erc20Abi, functionName: "mint",
        args: [account, MINT], chain: undefined, account,
      });
      await client.waitForTransactionReceipt({ hash: h });
    }
    setMsg("Test tokens minted.");
    await refreshBalance(account);
  });

  const onSwap = () => run(async () => {
    if (!account) return;
    const before = await readLive(POOL_ID as Hex);

    const allowance = await client.readContract({
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
      await client.waitForTransactionReceipt({ hash: h });
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
    await client.waitForTransactionReceipt({ hash });

    const after = await readLive(POOL_ID as Hex);
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

      {account && (
        <>
          <div className="swap-actions">
            <button className="btn ghost" onClick={onMint} disabled={busy}>
              {step === "minting" ? "Minting…" : "Mint test tokens"}
            </button>
            <button className="btn" onClick={onSwap} disabled={busy || bal === 0n}>
              {step === "approving" ? "Approving…" : step === "swapping" ? "Swapping…" : "Swap 200 WTA"}
            </button>
            {bal !== null && (
              <span className="mono bal">
                balance {(Number(bal / 10n ** 15n) / 1000).toLocaleString()} WTA
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
