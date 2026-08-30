import LiftSection from "@/components/LiftSection";
import Simulator from "@/components/Simulator";
import {
  micro, swapWeighted, gas, gasEcon, v1, v4, v1Distinct, v4Distinct,
  liftRange, nullLiftRange, distinctRealRange, distinctNullRange,
  breakeven, shareAbove, fmt,
} from "@/lib/data";
import { DEPLOYED } from "@/lib/volatility";

const r2 = ([a, b]: readonly [number, number], d = 2) => `${a.toFixed(d)}–${b.toFixed(d)}`;
const ri = ([a, b]: readonly [number, number]) => `${fmt(a)}–${fmt(b)}`;

export default function Page() {
  return (
    <main>
      {/* ---------------------------------------------------------------- hero */}
      <header className="hero">
        <div className="shell">
          <p className="eyebrow">Uniswap v4 · UHI10 Hookathon</p>
          <h1 className="display hero-h">
            A fee that reads the pool&rsquo;s own volatility —<br />
            and the test that <em>could have killed it</em>.
          </h1>
          <p className="lede narrow">
            Windward raises the swap fee while a pool is moving and lets it fall as the pool goes
            quiet, from tick history alone. No oracle, no external call, no admin key.
          </p>
          <p className="narrow">
            Plenty of hooks claim their fee tracks volatility. The hard part is showing it is not
            noise wearing a signal&rsquo;s clothes. So we built the control that could have
            falsified our own result — and ran it first against our own headline numbers, which
            did not survive it.
          </p>
          <div className="facts">
            <div><b className="tnum">{fmt(micro.swaps)}</b><span className="mono">swaps analysed</span></div>
            <div><b className="tnum">{micro.spanDays.toFixed(0)} days</b><span className="mono">of Unichain v4</span></div>
            <div><b className="tnum">{fmt(swapWeighted.swaps)}</b><span className="mono">swaps replayed</span></div>
            <div><b className="tnum">{fmt(gas.gasOverhead)}</b><span className="mono">gas per swap</span></div>
          </div>
        </div>
      </header>

      {/* ----------------------------------------------------------- simulator */}
      <section>
        <div className="shell">
          <p className="eyebrow">Watch it work</p>
          <h2 className="head">The fee moves because the market moved.</h2>
          <p className="narrow">
            This runs the deployed contract&rsquo;s arithmetic, in your browser, on simulated flow.
            Switch the market between calm and volatile and watch the fee follow — then stop
            trading and watch it decay back toward the floor on its own.
          </p>
          <Simulator />
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

      {/* -------------------------------------------------------- falsification */}
      <section>
        <div className="shell">
          <p className="eyebrow">The part most submissions skip</p>
          <h2 className="head">We ran that control against our own headline metrics. They failed.</h2>
          <p className="narrow">
            This project used to lead on two numbers. Shuffled noise reproduces both — and on one
            pool the null scores <em>better</em> than the real data. Neither can separate a working
            fee from a random one, so they were cut from the claim rather than quietly kept.
          </p>
          <div className="tw">
            <table>
              <thead>
                <tr><th>Metric</th><th>Real</th><th>Shuffled noise</th><th>Outcome</th></tr>
              </thead>
              <tbody>
                <tr>
                  <td>Never sits at the fee floor</td>
                  <td className="num">0.0%</td><td className="num">0.0%</td>
                  <td className="cut">Cut — proves nothing</td>
                </tr>
                <tr>
                  <td>Distinct fee values</td>
                  <td className="num">{ri(distinctRealRange)}</td>
                  <td className="num">{ri(distinctNullRange)}</td>
                  <td className="cut">Cut — the null wins a pool</td>
                </tr>
                <tr>
                  <td>Decile lift vs realised move</td>
                  <td className="num">{r2(liftRange)}×</td>
                  <td className="num">{r2(nullLiftRange)}×</td>
                  <td className="keep">Kept — this is the claim</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p className="narrow">
            Effect sizes, not significance: at {fmt(swapWeighted.swaps)} swaps an economically
            worthless correlation still clears any threshold you like.
          </p>
        </div>
      </section>

      {/* ----------------------------------------------------------------- bug */}
      <section>
        <div className="shell">
          <p className="eyebrow">Why the study existed</p>
          <h2 className="head">Real order flow caught a bug a green test suite was hiding.</h2>
          <p className="narrow">
            Integer truncation in <code>(dTick²)/dt</code> rounded{" "}
            <strong>{v1.pctObservationsRoundingToZero}%</strong> of real observations to{" "}
            <strong>zero</strong>. The &ldquo;dynamic&rdquo; fee sat at its floor on{" "}
            <strong>{swapWeighted.shipped_v1_pctAtFeeFloor}%</strong> of swaps and took{" "}
            <strong>{ri(v1Distinct)}</strong> distinct values — a static fee wearing a dynamic
            fee&rsquo;s clothes. Every unit test passed throughout, because they used synthetic
            swaps large enough to step straight over the truncation.
          </p>
          <div className="tw">
            <table>
              <thead><tr><th>Busiest pool</th><th>Before</th><th>After</th></tr></thead>
              <tbody>
                <tr>
                  <td>Observations truncated to zero</td>
                  <td className="num cut">{v1.pctObservationsRoundingToZero}%</td>
                  <td className="num keep">{v4.pctObservationsRoundingToZero}%</td>
                </tr>
                <tr>
                  <td>Swaps priced at the fee floor</td>
                  <td className="num cut">{swapWeighted.shipped_v1_pctAtFeeFloor}%</td>
                  <td className="num keep">{swapWeighted.repaired_pctAtFeeFloor}%</td>
                </tr>
                <tr>
                  <td>Distinct fee values</td>
                  <td className="num cut">{ri(v1Distinct)}</td>
                  <td className="num keep">{ri(v4Distinct)}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p className="narrow">
            Real Unichain flow is small and fast: median move{" "}
            <strong>{micro.tickMoveMedian} tick</strong>, median gap{" "}
            <strong>{micro.blockGapMedian} blocks</strong>, and{" "}
            <strong>{micro.pctSameBlockConsecutiveSwaps}%</strong> of consecutive swaps share a
            block. Synthetic tests never went near that regime.
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

      {/* -------------------------------------------------------------- limits */}
      <section>
        <div className="shell">
          <p className="eyebrow">What we are not claiming</p>
          <h2 className="head">The limits, stated before anyone has to ask.</h2>
          <ol className="limits">
            <li>
              <strong>The LP benefit is unvalidated.</strong> We measure fee revenue, not LP PnL,
              and there is no demand-elasticity model for flow that leaves at a higher fee.
            </li>
            <li>
              <strong>This is a heuristic.</strong> Motivated by the loss-versus-rebalancing
              literature, not an implementation of any optimal policy from it. The word{" "}
              <em>optimal</em> is not used.
            </li>
            <li>
              <strong>The lift is a correlation.</strong> It shows the fee is charged at the right{" "}
              <em>times</em>, not that the revenue exceeds the adverse selection it offsets.
            </li>
            <li>
              <strong>One finding is open.</strong> A same-block round trip can strand the tick
              anchor. It cannot move funds and costs the griefer more than the target, but a
              production deployment must fix it.
            </li>
            <li>
              <strong>Scope.</strong> Five busiest pools, one chain, one seven-day window. The
              thin-pool regime is untested.
            </li>
          </ol>
        </div>
      </section>

      <footer className="foot">
        <div className="shell">
          <p className="mono">
            Every figure on this site is generated from the committed study output —{" "}
            <code>analysis/run.sh</code> rebuilds all of it from the chain. The simulator runs a
            BigInt port of <code>Volatility.sol</code>, pinned to the same fixed vector as the
            Solidity and Python models.
          </p>
          <p className="mono dim">
            Not audited. Prototype. Must not secure real funds. MIT licensed.
          </p>
        </div>
      </footer>
    </main>
  );
}
