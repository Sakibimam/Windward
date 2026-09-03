import Simulator from "@/components/Simulator";
import LiveFee from "@/components/LiveFee";
import SwapPanel from "@/components/SwapPanel";

export const metadata = { title: "Live demo · Windward" };

export default function DemoPage() {
  return (
    <main>
      <header className="page-head">
        <div className="shell">
          <p className="eyebrow">Live demo</p>
          <h1 className="display page-h">
            Three ways to watch the same fee move.
          </h1>
          <p className="lede narrow">
            The arithmetic is the deployed contract&rsquo;s, the chain reads are live, and the
            trades are your own. The one invented thing on this page is the order flow in the first
            panel, and the maths running on it is not.
          </p>
        </div>
      </header>

      <section>
        <div className="shell">
          <p className="eyebrow">1 · Simulated flow</p>
          <h2 className="head">The fee moves because the market moved.</h2>
          <p className="narrow">
            This runs the deployed contract&rsquo;s arithmetic on synthetic order flow: the same
            BigInt integer maths, truncation included. Switch the market between calm and
            volatile and watch the fee follow, then leave it alone and watch it decay back toward
            the floor on its own.
          </p>
          <Simulator />
        </div>
      </section>

      <section>
        <div className="shell">
          <p className="eyebrow">2 · The deployed contract</p>
          <h2 className="head">Same hook, read live from chain.</h2>
          <p className="narrow">
            Read-only, straight from the deployed address. No wallet, no signature, no
            transaction. Just the contract&rsquo;s current state, polled every few seconds.
          </p>
          <LiveFee />
        </div>
      </section>

      <section>
        <div className="shell">
          <p className="eyebrow">3 · Your turn</p>
          <h2 className="head">Trade it yourself and move the fee.</h2>
          <p className="narrow">
            Mint yourself two throwaway test tokens, swap one for the other, and watch the hook
            reprice the next swap. One caveat worth knowing: swaps that land in the{" "}
            <em>same block</em> are ignored by design, because <code>dt == 0</code> is an identity, which
            is what closes the dust-swap suppression attack. Swap twice a few seconds apart.
          </p>
          <SwapPanel />
        </div>
      </section>
    </main>
  );
}
