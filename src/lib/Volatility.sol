// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Volatility
/// @notice Time-decayed realised-variance estimator over Uniswap v4 tick observations.
///
/// @dev **What this measures, precisely.** A Uniswap tick is defined by
/// `price = 1.0001^tick`, so `d(ln price) = d(tick) * ln(1.0001)` with
/// `ln(1.0001) = 9.9995e-5`. A tick delta is therefore a log return scaled by ~1e-4.
/// `sigmaWad()` returns **ticks per sqrt(second)**, NOT log-return per sqrt(second) — they
/// differ by that ~1e-4 factor, which is absorbed into the caller's `feePerSigma`
/// constant. Nothing here is annualised.
///
/// **This is a heuristic, not an optimal fee.** It is motivated by the observation that
/// loss-versus-rebalancing grows with price variance, but no claim is made that this
/// estimator, or any mapping from it to a fee, is optimal in the sense of the
/// stochastic-control literature. Those models assume an exogenous efficient price under
/// continuous arbitrage; this measures the realised variance of the pool price, which is a
/// different object. See docs/WINDWARD_DESIGN.md.
///
/// **Decay is a function of elapsed TIME, not of observation count.** An earlier version
/// decayed once per observation, which let a trader wash the estimate back to its floor
/// with dust swaps in a single block (20x fee suppression, demonstrated in
/// `test/WindwardAttack.t.sol`) and left a pool pinned at its ceiling indefinitely once it
/// stopped trading. Both are closed by making the weight depend on `dt`.
library Volatility {
    /// @dev Fixed-point scale for the variance, the decay factor and sigma. 1e18.
    uint256 internal constant WAD = 1e18;

    /// @dev Elapsed time is capped before use. Beyond this the decay factor is
    /// indistinguishable from zero anyway, and the cap keeps the shift bounded.
    uint256 internal constant MAX_DT = 7 days;

    /// @dev Upper bound on a single observation, in tick^2 per second.
    ///
    /// A swap can cross the entire curve, so `dTick^2` is bounded only by ~3.15e12 (the
    /// full tick range squared). This cap sits deliberately far BELOW that: 1e8 is a
    /// ~10,000-tick (2.7x price) move in one second, outside anything legitimate, while
    /// still bounding how long a single crafted swap can dominate the estimate. An
    /// earlier cap of 1e12 was inert — it sat above every reachable move, so it bounded
    /// nothing at all.
    uint256 internal constant MAX_OBSERVATION = 1e8;

    /// @notice Folds one observation into a time-decayed EWMA variance.
    ///
    /// @dev `varNew = w*varOld + (1-w)*observation` where `w = 2^(-dt/halfLife)`.
    ///
    /// **`dt == 0` returns the previous variance unchanged, and the caller MUST NOT
    /// advance its stored tick/timestamp.** No time has elapsed, so there is no
    /// variance-per-unit-time to measure. Leaving the anchor in place means a move split
    /// into same-block slices is not erased — it is measured in full against the next
    /// observation that does have elapsed time. This is what closes the dust-swap
    /// suppression attack: same-block swaps cannot move the estimate at all.
    ///
    /// @param varianceWad Previous variance, WAD-scaled, in tick^2 per second.
    /// @param tickBefore  Tick at the previous timestamped observation.
    /// @param tickAfter   Tick now.
    /// @param dt          Seconds since the previous timestamped observation.
    /// @param halfLife    Seconds over which an old estimate loses half its weight.
    function update(uint256 varianceWad, int24 tickBefore, int24 tickAfter, uint256 dt, uint256 halfLife)
        internal
        pure
        returns (uint256 newVarianceWad)
    {
        if (dt == 0) return varianceWad;
        if (dt > MAX_DT) dt = MAX_DT;

        // |int24 - int24| <= 2^25, so sq <= 2^50; sq * WAD <= ~1.1e33. No overflow.
        int256 diff = int256(tickAfter) - int256(tickBefore);
        uint256 absDiff = uint256(diff < 0 ? -diff : diff);
        uint256 sq = absDiff * absDiff;

        // WAD scaling is applied BEFORE the division so the quotient keeps its fraction.
        // Dividing first truncated every observation with dTick^2 < dt to zero, which on
        // real Unichain flow was 52-85% of them, pinning the fee at its floor.
        uint256 observationWad = (sq * WAD) / dt;
        uint256 capWad = MAX_OBSERVATION * WAD;
        if (observationWad > capWad) observationWad = capWad;

        uint256 w = decayFactor(dt, halfLife);

        // Rounds DOWN. A truncated estimate biases the fee toward the swapper, which is
        // the safer direction: a fee slightly too low costs LPs a little revenue, whereas
        // a fee too high prices honest flow out of the pool entirely.
        newVarianceWad = (w * varianceWad + (WAD - w) * observationWad) / WAD;
    }

    /// @notice `2^(-dt/halfLife)`, WAD-scaled, in [0, WAD].
    /// @dev Exact halvings for the integer part, linear interpolation across the
    /// remainder. The interpolation understates the true exponential by at most ~6% of
    /// the factor — immaterial for a heuristic — and is monotone non-increasing in `dt`,
    /// which is the property that matters: a longer gap can never retain more weight.
    function decayFactor(uint256 dt, uint256 halfLife) internal pure returns (uint256) {
        if (halfLife == 0) return 0;
        uint256 n = dt / halfLife;
        if (n >= 64) return 0; // 2^-64 is zero at WAD precision
        uint256 w = WAD >> n;
        uint256 rem = dt % halfLife;
        if (rem != 0) {
            // Interpolate from w down toward w/2 across the partial half-life.
            w -= (w * rem) / (2 * halfLife);
        }
        return w;
    }

    /// @notice sigma, WAD-scaled, in ticks per sqrt(second).
    /// @dev `sqrt(varianceWad * WAD) == sigma * WAD` exactly. Computing
    /// `sqrt(varianceWad / WAD)` instead truncated twice and quantised the fee onto a
    /// ladder whose first rung was 40% of the entire fee floor.
    /// Max input: MAX_OBSERVATION * WAD * WAD = 1e44, well inside uint256.
    function sigmaWad(uint256 varianceWad) internal pure returns (uint256) {
        return sqrt(varianceWad * WAD);
    }

    /// @notice Integer square root. Returns floor(sqrt(x)) for every uint256.
    ///
    /// @dev Babylonian iteration. The initial guess is `2^floor((bitlen-1)/2)`, which is at
    /// or BELOW sqrt(x) — never above it — so the first step overshoots and the sequence
    /// descends from there. An earlier comment claimed the guess was an upper bound and
    /// that convergence was monotone downward throughout; both statements were false,
    /// though the function was correct regardless.
    ///
    /// Correctness: the initial relative error is at most 2x, so after one step it is at
    /// most 1/4, and Newton squares the error each step (2^-2 -> 2^-4 -> ... -> 2^-128
    /// after six further steps), below one ULP for any sqrt(x) < 2^128. The final
    /// `min(y, x/y)` resolves the known s <-> s+1 oscillation.
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = x;
        y = 1;
        if (z >= 0x100000000000000000000000000000000) {
            z >>= 128;
            y <<= 64;
        }
        if (z >= 0x10000000000000000) {
            z >>= 64;
            y <<= 32;
        }
        if (z >= 0x100000000) {
            z >>= 32;
            y <<= 16;
        }
        if (z >= 0x10000) {
            z >>= 16;
            y <<= 8;
        }
        if (z >= 0x100) {
            z >>= 8;
            y <<= 4;
        }
        if (z >= 0x10) {
            z >>= 4;
            y <<= 2;
        }
        if (z >= 0x4) {
            y <<= 1;
        }

        unchecked {
            y = (y + x / y) >> 1;
            y = (y + x / y) >> 1;
            y = (y + x / y) >> 1;
            y = (y + x / y) >> 1;
            y = (y + x / y) >> 1;
            y = (y + x / y) >> 1;
            y = (y + x / y) >> 1;
            uint256 yd = x / y;
            if (y > yd) y = yd;
        }
    }
}
