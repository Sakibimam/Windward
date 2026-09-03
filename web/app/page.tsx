import LiftSection from "@/components/LiftSection";
import FeeStates from "@/components/FeeStates";
import Link from "next/link";
import {
  micro, swapWeighted, gas, liftRange, nullLiftRange, fmt,
  staleLift, staleNull, pctArbBelowRetail, pctFirstOfBlock,
} from "@/lib/data";

const r2 = ([a, b]: readonly [number, number]) => `${a.toFixed(2)}–${b.toFixed(2)}`;

export default function Page() {
  return (
    <main>
      {/* ---------------------------------------------------------------- hero */}
      <header className="hero">
        <div className="shell">
          <span className="badge-pill">Uniswap v4 hook &middot; UHI10 Hookathon</span>
          <h1 className="display hero-h">
            Calm pool, cheap swap.<br />
            Wild pool, <em>higher fee</em>.
          </h1>
          <p className="lede narrow">
            Windward reads how hard a pool is moving and sets the trading fee to match, on every
            swap. It works from the pool&rsquo;s own price history, so there is no oracle to feed it
            and no key that can change it.
          </p>
          <div className="hero-actions">
            <Link href="/demo" className="btn">See it live</Link>
            <Link href="/docs" className="btn ghost">Read the docs</Link>
          </div>
        </div>
      </header>

      {/* --------------------------------------------------------- the picture */}
      <section className="tight">
        <div className="shell">
          <FeeStates />
          <p className="caption">
            The estimator at three regimes, run at build time with the deployed parameters.
            Floor 0.05%, ceiling 1%.
          </p>
          <div className="facts spaced">
            <div><b className="tnum">{fmt(micro.swaps)}</b><span className="mono">swaps analysed</span></div>
            <div><b className="tnum">{micro.spanDays.toFixed(0)} days</b><span className="mono">of Unichain v4</span></div>
            <div><b className="tnum">{fmt(swapWeighted.swaps)}</b><span className="mono">swaps replayed</span></div>
            <div><b className="tnum">{fmt(gas.gasOverhead)}</b><span className="mono">gas per swap</span></div>
          </div>
        </div>
      </section>

      {/* --------------------------------------------------------- how it works */}
      <section>
        <div className="shell">
          <p className="eyebrow">How it works</p>
          <h2 className="head">Four steps, all inside the pool.</h2>
          <div className="steps">
            <div className="step">
              <h3>Watch</h3>
              <p>After each swap, the hook reads the pool&rsquo;s new price from Uniswap itself.</p>
            </div>
            <div className="step">
              <h3>Remember</h3>
              <p>Recent movement is kept as one number. Older movement fades from it.</p>
            </div>
            <div className="step">
              <h3>Price</h3>
              <p>Before the next swap, that number becomes the fee, between 0.05% and 1%.</p>
            </div>
            <div className="step">
              <h3>Forget</h3>
              <p>Quiet time lowers the fee on its own. Nobody has to trade to reset it.</p>
            </div>
          </div>
        </div>
      </section>

      {/* --------------------------------------------------------------- result */}
      <section>
        <div className="shell">
          <p className="eyebrow">Does it actually work?</p>
          <h2 className="head">When it charges more, more happens next.</h2>
          <p className="narrow">
            Sort real swaps by the fee they paid, then measure what the price did{" "}
            <em>afterwards</em>. The most expensive tenth precede moves{" "}
            <strong className="sig">{r2(liftRange)}×</strong> bigger than the cheapest, in all five
            of Unichain&rsquo;s busiest pools.
          </p>
          <LiftSection />
          <p className="narrow" style={{ marginTop: 26 }}>
            <strong>The check.</strong> Shuffle the same moves into a random order and the effect
            collapses to <strong>{r2(nullLiftRange)}×</strong>. The signal is the timing, not the
            numbers.
          </p>
        </div>
      </section>

      {/* -------------------------------------------------------------- signals */}
      <section>
        <div className="shell">
          <p className="eyebrow">What the data said</p>
          <h2 className="head">Two popular signals point the wrong way.</h2>
          <p className="narrow">
            Most dynamic-fee designs read one of these. On {fmt(micro.swaps)} real Unichain swaps,
            both behave backwards, so Windward uses neither.
          </p>
          <div className="findings">
            <div className="finding bad">
              <span className="mono tag">Inverted</span>
              <h3>Priority fee</h3>
              <p>
                Charging bots more assumes they bid up. {pctFirstOfBlock}% of swaps face no
                competition at all, and the arbitrage proxy tips <em>below</em> retail{" "}
                {pctArbBelowRetail}% of the time.
              </p>
            </div>
            <div className="finding bad">
              <span className="mono tag">Inverted</span>
              <h3>Price staleness</h3>
              <p>
                Idle pools are meant to drift out of line. The longest-idle tenth precede{" "}
                <em>smaller</em> moves: {r2(staleLift)}× against {r2(staleNull)}× for shuffled
                data.
              </p>
            </div>
            <div className="finding good">
              <span className="mono tag">Survived</span>
              <h3>Realised movement</h3>
              <p>
                The pool&rsquo;s own price history passes the same test the other two fail. That
                is the one Windward prices.
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
            A simulator, the deployed contract read live, and a pool you can trade yourself.
          </p>
          <Link href="/demo" className="btn big">See it live</Link>
        </div>
      </section>
    </main>
  );
}
