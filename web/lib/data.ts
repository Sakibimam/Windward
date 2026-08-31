/**
 * The study's numbers, read from the JSON that `analysis/` generates.
 *
 * Nothing on this site is typed by hand. `scripts/sync-data.mjs` copies data/*.json in before
 * every dev run and build, so the site cannot drift from the analysis (DECISIONS.md D-0017).
 */
import economics from "@/data/economics.json";
import stats from "@/data/stats.json";
import gasOverhead from "@/data/gas_overhead.json";
import gasEconomics from "@/data/gas_economics.json";
import staleness from "@/data/staleness.json";

export type Decile = {
  decile: number;
  feeMin: number;
  feeMax: number;
  meanForwardMove: number;
  medianForwardMove: number;
  p90ForwardMove: number;
  n: number;
};

export type Pool = {
  pool: string;
  swaps: number;
  observations: number;
  liftDecile10OverDecile1: number;
  liftDecile10OverDecile1_shuffledNull: number;
  real: { spread: Spread; spearmanFeeVsForwardVariance: number; decileLift: Decile[] };
  shuffledNull: { spread: Spread; spearmanFeeVsForwardVariance: number; decileLift: Decile[] };
};

type Spread = {
  pctAtFeeFloor: number;
  distinctFeeValues: number;
  feeMedian: number;
  feeP90: number;
};

export const pools = economics.pools as unknown as Pool[];
export const micro = stats.microstructure;
export const swapWeighted = stats.windwardReplaySwapWeighted;
export const replay = stats.windwardReplay;
export const gas = gasOverhead;
export const gasEcon = gasEconomics;

const lifts = pools.map((p) => p.liftDecile10OverDecile1);
const nulls = pools.map((p) => p.liftDecile10OverDecile1_shuffledNull);
const distinctReal = pools.map((p) => p.real.spread.distinctFeeValues);
const distinctNull = pools.map((p) => p.shuffledNull.spread.distinctFeeValues);

export const range = (xs: number[]) => [Math.min(...xs), Math.max(...xs)] as const;
export const liftRange = range(lifts);
export const nullLiftRange = range(nulls);
export const distinctRealRange = range(distinctReal);
export const distinctNullRange = range(distinctNull);

/** Shared y-axis across both charts. Rescaling each to its own data would hide the effect. */
export const yMax =
  Math.max(
    ...pools.flatMap((p) => [
      ...p.real.decileLift.map((d) => d.meanForwardMove),
      ...p.shuffledNull.decileLift.map((d) => d.meanForwardMove),
    ]),
  ) * 1.12;

export const v1 = replay[0].shipped_v1;
export const v4 = replay[0].repaired;
export const v1Distinct = range(replay.map((r) => r.shipped_v1.distinctFeeValues));
export const v4Distinct = range(replay.map((r) => r.repaired.distinctFeeValues));
export const breakeven = Math.max(...gasEcon.pools.map((p) => p.breakevenP10Usd));
export const shareAbove = Math.min(...gasEcon.pools.map((p) => p.shareAboveBreakevenP10)) * 100;

/** The two signals that failed, and the one that survived. */
export const stalePools = staleness.pools;
export const staleLift = range(stalePools.map((p) => p.liftDecile10OverDecile1));
export const staleNull = range(stalePools.map((p) => p.liftDecile10OverDecile1_shuffledNull));
export const priority = stats.priorityFee;
export const retailTip = priority.groups[0].median;
export const arbTip = priority.groups[2].median;
export const arbN = priority.groups[2].n;
export const tipRatio = priority.retail_over_C2_median_ratio;
export const pctArbBelowRetail = priority.pct_C2_below_retail_median;
export const pctFirstOfBlock = micro.pctSwapsFirstOfBlockForTheirPool;

export const fmt = (n: number) => n.toLocaleString("en-US");
