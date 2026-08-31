import {
  micro, swapWeighted, v1, v4, v1Distinct, v4Distinct,
  liftRange, nullLiftRange, distinctRealRange, distinctNullRange, fmt,
} from "@/lib/data";

export const metadata = { title: "Method — Windward" };

const r2 = ([a, b]: readonly [number, number], d = 2) => `${a.toFixed(d)}–${b.toFixed(d)}`;
const ri = ([a, b]: readonly [number, number]) => `${fmt(a)}–${fmt(b)}`;

export default function AboutPage() {
  return (
    <main>
      <header className="page-head">
        <div className="shell">
          <p className="eyebrow">Method</p>
          <h1 className="display page-h">
            How we tried to prove ourselves wrong.
          </h1>
          <p className="lede narrow">
            A fee that varies is not evidence of anything. This is the work that separates a
            signal from an expensive random number generator — including the parts where our own
            numbers did not survive it.
          </p>
        </div>
      </header>

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

    </main>
  );
}
