import LiftSection from "@/components/LiftSection";
import Link from "next/link";
import {
  micro, swapWeighted, gas, gasEcon, liftRange, nullLiftRange, breakeven, shareAbove, fmt,
  staleLift, staleNull, retailTip, arbTip, arbN, tipRatio, pctArbBelowRetail, pctFirstOfBlock,
} from "@/lib/data";
import { DEPLOYED } from "@/lib/volatility";

const r2 = ([a, b]: readonly [number, number], d = 2) => `${a.toFixed(d)}–${b.toFixed(d)}`;

export default function Page() {
  return (
    <main>
      {/* ---------------------------------------------------------------- hero */}
      <header className="hero">
        <div className="shell">
          <p className="eyebrow">Uniswap v4 · UHI10 Hookathon</p>
          <h1 className="display hero-h">
            Two signals the field prices MEV with.<br />
            On Unichain, both are <em>inverted</em>.
          </h1>
          <p className="lede narrow">
            We measured them on {fmt(micro.swaps)} real Unichain swaps. Then we measured a third,
            against a null built to kill it — and that one survived. Windward is the v4 hook that
            prices the survivor.
          </p>

          <div className="findings">
            <div className="finding bad">
              <span className="mono tag">Inverted</span>
              <h3>Priority fee</h3>
              <p>
                Taxing a searcher&rsquo;s tip assumes a contested auction. On Unichain{" "}
                {pctFirstOfBlock}% of swaps are already first for their pool in their block.
                Retail tips a median {fmt(retailTip)} wei; the arbitrage proxy tips{" "}
                {fmt(arbTip)} wei, and {pctArbBelowRetail}% of it pays below the median retail
                swap ({tipRatio}×, n={arbN}). The tax would land on retail.
              </p>
            </div>
            <div className="finding bad">
              <span className="mono tag">Inverted</span>
              <h3>Price staleness</h3>
              <p>
                An idle pool is meant to accumulate divergence for the next arbitrageur. Bucketed
                by gap since the last trade, the longest-gap decile precedes{" "}
                <em>smaller</em> moves: {staleLift[0].toFixed(2)}–{staleLift[1].toFixed(2)}×
                against a null of {staleNull[0].toFixed(2)}–{staleNull[1].toFixed(2)}×. Idle
                means calm, not stale.
              </p>
            </div>
            <div className="finding good">
              <span className="mono tag">Survived</span>
              <h3>Realised variance</h3>
              <p>
                The pool&rsquo;s own tick history. Top fee decile precedes moves{" "}
                {liftRange[0].toFixed(2)}–{liftRange[1].toFixed(2)}× larger than the bottom,
                against a null of {nullLiftRange[0].toFixed(2)}–{nullLiftRange[1].toFixed(2)}×.
                Same test, opposite outcome.
              </p>
            </div>
          </div>

          <div className="hero-actions">
            <Link href="/demo" className="btn">Open the live demo</Link>
            <a
              className="btn ghost"
              href="https://github.com/Sakibimam/Windward"
              target="_blank"
              rel="noreferrer"
            >
              Read the code
            </a>
          </div>

          <div className="facts">
            <div><b className="tnum">{fmt(micro.swaps)}</b><span className="mono">swaps analysed</span></div>
            <div><b className="tnum">{micro.spanDays.toFixed(0)} days</b><span className="mono">of Unichain v4</span></div>
            <div><b className="tnum">{fmt(swapWeighted.swaps)}</b><span className="mono">swaps replayed</span></div>
            <div><b className="tnum">{fmt(gas.gasOverhead)}</b><span className="mono">gas per swap</span></div>
          </div>
        </div>
      </header>

      {/* -------------------------------------------------------------- who for */}
      <section>
        <div className="shell">
          <p className="eyebrow">Who this is for</p>
          <h2 className="head">It prices movement, not motive.</h2>
          <p className="narrow">
            Windward cannot read intent and does not try to. A large honest buy and the first leg
            of a pump produce the same tick move, and the hook charges the same for both. What it
            does is make <em>whatever trades next after a violent move</em> pay more — which
            matters most where violent moves are the norm and the flow around them is predatory.
          </p>
          <div className="cards">
            <div className="card">
              <h3>Token launches</h3>
              <p>
                A large buy walks the price; every swap that follows — including the dump leg — is
                repriced upward until the pool settles. The round trip costs more the more it
                disrupted.
              </p>
            </div>
            <div className="card">
              <h3>Pumps and dumps</h3>
              <p>
                Same mechanism, same asymmetry. The calm pool stays cheap, the violent one gets
                expensive, and nobody has to be identified for it to work.
              </p>
            </div>
            <div className="card">
              <h3>Ordinary flow</h3>
              <p>
                A quiet pool sits at its floor, so retail in a calm market pays the base fee. The
                bottom fee decile precedes the smallest moves — that half is measured directly.
              </p>
            </div>
            <div className="card">
              <h3>What is not claimed</h3>
              <p>
                That it detects malicious <em>intent</em> — no signal here separates a legitimate
                large trade from a hostile one. And that LPs end up better off. Both remain
                unproven.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* ------------------------------------------------------------------ cta */}
      <section className="cta-band">
        <div className="shell">
          <h2 className="head">Watch it price a market.</h2>
          <p className="narrow">
            A live simulator, the deployed contract read straight off chain, and a pool you can
            trade yourself.
          </p>
          <Link href="/demo" className="btn big">Open the live demo</Link>
        </div>
      </section>

      {/* --------------------------------------------------------- how it works */}
      <section>
        <div className="shell">
          <p className="eyebrow">How it works</p>
          <h2 className="head">Four steps, entirely inside the pool.</h2>
          <p className="narrow">
            Windward never leaves the contract. It reads what v4 already records, folds it into a
            decaying estimate, and prices the next swap from it — no oracle, no external call, no
            keeper, nothing to trust but the pool&rsquo;s own history.
          </p>
          <div className="steps">
            <div className="step">
              <h3>Read the tick the protocol wrote</h3>
              <p>
                After every swap, <code>afterSwap</code> reads the pool&rsquo;s new tick straight
                from the <code>PoolManager</code>. The observation is written by v4 itself, so a
                caller cannot forge it.
              </p>
            </div>
            <div className="step">
              <h3>Fold it into a decaying variance</h3>
              <p>
                The squared tick move, divided by elapsed time, enters an EWMA whose weight halves
                every 300 seconds. WAD scaling is carried <em>through</em> the division — doing it
                the other way round is the bug the study found.
              </p>
            </div>
            <div className="step">
              <h3>Price the next swap from it</h3>
              <p>
                <code>beforeSwap</code> decays the stored estimate forward to now, takes its square
                root, scales it, adds a floor and clamps to a ceiling — then hands v4 that fee with
                the override flag, for that swap only.
              </p>
            </div>
            <div className="step">
              <h3>Let quiet pools fall back on their own</h3>
              <p>
                Because the decay is applied on read, elapsed time alone lowers the fee. A pool
                driven to the 1% ceiling returns to its floor without anybody having to trade it.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* -------------------------------------------------------------- result */}
      <section>
        <div className="shell">
          <p className="eyebrow">The result, on real flow</p>
          <h2 className="head">When Windward charges more, more actually happens next.</h2>
          <p className="narrow">
            Bucket every swap by the fee it was charged, then measure the tick move that{" "}
            <em>followed</em> it. If the fee carries information, its top decile should precede
            larger moves than its bottom decile. <strong className="sig">It does</strong> — in
            every one of the five busiest pools on Unichain.
          </p>
          <LiftSection />
          <p className="narrow" style={{ marginTop: 28 }}>
            <strong>The control.</strong> Shuffle each pool&rsquo;s real{" "}
            <code>(tick move, block gap)</code> pairs into a random order. Same multiset, same
            heavy tail, same median, same maximum — only the <em>clustering</em> is destroyed. Both
            charts share one axis. Across all five pools: real{" "}
            <strong className="sig">{r2(liftRange)}×</strong>, shuffled{" "}
            <strong>{r2(nullLiftRange)}×</strong>.
          </p>
        </div>
      </section>

      {/* --------------------------------------------------------- engineering */}
      <section>
        <div className="shell">
          <p className="eyebrow">Engineering</p>
          <h2 className="head">Small enough to reason about. Verified, not asserted.</h2>
          <div className="cards">
            <div className="card">
              <h3>It cannot move funds</h3>
              <p>
                Both callbacks return zero deltas and all four <code>*_RETURNS_DELTA</code> address
                bits are clear, so v4 never parses a delta from it. No owner, pause, upgrade path
                or setter — every parameter is immutable.
              </p>
            </div>
            <div className="card">
              <h3>Deployed, bytecode verified</h3>
              <p className="addr mono">{DEPLOYED.address}</p>
              <p>
                Unichain Sepolia, block {fmt(DEPLOYED.block)}. Runtime code matched against a local
                deploy-profile build; the only differences are the immutable slots, each confirmed
                through its getter.
              </p>
            </div>
            <div className="card">
              <h3>61 tests, two profiles</h3>
              <p>
                Eight security findings fixed, each pinned by a regression test written while it
                still failed. One remains open and documented rather than quietly dropped.
              </p>
            </div>
            <div className="card">
              <h3>{(gasEcon.gasCostUsd * 100).toFixed(4)}¢ per swap</h3>
              <p>
                {fmt(gas.gasOverhead)} gas, {gas.overheadPctOfUnhooked}% of an unhooked swap.
                Breakeven lands near <strong>${breakeven.toFixed(2)}</strong> a trade, which{" "}
                {shareAbove.toFixed(1)}%+ of real swaps clear.
              </p>
            </div>
          </div>
        </div>
      </section>

    </main>
  );
}
