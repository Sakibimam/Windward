/**
 * One swap, left to right.
 *
 * The docs page described the mechanism as a three-row table, which says what each stage does but
 * not who calls whom or where the hook sits. This draws the same sequence the README's diagram
 * shows, so a reader can see that both hook calls happen inside a single transaction and that the
 * only stored state is one number per pool.
 *
 * The arrows carry numbers rather than sentences: seven captions at this width collided into each
 * other, and a numbered key beside the drawing stays readable at any size.
 */

const W = 648;
const H = 210;

const LANES = [
  { y: 26, label: "Trader" },
  { y: 84, label: "PoolManager" },
  { y: 146, label: "WindwardHook" },
  { y: 190, label: "Stored number" },
];

type Step = { n: number; from: number; to: number; x: number; dashed?: boolean; self?: boolean };

const STEPS: Step[] = [
  { n: 1, from: 0, to: 1, x: 150 },
  { n: 2, from: 1, to: 2, x: 206 },
  { n: 3, from: 2, to: 3, x: 252 },
  { n: 4, from: 3, to: 2, x: 292, dashed: true },
  { n: 5, from: 2, to: 1, x: 340, dashed: true },
  { n: 6, from: 1, to: 1, x: 398, self: true },
  { n: 7, from: 1, to: 2, x: 500 },
  { n: 8, from: 2, to: 3, x: 566 },
];

const KEY = [
  "The trader sends a swap through a v4 router.",
  "Before touching the price, v4 calls beforeSwap.",
  "The hook reads the one number it stores for this pool.",
  "That number comes back, and the hook ages it forward to now.",
  "It takes the square root, clamps the result, and returns the fee for this swap only.",
  "v4 runs the swap, charging exactly that.",
  "v4 calls afterSwap, carrying the price the swap ended at.",
  "The hook folds the move back into its stored number, ready for the next trade.",
];

export default function Lifecycle() {
  return (
    <div className="lifecycle">
      <div className="lc-draw">
        <svg viewBox={`0 0 ${W} ${H}`} role="img"
          aria-label="One swap: a trader calls the PoolManager, which calls the hook before and after the swap. The hook reads and writes a single stored number per pool.">
          <defs>
            <marker id="lcA" viewBox="0 0 8 8" refX="7" refY="4"
              markerWidth="5.5" markerHeight="5.5" orient="auto-start-reverse">
              <path d="M0,0 L8,4 L0,8 z" fill="var(--fg-3)" />
            </marker>
            <marker id="lcS" viewBox="0 0 8 8" refX="7" refY="4"
              markerWidth="5.5" markerHeight="5.5" orient="auto-start-reverse">
              <path d="M0,0 L8,4 L0,8 z" fill="var(--signal)" />
            </marker>
          </defs>

          <rect x={184} y={12} width={W - 194} height={H - 26}
            fill="var(--signal)" opacity="0.03" rx="5" />
          <text x={188} y={8} className="lc-note">one transaction</text>

          {LANES.map((l, i) => (
            <g key={l.label}>
              <line x1={118} y1={l.y} x2={W - 10} y2={l.y}
                stroke={i === 2 ? "var(--signal-dim)" : "var(--rule-2)"} />
              <text x={110} y={l.y + 3.5} textAnchor="end"
                className={i === 2 ? "lc-lane lc-lane-on" : "lc-lane"}>{l.label}</text>
            </g>
          ))}

          {STEPS.map((s) => {
            const y1 = LANES[s.from].y;
            const y2 = LANES[s.to].y;
            const hookish = s.from === 3 || s.to === 3;
            const stroke = hookish ? "var(--signal)" : "var(--fg-3)";
            const mid = s.self ? y1 + 20 : (y1 + y2) / 2;
            return (
              <g key={s.n}>
                {s.self ? (
                  <path d={`M${s.x},${y1} q22,0 22,14 q0,14 -22,14`} fill="none"
                    stroke={stroke} markerEnd="url(#lcA)" />
                ) : (
                  <line x1={s.x} y1={y1} x2={s.x} y2={y2} stroke={stroke}
                    strokeDasharray={s.dashed ? "3 3" : undefined}
                    markerEnd={hookish ? "url(#lcS)" : "url(#lcA)"} />
                )}
                <circle cx={s.x} cy={y1} r="2.5" fill={stroke} />
                <circle cx={s.x + (s.self ? 30 : 0)} cy={mid} r="8"
                  fill="var(--ink)" stroke={stroke} strokeWidth="1" />
                <text x={s.x + (s.self ? 30 : 0)} y={mid + 3.2} textAnchor="middle"
                  className="lc-num">{s.n}</text>
              </g>
            );
          })}
        </svg>
      </div>

      <ol className="lc-key">
        {KEY.map((k, i) => (
          <li key={i}><b>{i + 1}</b><span>{k}</span></li>
        ))}
      </ol>
    </div>
  );
}
