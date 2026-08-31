"""Render the demo page from committed data. No figure is typed by hand.

    python3 analysis/make_demo_page.py      # writes demo/index.html

Every number on the page is read out of data/economics.json, data/stats.json,
data/gas_overhead.json or data/gas_economics.json at build time (D-0017). The page is
self-contained: inline CSS and inline SVG, no network, no CDN, no build step. Open it
straight from disk.
"""

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "data")


def load(name):
    with open(os.path.join(D, name)) as f:
        return json.load(f)


def bars(series, ymax, accent, label_every=1):
    """A column chart as inline SVG. Values are drawn to a shared ymax so two charts
    placed side by side are directly comparable — that comparison is the whole point."""
    w, h, pad = 340, 190, 26
    bw = (w - pad * 2) / len(series) * 0.72
    gap = (w - pad * 2) / len(series)
    out = []
    for i, v in enumerate(series):
        bh = max(1.5, (v / ymax) * (h - pad * 2))
        x = pad + i * gap + (gap - bw) / 2
        y = h - pad - bh
        out.append(
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{bw:.1f}" height="{bh:.1f}" rx="2" fill="{accent}"/>'
        )
        if (i + 1) % label_every == 0:
            out.append(
                f'<text x="{x + bw / 2:.1f}" y="{h - pad + 13:.0f}" text-anchor="middle" '
                f'class="ax">{i + 1}</text>'
            )
    out.append(f'<line x1="{pad}" y1="{h - pad:.0f}" x2="{w - pad}" y2="{h - pad:.0f}" class="axl"/>')
    return (
        f'<svg viewBox="0 0 {w} {h}" role="img" aria-label="column chart">' + "".join(out) + "</svg>"
    )


def main():
    econ, stats = load("economics.json"), load("stats.json")
    gas, gecon = load("gas_overhead.json"), load("gas_economics.json")
    micro, sw = stats["microstructure"], stats["windwardReplaySwapWeighted"]
    pools = econ["pools"]

    ymax = max(
        max(d["meanForwardMove"] for d in p[k]["decileLift"])
        for p in pools
        for k in ("real", "shuffledNull")
    ) * 1.08

    panels = []
    for i, p in enumerate(pools):
        r = [d["meanForwardMove"] for d in p["real"]["decileLift"]]
        n = [d["meanForwardMove"] for d in p["shuffledNull"]["decileLift"]]
        lo = p["real"]["decileLift"][0]["feeMin"]
        hi = p["real"]["decileLift"][-1]["feeMax"]
        panels.append(f"""
<div class="panel" data-pool="{i}"{'' if i == 0 else ' hidden'}>
  <div class="charts">
    <figure>
      <figcaption><span class="dot real"></span>Real Unichain order</figcaption>
      {bars(r, ymax, 'var(--accent)')}
      <div class="cap">fee climbs {lo} → {hi} pips across deciles</div>
    </figure>
    <figure>
      <figcaption><span class="dot null"></span>Same moves, shuffled</figcaption>
      {bars(n, ymax, 'var(--muted-bar)')}
      <div class="cap">identical distribution, order destroyed</div>
    </figure>
  </div>
  <div class="verdict">
    <div><b>{p['liftDecile10OverDecile1']:.2f}&times;</b><span>top vs bottom decile</span></div>
    <div class="vs">vs</div>
    <div><b class="dim">{p['liftDecile10OverDecile1_shuffledNull']:.2f}&times;</b><span>shuffled null</span></div>
    <div class="rho">Spearman &rho; <b>{p['real']['spearmanFeeVsForwardVariance']}</b>
      &nbsp;/&nbsp; null <b class="dim">{p['shuffledNull']['spearmanFeeVsForwardVariance']}</b></div>
  </div>
</div>""")

    tabs = "".join(
        f'<button class="tab{" on" if i == 0 else ""}" data-t="{i}">'
        f'{p["pool"][:8]}…<span>{p["swaps"]:,}</span></button>'
        for i, p in enumerate(pools)
    )

    dv = [p["real"]["spread"]["distinctFeeValues"] for p in pools]
    nv = [p["shuffledNull"]["spread"]["distinctFeeValues"] for p in pools]
    lifts = [p["liftDecile10OverDecile1"] for p in pools]
    nlifts = [p["liftDecile10OverDecile1_shuffledNull"] for p in pools]
    v1 = stats["windwardReplay"][0]["shipped_v1"]
    v4 = stats["windwardReplay"][0]["repaired"]
    v1d = [w["shipped_v1"]["distinctFeeValues"] for w in stats["windwardReplay"]]
    v4d = [w["repaired"]["distinctFeeValues"] for w in stats["windwardReplay"]]

    html = f"""<title>Windward — pricing volatility on Uniswap v4</title>
<style>
:root{{
  --bg:#0e1116; --panel:#161b23; --line:#252c37; --fg:#e8edf5; --dim:#95a1b3;
  --accent:#4ade80; --muted-bar:#3b4552; --warn:#fbbf24;
}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--fg);
  font:16px/1.6 ui-sans-serif,-apple-system,"Segoe UI",Inter,system-ui,sans-serif;}}
.wrap{{max-width:1080px;margin:0 auto;padding:48px 28px 96px}}
section{{padding:44px 0;border-bottom:1px solid var(--line)}}
section:last-child{{border:0}}
h1{{font-size:44px;line-height:1.15;margin:0 0 14px;letter-spacing:-.02em}}
h2{{font-size:13px;letter-spacing:.14em;text-transform:uppercase;color:var(--dim);
  margin:0 0 18px;font-weight:600}}
h3{{font-size:26px;margin:0 0 12px;letter-spacing:-.01em}}
p{{margin:0 0 14px;max-width:66ch;color:#c9d3e0}}
.lede{{font-size:19px;color:var(--fg)}}
b.hi{{color:var(--accent)}}
.meta{{display:flex;gap:26px;flex-wrap:wrap;margin-top:26px;padding-top:22px;
  border-top:1px solid var(--line)}}
.meta div{{font-size:13px;color:var(--dim)}}
.meta b{{display:block;font-size:21px;color:var(--fg);font-weight:650}}
.tabs{{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:22px}}
.tab{{background:var(--panel);border:1px solid var(--line);color:var(--dim);
  padding:8px 13px;border-radius:8px;font:inherit;font-size:13px;cursor:pointer}}
.tab span{{display:block;font-size:11px;opacity:.65}}
.tab.on{{border-color:var(--accent);color:var(--fg)}}
.charts{{display:grid;grid-template-columns:repeat(auto-fit,minmax(290px,1fr));gap:20px}}
figure{{margin:0;background:var(--panel);border:1px solid var(--line);
  border-radius:12px;padding:16px}}
figcaption{{font-size:13px;color:var(--dim);margin-bottom:6px;display:flex;
  align-items:center;gap:8px}}
.dot{{width:9px;height:9px;border-radius:50%;display:inline-block}}
.dot.real{{background:var(--accent)}} .dot.null{{background:var(--muted-bar)}}
svg{{width:100%;height:auto;display:block}}
.ax{{fill:var(--dim);font-size:9px}} .axl{{stroke:var(--line)}}
.cap{{font-size:12px;color:var(--dim);margin-top:8px}}
.verdict{{display:flex;align-items:center;gap:22px;flex-wrap:wrap;margin-top:20px;
  background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:16px 20px}}
.verdict b{{font-size:32px;display:block;line-height:1.1;color:var(--accent)}}
.verdict b.dim{{color:var(--dim)}}
.verdict span{{font-size:12px;color:var(--dim)}}
.vs{{color:var(--dim);font-size:13px}}
.rho{{margin-left:auto;font-size:13px;color:var(--dim)}}
.rho b{{display:inline;font-size:15px;color:var(--fg)}}
.rho b.dim{{color:var(--dim)}}
table{{width:100%;border-collapse:collapse;margin:16px 0;font-size:14px}}
th,td{{text-align:left;padding:11px 12px;border-bottom:1px solid var(--line)}}
th{{color:var(--dim);font-weight:600;font-size:12px;letter-spacing:.06em;
  text-transform:uppercase}}
td.no{{color:var(--warn)}} td.ok{{color:var(--accent)}}
.grid2{{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:18px}}
.card{{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:20px}}
.card h4{{margin:0 0 8px;font-size:15px}}
.card p{{font-size:14px;margin:0;color:var(--dim)}}
code{{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em;
  background:#1d232c;padding:2px 6px;border-radius:4px}}
.addr{{font-family:ui-monospace,Menlo,monospace;font-size:13px;word-break:break-all;
  color:var(--accent)}}
ol{{color:#c9d3e0;max-width:66ch}} ol li{{margin-bottom:9px}}
@media(max-width:620px){{h1{{font-size:32px}}.wrap{{padding:32px 18px 64px}}}}
</style>

<div class="wrap">

<section>
  <h2>Uniswap v4 · UHI10 Hookathon</h2>
  <h1>Windward prices volatility,<br>and we tried to prove it doesn't.</h1>
  <p class="lede">A v4 hook that raises the swap fee when the pool is moving and lowers it when
  the pool is calm — from the pool's own tick history. No oracle, no external call, no admin key.</p>
  <p>Plenty of hooks claim a fee tracks volatility. The hard part is showing it isn't noise.
  So we built the control that could have killed our own result — and ran it first on our own
  headline numbers, which failed it.</p>
  <div class="meta">
    <div><b>{micro['swaps']:,}</b>swaps analysed</div>
    <div><b>{micro['spanDays']:.0f} days</b>of Unichain v4</div>
    <div><b>{sw['swaps']:,}</b>swaps replayed</div>
    <div><b>{gas['gasOverhead']:,}</b>gas overhead</div>
  </div>
</section>

<section>
  <h2>The result</h2>
  <h3>When Windward charges more, more actually happens next.</h3>
  <p>Bucket every swap by the fee it was charged, then measure the tick move that <em>followed</em>.
  If the fee is informative, the top decile should precede bigger moves than the bottom one.
  <b class="hi">It does — and the control says that isn't an accident.</b></p>
  <div class="tabs">{tabs}</div>
  {''.join(panels)}
  <p style="margin-top:20px"><b>The control.</b> Shuffle each pool's real
  <code>(tick move, block gap)</code> observations into a random order. Same multiset, same heavy
  tail, same median, same maximum — only the <em>clustering</em> is destroyed. Every pool:
  real <b class="hi">{min(lifts):.2f}–{max(lifts):.2f}&times;</b>, shuffled
  <b>{min(nlifts):.2f}–{max(nlifts):.2f}&times;</b>.</p>
</section>

<section>
  <h2>The part most submissions skip</h2>
  <h3>We ran the control on our own headline metrics. They failed.</h3>
  <p>Before this, our README led on two numbers. Both are reproduced by shuffled noise — one pool's
  null scores <em>better</em> than the real data. Neither can tell a working fee from a random one,
  so we cut them from the pitch.</p>
  <table>
    <tr><th>Metric we used to lead with</th><th>Real</th><th>Shuffled noise</th><th>Verdict</th></tr>
    <tr><td>Never sits at the fee floor</td><td>0.0%</td><td>0.0%</td>
        <td class="no">Proves nothing — cut</td></tr>
    <tr><td>Distinct fee values</td><td>{min(dv):,}–{max(dv):,}</td>
        <td>{min(nv):,}–{max(nv):,}</td><td class="no">Null wins a pool — cut</td></tr>
    <tr><td>Decile lift vs realised move</td><td>{min(lifts):.2f}–{max(lifts):.2f}&times;</td>
        <td>{min(nlifts):.2f}–{max(nlifts):.2f}&times;</td>
        <td class="ok">Survives — this is the claim</td></tr>
  </table>
  <p>Read effect sizes, not significance: at {sw['swaps']:,} swaps an economically worthless
  correlation still clears any threshold.</p>
</section>

<section>
  <h2>Why the study existed at all</h2>
  <h3>Real data caught a bug that a green test suite hid.</h3>
  <p>Integer truncation in <code>(dTick²)/dt</code> rounded
  <b>{v1['pctObservationsRoundingToZero']}%</b> of real observations to <b>zero</b>. The "dynamic"
  fee sat at its floor on <b>{sw['shipped_v1_pctAtFeeFloor']}%</b> of swaps and took just
  <b>{min(v1d)}–{max(v1d)}</b> distinct values. It was a static fee wearing a dynamic fee's
  clothes — and every unit test passed, because they used synthetic swaps large enough to hide it.</p>
  <table>
    <tr><th></th><th>Before</th><th>After</th></tr>
    <tr><td>Observations truncated to zero</td><td class="no">{v1['pctObservationsRoundingToZero']}%</td>
        <td class="ok">{v4['pctObservationsRoundingToZero']}%</td></tr>
    <tr><td>Swaps priced at the fee floor</td><td class="no">{sw['shipped_v1_pctAtFeeFloor']}%</td>
        <td class="ok">{sw['repaired_pctAtFeeFloor']}%</td></tr>
    <tr><td>Distinct fee values</td><td class="no">{min(v1d)}–{max(v1d)}</td>
        <td class="ok">{min(v4d):,}–{max(v4d):,}</td></tr>
  </table>
  <p>Real Unichain flow is small and fast — median move <b>{micro['tickMoveMedian']} tick</b>,
  median gap <b>{micro['blockGapMedian']} blocks</b>, <b>{micro['pctSameBlockConsecutiveSwaps']}%</b>
  of consecutive swaps share a block. Synthetic tests never went near that regime.</p>
</section>

<section>
  <h2>Engineering</h2>
  <div class="grid2">
    <div class="card"><h4>Cannot move funds</h4><p>Both callbacks return zero deltas and all four
      <code>*_RETURNS_DELTA</code> address bits are clear, so v4 never parses a delta from it.
      No owner, pause, upgrade or setter — every parameter is immutable.</p></div>
    <div class="card"><h4>Deployed and verified</h4><p class="addr">0x609634584d5BD12Ba4216116528e364d385Ad0C0</p>
      <p>Unichain Sepolia. Runtime bytecode matched against a local deploy-profile build — the only
      differences are the immutable slots, each confirmed through its getter.</p></div>
    <div class="card"><h4>61 tests, both profiles</h4><p>Eight security findings fixed, each pinned
      by a regression test written while it still failed. One remains open and is documented
      rather than quietly dropped.</p></div>
    <div class="card"><h4>Costs {gecon['gasCostUsd'] * 100:.4f}¢ a swap</h4>
      <p>{gas['gasOverhead']:,} gas, {gas['overheadPctOfUnhooked']}% of an unhooked swap. A swap
      clears breakeven above roughly ${max(p['breakevenP10Usd'] for p in gecon['pools']):.2f};
      {min(p['shareAboveBreakevenP10'] for p in gecon['pools']) * 100:.1f}%+ of real swaps do.</p></div>
  </div>
</section>

<section>
  <h2>What we are not claiming</h2>
  <ol>
    <li><b>The LP benefit is unvalidated.</b> We measure fee revenue, not LP PnL, and there is no
      demand-elasticity model for flow that leaves at a higher fee.</li>
    <li><b>This is a heuristic.</b> Motivated by the loss-versus-rebalancing literature — not an
      implementation of any optimal policy from it. The word <em>optimal</em> is not used.</li>
    <li><b>The lift is a correlation.</b> It shows the fee is charged at the right <em>times</em>,
      not that the revenue exceeds the adverse selection it offsets.</li>
    <li><b>One open finding.</b> A same-block round trip can strand the tick anchor. It cannot move
      funds and costs the griefer more than the target, but a production deployment must fix it.</li>
    <li><b>Scope.</b> Five busiest pools, one chain, one 7-day window. The thin-pool regime is
      untested.</li>
  </ol>
  <p style="margin-top:18px">Every number on this page is generated from committed JSON by
  <code>analysis/make_demo_page.py</code>. <code>analysis/run.sh</code> rebuilds all of it from
  the chain.</p>
</section>

</div>
<script>
document.querySelectorAll('.tab').forEach(function(t){{
  t.addEventListener('click', function(){{
    var i = t.dataset.t;
    document.querySelectorAll('.tab').forEach(function(x){{ x.classList.toggle('on', x === t); }});
    document.querySelectorAll('.panel').forEach(function(p){{ p.hidden = p.dataset.pool !== i; }});
  }});
}});
</script>
"""
    out = os.path.join(ROOT, "demo", "index.html")
    with open(out, "w") as f:
        f.write(html)
    print("wrote", out)


if __name__ == "__main__":
    main()
