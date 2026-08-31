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
            We tested all three on {fmt(micro.swaps)} real Unichain swaps. Two of them point the
            wrong way. Windward is the v4 hook that prices the one that survived.
          </p>

          <div className="findings">
            <div className="finding bad">
              <span className="mono tag">Inverted</span>
              <h3>Priority fee</h3>
              <p>
                Taxing a searcher&rsquo;s tip assumes a contested auction. But {pctFirstOfBlock}%
                of swaps are already first for their pool in their block, and the arbitrage proxy
                tips <em>below</em> median retail {pctArbBelowRetail}% of the time. The tax would
                land on retail.
              </p>
            </div>
            <div className="finding bad">
              <span className="mono tag">Inverted</span>
              <h3>Price staleness</h3>
              <p>
                An idle pool is meant to accumulate divergence for the next arbitrageur. Instead
                the longest-gap decile precedes <em>smaller</em> moves —{" "}
                {r2(staleLift)}× against a null of {r2(staleNull)}×. Idle means calm, not stale.
              </p>
            </div>
            <div className="finding good">
              <span className="mono tag">Survived</span>
              <h3>Realised variance</h3>
              <p>
                The pool&rsquo;s own tick history. The top fee decile precedes moves{" "}
                {r2(liftRange)}× larger than the bottom, against a null of {r2(nullLiftRange)}×.
                Same test, opposite outcome.
              </p>
            </div>
          </div>

          <div className="hero-actions">
            <Link href="/demo" className="btn">Open the live demo</Link>
            <Link href="/docs" className="btn ghost">Read the docs</Link>
          </div>

          <div className="facts">
            <div><b className="tnum">{fmt(micro.swaps)}</b><span className="mono">swaps analysed</span></div>
            <div><b className="tnum">{micro.spanDays.toFixed(0)} days</b><span className="mono">of Unichain v4</span></div>
            <div><b className="tnum">{fmt(swapWeighted.swaps)}</b><span className="mono">swaps replayed</span></div>
            <div><b className="tnum">{fmt(gas.gasOverhead)}</b><span className="mono">gas per swap</span></div>
          </div>
        </div>
      </header>

      {/* --------------------------------------------------------- how it works */}
      <section>
        <div className="shell">
          <p className="eyebrow">How it works</p>
          <h2 className="head">Four steps, entirely inside the pool.</h2>
          <p className="narrow">
            No oracle, no keeper, no external call. The hook reads what v4 already writes and
            prices the next swap from it.
          </p>
          <div className="steps">
            <div className="step">
              <h3>Read the tick v4 wrote</h3>
              <p>
                <code>afterSwap</code> reads the pool&rsquo;s new tick from the{" "}
                <code>PoolManager</code>. The protocol writes it, so a caller cannot forge it.
              </p>
            </div>
            <div className="step">
              <h3>Fold it into a decaying variance</h3>
              <p>
                Squared tick move over elapsed time, into an EWMA whose weight halves every 300
                seconds.
              </p>
            </div>
            <div className="step">
              <h3>Price the next swap from it</h3>
              <p>
                <code>beforeSwap</code> decays that estimate to now, takes its square root, and
                clamps the result between 0.05% and 1%.
              </p>
            </div>
            <div className="step">
              <h3>Let quiet pools fall back</h3>
              <p>
                Decay is applied on read, so time alone lowers the fee. A pool at the ceiling
                returns to its floor with nobody trading it.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* --------------------------------------------------------------- result */}
      <section>
        <div className="shell">
          <p className="eyebrow">The result, on real flow</p>
          <h2 className="head">When Windward charges more, more happens next.</h2>
          <p className="narrow">
            Bucket every swap by the fee it paid, then measure the move that{" "}
            <em>followed</em>. The top decile precedes moves{" "}
            <strong className="sig">{r2(liftRange)}×</strong> larger than the bottom — in all five
            of the busiest pools on Unichain.
          </p>
          <LiftSection />
          <p className="narrow" style={{ marginTop: 28 }}>
            <strong>The control.</strong> Shuffle each pool&rsquo;s real{" "}
            <code>(tick move, block gap)</code> pairs. Same values, same tail, same median — only
            the clustering is destroyed. The lift collapses to{" "}
            <strong>{r2(nullLiftRange)}×</strong>. That gap is the whole claim.
          </p>
        </div>
      </section>

      {/* -------------------------------------------------------------- who for */}
      <section>
        <div className="shell">
          <p className="eyebrow">Who this is for</p>
          <h2 className="head">It prices movement, not motive.</h2>
          <p className="narrow">
            Windward cannot read intent and does not try to. It makes{" "}
            <em>whatever trades next after a violent move</em> pay more.
          </p>
          <div className="cards">
            <div className="card">
              <h3>Token launches</h3>
              <p>
                A large buy walks the price. Every swap after it — including the dump leg — is
                repriced upward until the pool settles.
              </p>
            </div>
            <div className="card">
              <h3>Pumps and dumps</h3>
              <p>
                Same mechanism. The calm pool stays cheap, the violent one gets expensive, and
                nobody has to be identified for it to work.
              </p>
            </div>
            <div className="card">
              <h3>Ordinary flow</h3>
              <p>
                A quiet pool sits at its floor, so retail in a calm market pays the base fee. That
                half is measured directly.
              </p>
            </div>
            <div className="card">
              <h3>What is not claimed</h3>
              <p>
                That it detects malicious <em>intent</em>, or that LPs end up better off. Both
                remain unproven. <Link href="/docs#limits">The full list of limits</Link>.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* ---------------------------------------------------------- engineering */}
      <section>
        <div className="shell">
          <p className="eyebrow">Engineering</p>
          <h2 className="head">Small enough to reason about.</h2>
          <div className="cards">
            <div className="card">
              <h3>It cannot move funds</h3>
              <p>
                All four <code>*_RETURNS_DELTA</code> address bits are clear, so v4 never parses a
                delta from it. No owner, no pause, no upgrade path.
              </p>
            </div>
            <div className="card">
              <h3>Deployed, bytecode verified</h3>
              <p className="addr mono">{DEPLOYED.address}</p>
              <p>
                Unichain Sepolia, block {fmt(DEPLOYED.block)}. Runtime code matched against a local
                build; the only differences are the immutable slots.
              </p>
            </div>
            <div className="card">
              <h3>61 tests, two profiles</h3>
              <p>
                Eight security findings fixed, each pinned by a regression test written while it
                still failed. One stays open and documented.
              </p>
            </div>
            <div className="card">
              <h3>{(gasEcon.gasCostUsd * 100).toFixed(4)}¢ per swap</h3>
              <p>
                {fmt(gas.gasOverhead)} gas, {gas.overheadPctOfUnhooked}% of an unhooked swap.
                Breakeven near <strong>${breakeven.toFixed(2)}</strong> a trade, which{" "}
                {shareAbove.toFixed(1)}%+ of real swaps clear.
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
    </main>
  );
}
