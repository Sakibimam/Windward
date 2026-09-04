import Link from "next/link";
import Lifecycle from "@/components/Lifecycle";
import { gas, gasEcon, fmt, v1 } from "@/lib/data";
import { DEPLOYED, WAD, update, feeFor, sigmaWad, decayFactor } from "@/lib/volatility";

const REPO = "https://github.com/Sakibimam/Windward";

const { feeMin, feeMax, feePerSigma, halfLife } = DEPLOYED;
const pct = (pips: number) => `${(pips / 10000).toFixed(3)}%`;

/** One observation from a standing start, run through the deployed estimator at build time. */
function observe(moveTicks: number, seconds: bigint) {
  const variance = update(0n, 0n, BigInt(moveTicks), seconds, halfLife);
  return {
    moveTicks,
    seconds: Number(seconds),
    sigma: Number((sigmaWad(variance) * 100n) / WAD) / 100,
    fee: Number(feeFor(variance, feeMin, feeMax, feePerSigma)),
    variance,
  };
}

const EXAMPLES = [
  observe(1, 12n),
  observe(10, 5n),
  observe(40, 2n),
  observe(120, 1n),
  observe(400, 1n),
];

/** The same hot pool, left alone. Nothing trades; only time passes. */
const HOT = EXAMPLES[EXAMPLES.length - 1].variance;
const DECAY = [0, 300, 900, 1800, 3600].map((secs) => ({
  secs,
  fee: Number(
    feeFor((decayFactor(BigInt(secs), halfLife) * HOT) / WAD, feeMin, feeMax, feePerSigma),
  ),
}));

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
            <a href="#start">Start here</a>
            <a href="#architecture">Architecture</a>
            <a href="#mechanism">Mechanism</a>
            <a href="#parameters">Parameters</a>
            <a href="#integrate">Integration</a>
            <a href="#deploy">Deployment</a>
            <a href="#limits">Limits</a>
            <a href="#words">Glossary</a>
          </nav>
        </div>
      </header>

      {/* ---------------------------------------------------------------- start */}
      <section id="start">
        <div className="shell">
          <p className="eyebrow">Start here</p>
          <h2 className="head">What the hook actually does.</h2>
          <p className="narrow">
            A Uniswap pool normally charges one fixed fee. Windward replaces that with a fee that
            follows how much the pool is moving, and it works out the number itself, from the
            pool&rsquo;s own trading history. Nothing feeds it from outside.
          </p>
          <div className="cards">
            <div className="card">
              <h3>When the pool is quiet</h3>
              <p>
                Small price moves, minutes apart. The fee sits at its floor of{" "}
                <strong>{pct(Number(feeMin))}</strong>, which is what an ordinary 0.05% pool would
                have charged anyway.
              </p>
            </div>
            <div className="card">
              <h3>When the pool is moving hard</h3>
              <p>
                Large moves, seconds apart. The fee climbs, up to a hard ceiling of{" "}
                <strong>{pct(Number(feeMax))}</strong>. It can never go above that, whatever
                happens.
              </p>
            </div>
            <div className="card">
              <h3>When trading stops</h3>
              <p>
                The fee falls again on its own, purely because time passes. No one has to trade,
                and there is no keeper or admin to poke it.
              </p>
            </div>
          </div>
          <p className="narrow" style={{ marginTop: 22 }}>
            <strong>Who pays what.</strong> The fee is decided <em>before</em> a swap runs, from
            what already happened. So the trader who causes a big move pays the old, lower fee, and
            whoever trades next pays the raised one. That ordering is a property of every fee that
            reacts to price rather than predicting it, and it is stated again under{" "}
            <a href="#limits">Limits</a>.
          </p>
        </div>
      </section>

      {/* ----------------------------------------------------------- architecture */}
      <section id="architecture">
        <div className="shell">
          <p className="eyebrow">Architecture</p>
          <h2 className="head">Where the hook sits.</h2>
          <p className="narrow">
            Uniswap v4 lets a contract register for callbacks at fixed points in a swap. Windward
            registers for two of them: once just before the swap, to set the fee, and once just
            after, to record what happened. Both happen inside the trader&rsquo;s own transaction.
          </p>

          <Lifecycle />

          <p className="narrow">
            Steps 3, 4 and 7 are the only places the hook touches storage, and what it touches is a
            single number for that pool. There is no queue, no scheduled job and no second contract.
            If the trade reverts, every one of these steps reverts with it.
          </p>

          <h3 className="sub-head">What it is allowed to do</h3>
          <p className="narrow">
            A v4 hook&rsquo;s powers are encoded in its own address, and the protocol checks them
            before it will run. Windward&rsquo;s address grants three and withholds the rest.
          </p>
          <div className="tw">
            <table>
              <thead><tr><th>Capability</th><th>Windward</th><th>What that means for you</th></tr></thead>
              <tbody>
                <tr>
                  <td className="mono">beforeSwap</td>
                  <td className="keep">granted</td>
                  <td>It can set the fee for the swap about to happen.</td>
                </tr>
                <tr>
                  <td className="mono">afterSwap</td>
                  <td className="keep">granted</td>
                  <td>It can read the price the swap ended at.</td>
                </tr>
                <tr>
                  <td className="mono">afterInitialize</td>
                  <td className="keep">granted</td>
                  <td>It sets a pool up the first time, and refuses pools that are not dynamic-fee.</td>
                </tr>
                <tr>
                  <td className="mono">*_RETURNS_DELTA</td>
                  <td className="cut">withheld</td>
                  <td>
                    It cannot take, redirect or keep any part of a trade. v4 never even reads a
                    balance change back from it, so the inability is the protocol&rsquo;s, not a
                    promise of ours.
                  </td>
                </tr>
                <tr>
                  <td>Liquidity callbacks</td>
                  <td className="cut">withheld</td>
                  <td>It is not called when anyone adds or removes liquidity, so it cannot block a withdrawal.</td>
                </tr>
              </tbody>
            </table>
          </div>
          <p className="narrow">
            Those permissions are readable from the deployed address itself, which is how the
            constructor validates them. See <a href="#deploy">Deployment</a> for the values read
            back off chain.
          </p>
        </div>
      </section>

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

          <h3 className="sub-head">What that produces, in numbers</h3>
          <p className="narrow">
            Every row below is computed when this page is built, by the same code the deployed
            contract runs. A tick is Uniswap&rsquo;s smallest price step, about one hundredth of
            one percent.
          </p>
          <div className="tw">
            <table>
              <thead>
                <tr>
                  <th>The pool moves</th><th>In</th><th>σ</th><th>Fee charged next</th>
                </tr>
              </thead>
              <tbody>
                {EXAMPLES.map((e) => (
                  <tr key={e.moveTicks}>
                    <td className="num">{e.moveTicks} tick{e.moveTicks === 1 ? "" : "s"}</td>
                    <td className="num">{e.seconds}s</td>
                    <td className="num">{e.sigma.toFixed(2)}</td>
                    <td className="num"><strong>{pct(e.fee)}</strong> <span className="mono">({e.fee} pips)</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="narrow">
            Each row starts from a calm pool and applies one observation, so a real pool that is
            already busy reaches a given fee sooner than this suggests.
          </p>

          <h3 className="sub-head">And what happens when trading stops</h3>
          <p className="narrow">
            Taking the last row above, a pool at {pct(DECAY[0].fee)}, and then letting it sit with
            nobody trading at all:
          </p>
          <div className="tw">
            <table>
              <thead><tr><th>Time with no trades</th><th>Fee</th></tr></thead>
              <tbody>
                {DECAY.map((d) => (
                  <tr key={d.secs}>
                    <td className="num">
                      {d.secs === 0 ? "immediately after" : d.secs < 3600
                        ? `${d.secs / 60} minutes`
                        : `${d.secs / 3600} hour`}
                    </td>
                    <td className="num"><strong>{pct(d.fee)}</strong> <span className="mono">({d.fee} pips)</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="narrow">
            The estimate halves every <strong>{halfLife.toString()} seconds</strong> of silence.
            Nothing runs to make this happen: the decay is applied at the moment the fee is read,
            so an idle pool is already cheap by the time anyone asks.
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

      {/* ------------------------------------------------------------- glossary */}
      <section id="words">
        <div className="shell">
          <p className="eyebrow">Glossary</p>
          <h2 className="head">The words on this page, in plain English.</h2>
          <div className="tw">
            <table>
              <tbody>
                <tr>
                  <th>Tick</th>
                  <td>Uniswap&rsquo;s smallest price step, roughly one hundredth of one percent. A pool that moves 100 ticks has moved about 1%.</td>
                </tr>
                <tr>
                  <th>Pip</th>
                  <td>One hundredth of one percent of a trade, the unit fees are quoted in. 500 pips is 0.05%; 10,000 pips is 1%.</td>
                </tr>
                <tr>
                  <th>Variance</th>
                  <td>How much the price has been jumping around, squared and averaged. Squaring is what makes one big move count for more than several small ones.</td>
                </tr>
                <tr>
                  <th>σ (sigma)</th>
                  <td>The square root of variance, back in the units you started in. This is the number the fee is scaled from.</td>
                </tr>
                <tr>
                  <th>EWMA</th>
                  <td>Exponentially weighted moving average. An average that leans on recent readings and lets old ones fade, rather than treating a move from an hour ago as equal to one from a second ago.</td>
                </tr>
                <tr>
                  <th>Half-life</th>
                  <td>How long the estimate takes to lose half its weight. At {halfLife.toString()} seconds, a reading counts half as much five minutes later and a quarter as much ten minutes later.</td>
                </tr>
                <tr>
                  <th>Decile</th>
                  <td>One tenth of the data, sorted. &ldquo;Top fee decile&rdquo; means the tenth of swaps that paid the highest fees.</td>
                </tr>
                <tr>
                  <th>Shuffled null</th>
                  <td>A control. The same real numbers put in a random order, so any pattern that survives is coming from the ordering rather than from the numbers themselves.</td>
                </tr>
                <tr>
                  <th>WAD</th>
                  <td>Fixed-point arithmetic scaled by 10<sup>18</sup>. Solidity has no decimals, so fractions are carried as very large integers.</td>
                </tr>
                <tr>
                  <th>Hook</th>
                  <td>A contract Uniswap v4 calls at set moments during a swap. This one is called just before and just after.</td>
                </tr>
                <tr>
                  <th>Immutable</th>
                  <td>Fixed at deployment and unchangeable afterwards, by anyone including us. A pool wanting different numbers has to deploy its own copy.</td>
                </tr>
                <tr>
                  <th>C-1</th>
                  <td>Our label for the one security finding still open. Buy and sell inside a single block and the hook&rsquo;s record of &ldquo;where the price was&rdquo; can stick at a price that never really held, so the next honest trader is charged for a move that did not happen. It cannot move anyone&rsquo;s funds.</td>
                </tr>
              </tbody>
            </table>
          </div>
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
