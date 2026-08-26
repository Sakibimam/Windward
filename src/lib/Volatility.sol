// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Volatility
/// @notice Exponentially-weighted realised-variance estimator over Uniswap v4 tick observations.
///
/// @dev Windward needs a volatility estimate that is (a) computable from the pool's own state,
/// (b) cheap enough to update on every swap, and (c) impossible for a counterparty to forge.
/// Ticks satisfy all three: they are written by the PoolManager, and one tick is one basis point
/// of price, so a tick delta is already a natural log-return in bps.
///
/// The estimator is a standard EWMA of squared tick returns normalised by elapsed time:
///
///     varNew = alpha * (dTick^2 / dt) + (1 - alpha) * varOld
///
/// `sigma = sqrt(var)` then has units of ticks per sqrt(second), i.e. bps per sqrt(second),
/// which is exactly the quantity the LVR literature scales the optimal fee by.
library Volatility {
    /// @dev Fixed-point scale for `alpha` and for the stored variance. 1e18 throughout.
    uint256 internal constant WAD = 1e18;

    /// @dev Elapsed time is clamped into [MIN_DT, MAX_DT] seconds before dividing.
    ///
    /// MIN_DT stops a same-second burst of swaps from dividing by zero, and — more importantly —
    /// from producing an unbounded variance spike that an attacker could use to drive the fee to
    /// its ceiling and grief honest swappers. MAX_DT stops a long quiet period from decaying a
    /// genuine variance estimate to zero in a single step.
    uint256 internal constant MIN_DT = 1;
    uint256 internal constant MAX_DT = 3600;

    /// @dev Per-observation cap on squared return, in tick^2 per second. A single swap may move
    /// the tick arbitrarily far (a swap can cross the whole curve), so without this cap one
    /// crafted swap could dominate the EWMA for a long time. 1e12 corresponds to a ~1e6-tick
    /// move in one second, far beyond any legitimate price change.
    uint256 internal constant MAX_OBSERVATION = 1e12;

    /// @notice Folds one observation into an EWMA variance.
    /// @param varianceWad Previous variance estimate, WAD-scaled, in tick^2 per second.
    /// @param tickBefore  Pool tick at the previous observation.
    /// @param tickAfter   Pool tick now.
    /// @param dt          Seconds elapsed since the previous observation.
    /// @param alphaWad    Smoothing factor in (0, WAD]. Larger reacts faster.
    /// @return newVarianceWad Updated variance estimate, WAD-scaled.
    function update(uint256 varianceWad, int24 tickBefore, int24 tickAfter, uint256 dt, uint256 alphaWad)
        internal
        pure
        returns (uint256 newVarianceWad)
    {
        if (dt < MIN_DT) dt = MIN_DT;
        if (dt > MAX_DT) dt = MAX_DT;

        // int24 subtraction cannot overflow int256, and the absolute value of the difference of
        // two int24 values is at most 2^24, so `sq` is at most 2^48 and the WAD scaling below
        // cannot overflow uint256.
        int256 diff = int256(tickAfter) - int256(tickBefore);
        uint256 absDiff = uint256(diff < 0 ? -diff : diff);
        uint256 sq = absDiff * absDiff;

        // Rounds DOWN. Under-stating an observation biases the fee downward, which favours the
        // swapper over the LP. That is the conservative direction for a guard that can otherwise
        // only make swaps more expensive: a fee that is too low costs LPs some revenue, whereas a
        // fee that is too high can price honest flow out of the pool entirely.
        uint256 observation = sq / dt;
        if (observation > MAX_OBSERVATION) observation = MAX_OBSERVATION;

        // varNew = alpha * observation + (1 - alpha) * varOld, all WAD-scaled.
        //
        // `observation` is a raw integer (tick^2 per second); its WAD-scaled form is
        // `observation * WAD`. The weighted term is therefore
        //     (observation * WAD) * alphaWad / WAD  ==  observation * alphaWad
        // which is what is written below. Writing it as `observation * alphaWad / WAD` would
        // divide by WAD once too often and leave the result unscaled, which makes `sigma()`
        // — which divides by WAD again — return 0 for every realistic observation.
        //
        // Overflow: observation <= MAX_OBSERVATION (1e12) and alphaWad <= WAD (1e18), so the
        // product is at most 1e30, far below uint256 max.
        //
        // Rounds DOWN on the decay term, same rationale as above.
        uint256 weighted = observation * alphaWad;
        uint256 decayed = (varianceWad * (WAD - alphaWad)) / WAD;
        newVarianceWad = weighted + decayed;
    }

    /// @notice Converts a WAD-scaled variance into sigma, in ticks per sqrt(second).
    /// @dev Rounds DOWN (integer sqrt truncates), again biasing the fee low.
    function sigma(uint256 varianceWad) internal pure returns (uint256) {
        return sqrt(varianceWad / WAD);
    }

    /// @notice Integer square root, Babylonian method. Returns floor(sqrt(x)).
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        // Initial guess: 2^(ceil(bitlen/2)) is always >= sqrt(x), which guarantees the
        // Babylonian iteration converges monotonically downward to floor(sqrt(x)).
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
        if (z >= 0x4) y <<= 1;

        // Seven iterations are sufficient for a 256-bit input from this starting point.
        // Each step is exact integer arithmetic; no overflow is possible because y <= x.
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
