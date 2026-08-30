type Props = {
  series: number[];
  yMax: number;
  variant: "signal" | "noise";
  label: string;
  caption: string;
};

/**
 * Decile columns. Both charts on the page receive the same `yMax` — a chart rescaled to its own
 * data would flatter the null and hide the effect, which is the one thing this page must not do.
 * The null series is hatched rather than merely tinted so it reads as noise before the numbers do.
 */
export default function BarChart({ series, yMax, variant, label, caption }: Props) {
  const W = 380;
  const H = 220;
  const padL = 32;
  const padB = 30;
  const padT = 20;
  const slot = (W - padL - 12) / series.length;
  const bw = slot * 0.64;
  const stroke = variant === "signal" ? "var(--signal)" : "var(--noise)";
  const fill = variant === "signal" ? "var(--signal)" : "url(#hatch)";

  return (
    <figure className="fig">
      <figcaption>
        <span className={`key ${variant}`} aria-hidden="true" />
        {label}
      </figcaption>
      <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`${label}: ${caption}`}>
        <defs>
          <pattern
            id="hatch"
            width="5"
            height="5"
            patternUnits="userSpaceOnUse"
            patternTransform="rotate(45)"
          >
            <line x1="0" y1="0" x2="0" y2="5" stroke="var(--noise)" strokeWidth="1.7" />
          </pattern>
        </defs>

        {[1, 2, 3, 4].map((g) => {
          const y = H - padB - (g / 4) * (H - padB - padT);
          return (
            <g key={g}>
              <line x1={padL} y1={y} x2={W - 6} y2={y} stroke="var(--rule-2)" />
              <text x={padL - 7} y={y + 3.5} textAnchor="end" className="axis-t">
                {((g / 4) * yMax).toFixed(0)}
              </text>
            </g>
          );
        })}

        {series.map((v, i) => {
          const h = Math.max(2, (v / yMax) * (H - padB - padT));
          const x = padL + i * slot + (slot - bw) / 2;
          const y = H - padB - h;
          const edge = i === 0 || i === series.length - 1;
          return (
            <g key={i}>
              <rect x={x} y={y} width={bw} height={h} fill={fill} stroke={stroke} strokeWidth="1" />
              {edge && (
                <text x={x + bw / 2} y={y - 7} textAnchor="middle" className="axis-v">
                  {v}
                </text>
              )}
              <text x={x + bw / 2} y={H - padB + 15} textAnchor="middle" className="axis-t">
                {i + 1}
              </text>
            </g>
          );
        })}
        <line x1={padL} y1={H - padB} x2={W - 6} y2={H - padB} stroke="var(--rule)" />
      </svg>
      <p className="cap">{caption}</p>
    </figure>
  );
}
