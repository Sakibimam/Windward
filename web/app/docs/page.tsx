import Link from "next/link";
import { gas, gasEcon, fmt, v1 } from "@/lib/data";
import { DEPLOYED } from "@/lib/volatility";

const REPO = "https://github.com/Sakibimam/Windward";

export const metadata = {
  title: "Docs · Windward",
  description: "Parameters, integration, deployment and the complete list of limits.",
};

export default function Docs() {
  return (
    <main className="doc">
      <header className="page-head">
        <div className="shell">
          <p className="eyebrow">Docs</p>
          <h1 className="display page-h">Everything needed to check our work.</h1>
          <p className="lede narrow">
            The mechanism, the four parameters, how to point a pool at it, and the ten limits,
            including the ones that undercut the result.
          </p>
          <nav className="toc">
            <a href="#mechanism">Mechanism</a>
            <a href="#parameters">Parameters</a>
            <a href="#integrate">Integration</a>
            <a href="#deploy">Deployment</a>
            <a href="#limits">Limits</a>
          </nav>
        </div>
      </header>

      {/* ------------------------------------------------------------ mechanism */}
      <section id="mechanism">
        <div className="shell">
          <p className="eyebrow">Mechanism</p>
          <h2 className="head">One number, decayed and re-read.</h2>
          <p className="narrow">
            The hook keeps a single per-pool variance estimate. Every swap updates it; every swap
            reads it back, decayed to the current timestamp. Nothing else is stored, and nothing
            is read from outside the pool.
          </p>

          <div className="tw">
            <table>
              <thead>
                <tr><th>Stage</th><th>Hook</th><th>What happens</th></tr>
              </thead>
              <tbody>
                <tr>
                  <td>Observe</td>
                  <td className="mono">afterSwap</td>
                  <td>
                    Reads the pool&rsquo;s new tick from the <code>PoolManager</code> and folds
                    <code>(Δtick)²/Δt</code> into the EWMA.
                  </td>
                </tr>
                <tr>
                  <td>Decay</td>
                  <td className="mono">_varianceNow</td>
                  <td>
                    Halves the stored estimate every <code>halfLife</code> seconds of elapsed time,
                    on read. Rounds down, which can only lower the fee.
                  </td>
                </tr>
                <tr>
                  <td>Price</td>
                  <td className="mono">beforeSwap</td>
                  <td>
                    Takes <code>√variance</code>, scales by <code>feePerSigma</code>, clamps into
                    the band, returns it with the override flag, for that swap only.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <p className="narrow">
            Two details matter more than they look. WAD scaling is carried <em>through</em> the
            division rather than after it. Doing it the other way rounded{" "}
            <strong>{v1.pctObservationsRoundingToZero}%</strong> of real observations to zero,
            which is the bug the study found. And when <code>Δt</code> is zero the anchor is held
            rather than updated, which is what stops a dust swap suppressing the estimate.
          </p>
        </div>
      </section>

      {/* ----------------------------------------------------------- parameters */}
      <section id="parameters">
        <div className="shell">
          <p className="eyebrow">Parameters</p>
          <h2 className="head">Four constructor arguments, all immutable.</h2>
          <div className="tw">
            <table>
              <thead>
                <tr><th>Name</th><th>Value</th><th>Meaning</th></tr>
              </thead>
              <tbody>
                <tr>
                  <td className="mono">feeMin</td>
                  <td className="num">{DEPLOYED.feeMin.toString()}</td>
                  <td>Floor, 0.05%. What a calm pool charges.</td>
                </tr>
                <tr>
                  <td className="mono">feeMax</td>
                  <td className="num">{DEPLOYED.feeMax.toString()}</td>
                  <td>Ceiling, 1.00%. The fee can never exceed it.</td>
                </tr>
                <tr>
                  <td className="mono">feePerSigma</td>
                  <td className="num">{DEPLOYED.feePerSigma.toString()}</td>
                  <td>Pips of fee per unit of σ (ticks per √second).</td>
                </tr>
                <tr>
                  <td className="mono">halfLife</td>
                  <td className="num">{DEPLOYED.halfLife.toString()}s</td>
                  <td>How long the estimate takes to lose half its weight.</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p className="narrow flagged">
            <strong>These are choices, not results.</strong> Nothing in the study derives, fits or
            optimises any of them, and no sensitivity analysis was run. They are{" "}
            <code>immutable</code>, so a pool wanting different values needs its own deployment.
          </p>
        </div>
      </section>

      {/* ---------------------------------------------------------- integration */}
      <section id="integrate">
        <div className="shell">
          <p className="eyebrow">Integration</p>
          <h2 className="head">Two requirements, both enforced.</h2>
          <div className="cards">
            <div className="card">
              <h3>Initialise with the dynamic-fee flag</h3>
              <p>
                The pool key&rsquo;s fee field must be <code>0x800000</code>. Anything else and{" "}
                <code>afterInitialize</code> reverts by design, so a pool cannot silently get a
                static fee from a dynamic hook.
              </p>
            </div>
            <div className="card">
              <h3>Swap through a router</h3>
              <p>
                v4 routes all swaps through <code>unlockCallback</code>. There is no path that
                calls the <code>PoolManager</code> directly, so integrations use a router exactly
                as they would for any other pool.
              </p>
            </div>
            <div className="card">
              <h3>Quote with <code>currentFee</code></h3>
              <p>
                The view decays on read, so an off-chain quoter sees the same fee the next swap
                will actually be charged. Quoting from raw stored state overstates it.
              </p>
            </div>
            <div className="card">
              <h3>Budget {fmt(gas.gasOverhead)} gas</h3>
              <p>
                {gas.overheadPctOfUnhooked}% on top of an unhooked swap, or about{" "}
                {(gasEcon.gasCostUsd * 100).toFixed(4)}¢ at the measured gas price.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* ------------------------------------------------------------- deployed */}
      <section id="deploy">
        <div className="shell">
          <p className="eyebrow">Deployment</p>
          <h2 className="head">Live on Unichain Sepolia.</h2>
          <div className="tw">
            <table>
              <tbody>
                <tr><th>Address</th><td className="mono">{DEPLOYED.address}</td></tr>
                <tr><th>Chain</th><td>Unichain Sepolia · {DEPLOYED.chainId}</td></tr>
                <tr><th>Block</th><td className="num">{fmt(DEPLOYED.block)}</td></tr>
                <tr><th>Admin surface</th><td>None. No owner, pause, upgrade path or setter.</td></tr>
                <tr><th>Can it move funds?</th><td>No. All four <code>*_RETURNS_DELTA</code> bits are clear.</td></tr>
              </tbody>
            </table>
          </div>
          <p className="narrow">
            The runtime code was compared byte-for-byte against a local deploy-profile build. It
            differs in 111 places, all of them inside the compiler-recorded immutable ranges, each
            confirmed through its getter. Full evidence in{" "}
            <a href={`${REPO}/blob/main/docs/DEPLOYMENT.md`} target="_blank" rel="noreferrer">
              docs/DEPLOYMENT.md
            </a>.
          </p>
          <p className="narrow flagged">
            Testnet only. This is an unaudited hackathon prototype and must not secure real funds.
          </p>
        </div>
      </section>

      {/* --------------------------------------------------------------- limits */}
      <section id="limits">
        <div className="shell">
          <p className="eyebrow">Limits</p>
          <h2 className="head">All ten, including the ones that hurt.</h2>
          <p className="narrow">
            Condensed from{" "}
            <a href={`${REPO}/blob/main/docs/LIMITATIONS.md`} target="_blank" rel="noreferrer">
              docs/LIMITATIONS.md
            </a>, which carries them unabridged.
          </p>
          <ol className="limits">
            <li>
              <strong>It is a heuristic.</strong> Motivated by the loss-versus-rebalancing
              literature, not an implementation of any optimal policy from it. The word{" "}
              <em>optimal</em> is not used.
            </li>
            <li>
              <strong>The LP benefit is unvalidated.</strong> We measure fee revenue, not LP PnL,
              and there is no demand-elasticity model for flow that leaves at a higher fee.
            </li>
            <li>
              <strong>The replay covers the five busiest pools only.</strong> 136,167 swaps across
              227 pools were never replayed, so the thin-pool regime is untested.
            </li>
            <li>
              <strong>The fee is charged to the trader after the mover.</strong> A property of
              every reactive dynamic fee, not a bug specific to this one.
            </li>
            <li>
              <strong>It conflates transient and permanent impact.</strong> LVR depends on the
              permanent component; the estimator does not separate them.
            </li>
            <li>
              <strong>The tick is steerable.</strong> A funded actor can raise a pool&rsquo;s fee
              by trading it.
            </li>
            <li>
              <strong>All four parameters are underived.</strong> Picked by hand, never fitted.
            </li>
            <li>
              <strong>One chain, one seven-day window, one public RPC.</strong> Pool identities
              come from Transfer-log heuristics, not a registry.
            </li>
            <li>
              <strong>One finding is open.</strong> A same-block round trip can strand the tick
              anchor and raise the fee an honest trader pays. Accepted and documented, not fixed.
            </li>
            <li>
              <strong>The lift is a correlation.</strong> It shows the fee is charged at the right{" "}
              <em>times</em>. It does not show the revenue exceeds the adverse selection it is
              meant to offset.
            </li>
          </ol>
        </div>
      </section>

      {/* --------------------------------------------------------------- source */}
      <section>
        <div className="shell">
          <p className="eyebrow">Source</p>
          <h2 className="head">Read the rest in the repo.</h2>
          <div className="cards">
            <div className="card">
              <h3><a href={`${REPO}/blob/main/THREAT_MODEL.md`} target="_blank" rel="noreferrer">Threat model</a></h3>
              <p>Every finding, fixed and open, with the reasoning for each.</p>
            </div>
            <div className="card">
              <h3><a href={`${REPO}/blob/main/docs/SIGNALS.md`} target="_blank" rel="noreferrer">Signals</a></h3>
              <p>How each of the three candidate signals was tested, and why two were dropped.</p>
            </div>
            <div className="card">
              <h3><a href={`${REPO}/blob/main/docs/ABLATION.md`} target="_blank" rel="noreferrer">Ablation</a></h3>
              <p>What each component contributes, measured by removing it.</p>
            </div>
            <div className="card">
              <h3><a href={`${REPO}/blob/main/DECISIONS.md`} target="_blank" rel="noreferrer">Decision log</a></h3>
              <p>Every design call, dated, including the ones later reversed.</p>
            </div>
          </div>
          <div className="hero-actions" style={{ marginTop: 30 }}>
            <Link href="/demo" className="btn">Open the live demo</Link>
            <a className="btn ghost" href={REPO} target="_blank" rel="noreferrer">View on GitHub</a>
          </div>
        </div>
      </section>
    </main>
  );
}
