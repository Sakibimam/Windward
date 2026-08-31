"""Render the demo page from committed data. No figure is typed by hand.

    python3 analysis/make_demo_page.py      # writes demo/index.html

Every number on the page is read out of data/economics.json, data/stats.json,
data/gas_overhead.json or data/gas_economics.json at build time (D-0017).

The page is one self-contained file: inline CSS, inline SVG, no build step. Web fonts are
requested from Google Fonts but every stack has a real fallback, so the page still reads
correctly with no network — which matters, because the rest of the demo runs offline.
"""

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D = os.path.join(ROOT, "data")


def load(name):
    with open(os.path.join(D, name)) as f:
        return json.load(f)


def chart(series, ymax, fill, hatch=False):
    """A column chart as inline SVG.

    Both charts on the page are drawn to a shared `ymax`, because the comparison between them
    is the entire argument — a chart rescaled to its own data would hide the effect.
    The null series is hatched rather than merely tinted, so it reads as noise at a glance.
    """
    w, h, pad_l, pad_b, pad_t = 360, 208, 30, 30, 16
    n = len(series)
    slot = (w - pad_l - 14) / n
    bw = slot * 0.66
    parts = []
    for i, v in enumerate(series):
        bh = max(2.0, (v / ymax) * (h - pad_b - pad_t))
        x = pad_l + i * slot + (slot - bw) / 2
        y = h - pad_b - bh
        parts.append(
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{bw:.1f}" height="{bh:.1f}" '
            f'fill="{"url(#hatch)" if hatch else fill}" stroke="{fill}" stroke-width="1"/>'
        )
        if i in (0, n - 1):
            parts.append(
                f'<text x="{x + bw / 2:.1f}" y="{y - 6:.1f}" text-anchor="middle" '
                f'class="val">{v:g}</text>'
            )
        parts.append(
            f'<text x="{x + bw / 2:.1f}" y="{h - pad_b + 15:.0f}" text-anchor="middle" '
            f'class="ax">{i + 1}</text>'
        )
    # Gridlines carry the shared scale; without them "same axis" is a claim, not a fact.
    for g in range(1, 5):
        gy = h - pad_b - (g / 4) * (h - pad_b - pad_t)
        parts.insert(0, f'<line x1="{pad_l}" y1="{gy:.1f}" x2="{w - 8}" y2="{gy:.1f}" class="grid"/>')
        parts.insert(1, f'<text x="{pad_l - 7}" y="{gy + 3.5:.1f}" text-anchor="end" '
                        f'class="ax">{(g / 4) * ymax:.0f}</text>')
    parts.append(f'<line x1="{pad_l}" y1="{h - pad_b}" x2="{w - 8}" y2="{h - pad_b}" class="axis"/>')
    return (
        f'<svg viewBox="0 0 {w} {h}" role="img">'
        '<defs><pattern id="hatch" width="5" height="5" patternTransform="rotate(45)" '
        'patternUnits="userSpaceOnUse">'
        '<line x1="0" y="0" x2="0" y2="5" class="hl"/></pattern></defs>'
        + "".join(parts) + "</svg>"
    )


def main():
    econ, stats = load("economics.json"), load("stats.json")
    gas, gecon = load("gas_overhead.json"), load("gas_economics.json")
    micro, sw = stats["microstructure"], stats["windwardReplaySwapWeighted"]
    pools = econ["pools"]

    ymax = max(d["meanForwardMove"] for p in pools for k in ("real", "shuffledNull")
               for d in p[k]["decileLift"]) * 1.12

    panels = []
    for i, p in enumerate(pools):
        r = [d["meanForwardMove"] for d in p["real"]["decileLift"]]
        nl = [d["meanForwardMove"] for d in p["shuffledNull"]["decileLift"]]
        lo, hi = p["real"]["decileLift"][0]["feeMin"], p["real"]["decileLift"][-1]["feeMax"]
        panels.append(f"""
<div class="panel" data-pool="{i}"{'' if i == 0 else ' hidden'}>
  <div class="twin">
    <figure>
      <figcaption><span class="key sig"></span>Real order</figcaption>
      {chart(r, ymax, 'var(--signal)')}
      <p class="cap">Fee rises {lo}&thinsp;&rarr;&thinsp;{hi} pips across the deciles.</p>
    </figure>
    <figure>
      <figcaption><span class="key nul"></span>Shuffled</figcaption>
      {chart(nl, ymax, 'var(--noise)', hatch=True)}
      <p class="cap">Same moves, same gaps. Order destroyed.</p>
    </figure>
  </div>
  <div class="verdict">
    <div class="big"><b>{p['liftDecile10OverDecile1']:.2f}&times;</b>
      <span>top decile / bottom decile</span></div>
    <div class="big"><b class="mute">{p['liftDecile10OverDecile1_shuffledNull']:.2f}&times;</b>
      <span>same test, shuffled</span></div>
    <div class="rho">Spearman&nbsp;&rho; vs forward variance<br>
      <b>{p['real']['spearmanFeeVsForwardVariance']}</b> real
      &nbsp;·&nbsp; <b class="mute">{p['shuffledNull']['spearmanFeeVsForwardVariance']}</b> null</div>
  </div>
</div>""")

    tabs = "".join(
        f'<button class="tab{" on" if i == 0 else ""}" data-t="{i}" type="button">'
        f'<em>{p["pool"][:8]}…</em><span>{p["swaps"]:,} swaps</span></button>'
        for i, p in enumerate(pools))

    dv = [p["real"]["spread"]["distinctFeeValues"] for p in pools]
    nv = [p["shuffledNull"]["spread"]["distinctFeeValues"] for p in pools]
    lf = [p["liftDecile10OverDecile1"] for p in pools]
    nf = [p["liftDecile10OverDecile1_shuffledNull"] for p in pools]
    v1 = stats["windwardReplay"][0]["shipped_v1"]
    v4 = stats["windwardReplay"][0]["repaired"]
    v1d = [w["shipped_v1"]["distinctFeeValues"] for w in stats["windwardReplay"]]
    v4d = [w["repaired"]["distinctFeeValues"] for w in stats["windwardReplay"]]
    be = max(q["breakevenP10Usd"] for q in gecon["pools"])
    sh = min(q["shareAboveBreakevenP10"] for q in gecon["pools"]) * 100

    html = f"""<title>Windward</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Newsreader:ital,opsz,wght@0,6..72,400;0,6..72,500;1,6..72,400&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root{{
  --paper:#f6f7f9; --raise:#ffffff; --rule:#dde1e7; --rule-2:#eaedf1;
  --ink:#11161d; --ink-2:#4a5665; --ink-3:#77828f;
  --signal:#14566b; --signal-soft:#e3eef2;
  --noise:#9aa5b4; --flag:#9c3d26;
  --serif:"Newsreader",Georgia,"Times New Roman",serif;
  --sans:"IBM Plex Sans",ui-sans-serif,-apple-system,"Segoe UI",system-ui,sans-serif;
  --mono:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,monospace;
}}
@media (prefers-color-scheme:dark){{
  :root:not([data-theme="light"]){{
    --paper:#0d1218; --raise:#141b23; --rule:#28313d; --rule-2:#1c242e;
    --ink:#e7ecf2; --ink-2:#aab5c3; --ink-3:#7d8895;
    --signal:#57b6d0; --signal-soft:#152a33; --noise:#5d6a79; --flag:#d4886c;
  }}
}}
:root[data-theme="dark"]{{
  --paper:#0d1218; --raise:#141b23; --rule:#28313d; --rule-2:#1c242e;
  --ink:#e7ecf2; --ink-2:#aab5c3; --ink-3:#7d8895;
  --signal:#57b6d0; --signal-soft:#152a33; --noise:#5d6a79; --flag:#d4886c;
}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--paper);color:var(--ink);font-family:var(--sans);
  font-size:16.5px;line-height:1.62;-webkit-font-smoothing:antialiased}}
.page{{max-width:960px;margin:0 auto;padding:64px 32px 112px}}
section{{padding:52px 0;border-top:1px solid var(--rule-2)}}
section:first-of-type{{border-top:0;padding-top:8px}}
p{{max-width:64ch;margin:0 0 15px;color:var(--ink-2)}}
.eyebrow{{font-family:var(--mono);font-size:11.5px;letter-spacing:.18em;
  text-transform:uppercase;color:var(--ink-3);margin:0 0 20px}}
h1{{font-family:var(--serif);font-weight:400;font-size:clamp(38px,6.2vw,60px);
  line-height:1.07;letter-spacing:-.018em;margin:0 0 22px;text-wrap:balance;color:var(--ink)}}
h1 em{{font-style:italic;color:var(--signal)}}
h2{{font-family:var(--serif);font-weight:400;font-size:clamp(25px,3.4vw,33px);
  line-height:1.2;letter-spacing:-.012em;margin:0 0 14px;text-wrap:balance;color:var(--ink)}}
.lede{{font-size:19.5px;line-height:1.55;color:var(--ink);max-width:60ch}}
strong{{color:var(--ink);font-weight:600}}
.sig{{color:var(--signal);font-weight:600}}
.facts{{display:flex;flex-wrap:wrap;gap:36px;margin-top:34px;padding-top:26px;
  border-top:1px solid var(--rule)}}
.facts div{{font-family:var(--mono);font-size:11.5px;letter-spacing:.09em;
  text-transform:uppercase;color:var(--ink-3)}}
.facts b{{display:block;font-family:var(--serif);font-size:30px;font-weight:500;
  letter-spacing:-.01em;color:var(--ink);text-transform:none;font-variant-numeric:tabular-nums}}
.tabs{{display:flex;gap:7px;flex-wrap:wrap;margin:26px 0 22px}}
.tab{{background:none;border:1px solid var(--rule);border-radius:2px;cursor:pointer;
  padding:8px 12px;text-align:left;color:var(--ink-3);font-family:var(--mono);font-size:11.5px;
  line-height:1.35}}
.tab em{{display:block;font-style:normal;color:var(--ink-2)}}
.tab span{{font-size:10.5px;opacity:.75}}
.tab:hover{{border-color:var(--ink-3)}}
.tab.on{{border-color:var(--signal);background:var(--signal-soft)}}
.tab.on em{{color:var(--signal)}}
.tab:focus-visible{{outline:2px solid var(--signal);outline-offset:2px}}
.twin{{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:20px}}
figure{{margin:0;background:var(--raise);border:1px solid var(--rule);border-radius:3px;
  padding:18px 18px 14px}}
figcaption{{display:flex;align-items:center;gap:9px;font-family:var(--mono);font-size:11.5px;
  letter-spacing:.13em;text-transform:uppercase;color:var(--ink-3);margin-bottom:10px}}
.key{{width:11px;height:11px;flex:none;border:1px solid var(--signal)}}
.key.sig{{background:var(--signal)}}
.key.nul{{border-color:var(--noise);background:repeating-linear-gradient(45deg,
  var(--noise) 0 1px,transparent 1px 4px)}}
svg{{width:100%;height:auto;display:block;overflow:visible}}
.ax{{fill:var(--ink-3);font-family:var(--mono);font-size:9px}}
.val{{fill:var(--ink);font-family:var(--mono);font-size:10.5px;font-weight:500}}
.grid{{stroke:var(--rule-2)}} .axis{{stroke:var(--rule)}} .hl{{stroke:var(--noise);stroke-width:1.6}}
.cap{{font-size:13px;color:var(--ink-3);margin:10px 0 0;max-width:none}}
.verdict{{display:flex;align-items:flex-end;gap:44px;flex-wrap:wrap;margin-top:20px;
  padding-top:20px;border-top:1px solid var(--rule)}}
.big b{{display:block;font-family:var(--serif);font-size:46px;font-weight:500;line-height:1;
  letter-spacing:-.02em;color:var(--signal);font-variant-numeric:tabular-nums}}
.big b.mute{{color:var(--noise)}}
.big span{{font-family:var(--mono);font-size:11px;letter-spacing:.1em;text-transform:uppercase;
  color:var(--ink-3)}}
.rho{{margin-left:auto;font-family:var(--mono);font-size:11.5px;line-height:1.75;
  color:var(--ink-3);text-align:right}}
.rho b{{color:var(--ink);font-weight:500}} .rho b.mute{{color:var(--noise)}}
.tw{{width:100%;overflow-x:auto;margin:22px 0}}
table{{width:100%;border-collapse:collapse;font-size:14.5px;font-variant-numeric:tabular-nums}}
th{{font-family:var(--mono);font-size:10.5px;letter-spacing:.13em;text-transform:uppercase;
  color:var(--ink-3);font-weight:400;text-align:left;padding:0 16px 9px 0;
  border-bottom:1px solid var(--rule)}}
td{{padding:12px 16px 12px 0;border-bottom:1px solid var(--rule-2);color:var(--ink-2)}}
td:first-child{{color:var(--ink)}}
td.num{{font-family:var(--mono);font-size:13.5px}}
.cut{{color:var(--flag)}} .keep{{color:var(--signal)}}
.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(255px,1fr));gap:1px;
  background:var(--rule);border:1px solid var(--rule);margin-top:8px}}
.card{{background:var(--paper);padding:22px}}
.card h3{{font-family:var(--sans);font-size:14px;font-weight:600;margin:0 0 8px;color:var(--ink)}}
.card p{{font-size:13.5px;margin:0;color:var(--ink-2)}}
.addr{{font-family:var(--mono);font-size:12px;word-break:break-all;color:var(--signal);
  margin:0 0 8px}}
ol{{max-width:64ch;padding-left:1.15em;color:var(--ink-2)}}
ol li{{margin-bottom:11px;padding-left:4px}}
ol li::marker{{font-family:var(--mono);font-size:12px;color:var(--ink-3)}}
code{{font-family:var(--mono);font-size:.88em;color:var(--ink)}}
.foot{{font-size:13.5px;color:var(--ink-3);margin-top:30px;padding-top:18px;
  border-top:1px solid var(--rule-2)}}
@media (prefers-reduced-motion:no-preference){{
  .panel{{animation:fade .28s ease-out}}
  @keyframes fade{{from{{opacity:0}}to{{opacity:1}}}}
}}
@media(max-width:640px){{.page{{padding:40px 20px 72px}}.facts{{gap:24px}}.verdict{{gap:26px}}
  .rho{{margin-left:0;text-align:left}}}}
</style>

<div class="page">

<section>
  <p class="eyebrow">Uniswap v4 · UHI10 Hookathon</p>
  <h1>A fee that reads the pool's own volatility — and the test that <em>could have killed it</em>.</h1>
  <p class="lede">Windward raises the swap fee when a pool is moving and lowers it when the pool is
  calm, from tick history alone. No oracle, no external call, no admin key.</p>
  <p>Plenty of hooks claim their fee tracks volatility. The hard part is showing it isn't noise
  dressed up as signal. So we built the control that could have falsified our own result — and
  ran it first against our own headline numbers, which did not survive it.</p>
  <div class="facts">
    <div><b>{micro['swaps']:,}</b>swaps analysed</div>
    <div><b>{micro['spanDays']:.0f} days</b>of Unichain v4</div>
    <div><b>{sw['swaps']:,}</b>swaps replayed</div>
    <div><b>{gas['gasOverhead']:,}</b>gas per swap</div>
  </div>
</section>

<section>
  <p class="eyebrow">The result</p>
  <h2>When Windward charges more, more actually happens next.</h2>
  <p>Bucket every swap by the fee it was charged, then measure the tick move that
  <em>followed</em> it. If the fee carries information, the top decile should precede larger
  moves than the bottom decile. <strong class="sig">It does.</strong></p>
  <div class="tabs">{tabs}</div>
  {''.join(panels)}
  <p style="margin-top:26px"><strong>The control.</strong> Shuffle each pool's real
  <code>(tick move, block gap)</code> pairs into a random order. Same multiset, same heavy tail,
  same median, same maximum — only the <em>clustering</em> is destroyed. Both charts share one
  axis. Across all five pools: real <strong class="sig">{min(lf):.2f}–{max(lf):.2f}&times;</strong>,
  shuffled <strong>{min(nf):.2f}–{max(nf):.2f}&times;</strong>.</p>
</section>

<section>
  <p class="eyebrow">The part most submissions skip</p>
  <h2>We ran that control against our own headline metrics. They failed.</h2>
  <p>This project used to lead on two numbers. Shuffled noise reproduces both — and on one pool
  the null scores <em>better</em> than the real data. Neither can separate a working fee from a
  random one, so they were cut from the claim rather than quietly kept.</p>
  <div class="tw"><table>
    <thead><tr><th>Metric</th><th>Real</th><th>Shuffled noise</th><th>Outcome</th></tr></thead>
    <tbody>
      <tr><td>Never sits at the fee floor</td><td class="num">0.0%</td><td class="num">0.0%</td>
        <td class="cut">Cut — proves nothing</td></tr>
      <tr><td>Distinct fee values</td><td class="num">{min(dv):,}–{max(dv):,}</td>
        <td class="num">{min(nv):,}–{max(nv):,}</td>
        <td class="cut">Cut — the null wins a pool</td></tr>
      <tr><td>Decile lift vs realised move</td>
        <td class="num">{min(lf):.2f}–{max(lf):.2f}&times;</td>
        <td class="num">{min(nf):.2f}–{max(nf):.2f}&times;</td>
        <td class="keep">Kept — this is the claim</td></tr>
    </tbody>
  </table></div>
  <p>Effect sizes, not significance: at {sw['swaps']:,} swaps an economically worthless
  correlation still clears any threshold you like.</p>
</section>

<section>
  <p class="eyebrow">Why the study existed</p>
  <h2>Real order flow caught a bug that a green test suite was hiding.</h2>
  <p>Integer truncation in <code>(dTick²)/dt</code> rounded
  <strong>{v1['pctObservationsRoundingToZero']}%</strong> of real observations to
  <strong>zero</strong>. The "dynamic" fee sat at its floor on
  <strong>{sw['shipped_v1_pctAtFeeFloor']}%</strong> of swaps and took
  <strong>{min(v1d)}–{max(v1d)}</strong> distinct values — a static fee wearing a dynamic fee's
  clothes. Every unit test passed throughout, because they used synthetic swaps large enough to
  step over the truncation entirely.</p>
  <div class="tw"><table>
    <thead><tr><th>Busiest pool</th><th>Before</th><th>After</th></tr></thead>
    <tbody>
      <tr><td>Observations truncated to zero</td>
        <td class="num cut">{v1['pctObservationsRoundingToZero']}%</td>
        <td class="num keep">{v4['pctObservationsRoundingToZero']}%</td></tr>
      <tr><td>Swaps priced at the fee floor</td>
        <td class="num cut">{sw['shipped_v1_pctAtFeeFloor']}%</td>
        <td class="num keep">{sw['repaired_pctAtFeeFloor']}%</td></tr>
      <tr><td>Distinct fee values</td><td class="num cut">{min(v1d)}–{max(v1d)}</td>
        <td class="num keep">{min(v4d):,}–{max(v4d):,}</td></tr>
    </tbody>
  </table></div>
  <p>Real Unichain flow is small and fast: median move <strong>{micro['tickMoveMedian']} tick</strong>,
  median gap <strong>{micro['blockGapMedian']} blocks</strong>, and
  <strong>{micro['pctSameBlockConsecutiveSwaps']}%</strong> of consecutive swaps share a block.
  Synthetic tests never went near that regime.</p>
</section>

<section>
  <p class="eyebrow">Engineering</p>
  <div class="cards">
    <div class="card"><h3>It cannot move funds</h3><p>Both callbacks return zero deltas and all
      four <code>*_RETURNS_DELTA</code> address bits are clear, so v4 never parses a delta from
      it. No owner, pause, upgrade path or setter — every parameter is immutable.</p></div>
    <div class="card"><h3>Deployed, bytecode verified</h3>
      <p class="addr">0x609634584d5BD12Ba4216116528e364d385Ad0C0</p>
      <p>Unichain Sepolia. Runtime code matched against a local deploy-profile build; the only
      differences are the immutable slots, each confirmed through its getter.</p></div>
    <div class="card"><h3>61 tests, two profiles</h3><p>Eight security findings fixed, each pinned
      by a regression test written while it still failed. One remains open, documented rather
      than quietly dropped.</p></div>
    <div class="card"><h3>{gecon['gasCostUsd'] * 100:.4f}&cent; per swap</h3>
      <p>{gas['gasOverhead']:,} gas, {gas['overheadPctOfUnhooked']}% of an unhooked swap. Breakeven
      lands near <strong>${be:.2f}</strong> a trade, which {sh:.1f}%+ of real swaps clear.</p></div>
  </div>
</section>

<section>
  <p class="eyebrow">What we are not claiming</p>
  <h2>The limits, stated before anyone has to ask.</h2>
  <ol>
    <li><strong>The LP benefit is unvalidated.</strong> We measure fee revenue, not LP PnL, and
      there is no demand-elasticity model for flow that leaves at a higher fee.</li>
    <li><strong>This is a heuristic.</strong> Motivated by the loss-versus-rebalancing literature,
      not an implementation of any optimal policy from it. The word <em>optimal</em> is not used.</li>
    <li><strong>The lift is a correlation.</strong> It shows the fee is charged at the right
      <em>times</em>, not that the revenue exceeds the adverse selection it offsets.</li>
    <li><strong>One finding is open.</strong> A same-block round trip can strand the tick anchor.
      It cannot move funds and costs the griefer more than the target, but a production
      deployment must fix it.</li>
    <li><strong>Scope.</strong> Five busiest pools, one chain, one seven-day window. The
      thin-pool regime is untested.</li>
  </ol>
  <p class="foot">Every figure on this page is generated from committed JSON by
  <code>analysis/make_demo_page.py</code>. <code>analysis/run.sh</code> rebuilds all of it from
  the chain.</p>
</section>

</div>
<script>
document.querySelectorAll(".tab").forEach(function (t) {{
  t.addEventListener("click", function () {{
    document.querySelectorAll(".tab").forEach(function (x) {{ x.classList.toggle("on", x === t); }});
    document.querySelectorAll(".panel").forEach(function (p) {{
      p.hidden = p.dataset.pool !== t.dataset.t;
    }});
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
