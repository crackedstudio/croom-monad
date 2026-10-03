// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {FixedPointMath as F} from "./FixedPointMath.sol";
import {InverseNormal} from "./InverseNormal.sol";
import {RoomSpec} from "./RoomSpec.sol";

/// @title Tick
/// @notice The deterministic map from `(spec, beacon value)` to the next price. Pure: no storage,
/// no timestamps, no block data, no chain state. Ported from `croom-core`'s `model.rs` and
/// `derive.rs`; normative definition in `docs/core-v1.md` §2, §5, §6.
///
/// Two families ship on EVM — **Drift** and **Step**. The reference implements all eight; see
/// `docs/decisions/0002-scope.md`.
///
/// This library is the conformance surface and the fraud proof's terminal step: when a dispute
/// narrows to one tick, the contract runs exactly this and pays the bond to whoever was right. So
/// every rounding here is copied from the reference rather than reasoned about.
library Tick {
    /// @dev Streams are domain separators, one byte each. Only `DIFFUSION` is reached by the two
    /// families we ship; the rest are listed because the byte values are frozen and a future
    /// family must not renumber them.
    uint8 internal constant STREAM_DIFFUSION = 0;
    uint8 internal constant STREAM_JUMP_OCCUR = 1;
    uint8 internal constant STREAM_JUMP_SIZE = 2;
    uint8 internal constant STREAM_REGIME = 3;
    uint8 internal constant STREAM_DIGIT = 4;
    uint8 internal constant STREAM_JACKPOT = 5;

    /// @dev Eight ASCII bytes, no length prefix.
    bytes8 internal constant DOMAIN = "CROOM/v1";

    int256 internal constant SECONDS_PER_YEAR = 31_536_000;
    int256 internal constant ROUND_SECONDS_WAD = 3 * F.WAD;

    /// @dev 10^-18 and 10^20. Unreachable in practice; they exist so the transition is total.
    int256 internal constant PRICE_MIN = 1;
    int256 internal constant PRICE_MAX = 100_000_000_000_000_000_000 * F.WAD;
    int256 internal constant LN_PRICE_MAX = 46_051_701_859_880_913_680;

    error UnsupportedFamily(uint8 family);

    /// @notice A spec compiled into the constants each tick needs. Deterministic, and part of the
    /// definition rather than an optimisation — the reference computes these once per Room and the
    /// truncation in each one is observable in the output.
    struct Model {
        uint8 family;
        bytes32 roomId;
        uint8 subTicks;
        int256 sigmaT; // Drift
        int256 varHalf; // Drift
        int256 step; // Step
    }

    /// @notice Compiles a spec into its derived constants.
    /// @dev `dt = 3·WAD / (k·Y)`, truncated, then `√dt`, then `σ_t = σ·√dt` and
    /// `var_half = σ_t²/2`. Note `k` divides: a Room with two sub-ticks per round has each
    /// sub-tick spanning half the time, so its per-sub-tick volatility is lower.
    function compile(
        RoomSpec.Spec memory s
    ) internal pure returns (Model memory m) {
        m.family = s.family;
        m.roomId = RoomSpec.roomId(s);
        m.subTicks = s.subTicks;

        int256 dt = F.divInt(ROUND_SECONDS_WAD, int256(uint256(s.subTicks)) * SECONDS_PER_YEAR);
        int256 sqrtDt = F.sqrtWad(dt);

        if (s.family == RoomSpec.FAMILY_DRIFT) {
            m.sigmaT = F.mulWad(s.param, sqrtDt);
            m.varHalf = F.divInt(F.mulWad(m.sigmaT, m.sigmaT), 2);
        } else if (s.family == RoomSpec.FAMILY_STEP) {
            m.step = s.param;
        } else {
            revert UnsupportedFamily(s.family);
        }
    }

    /// @notice `u(R, roomId, j, stream)` — the full 32-byte derived value.
    /// @dev The round number is **not** hashed. It enters through `R`, which is already unique per
    /// round. Chain ID is never hashed, which is what lets a Room produce identical prices on
    /// every host chain.
    function derive(
        bytes32 r,
        bytes32 roomId,
        uint8 subTick,
        uint8 stream
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(DOMAIN, r, roomId, subTick, stream));
    }

    /// @notice A uniform draw in WAD, `1 <= U <= WAD - 1`.
    /// @dev Top 64 bits of the derived value, scaled by `WAD / 2^64`, floored at 1. The floor is
    /// load-bearing: `Φ⁻¹(0)` is undefined, so a zero draw would take the inverse normal outside
    /// its domain. The upper end needs no clamp — the maximum is `WAD - 1`.
    function uniformWad(
        bytes32 r,
        bytes32 roomId,
        uint8 subTick,
        uint8 stream
    ) internal pure returns (int256) {
        return F.u64ToWad(uint256(derive(r, roomId, subTick, stream)) >> 192);
    }

    /// @notice One sub-tick. Returns the price after it.
    function stepOnce(
        Model memory m,
        int256 price,
        bytes32 r,
        uint8 subTick
    ) internal pure returns (int256) {
        int256 u = uniformWad(r, m.roomId, subTick, STREAM_DIFFUSION);

        if (m.family == RoomSpec.FAMILY_DRIFT) {
            return _diffuse(m, price, InverseNormal.invPhiWad(u));
        }
        if (m.family == RoomSpec.FAMILY_STEP) {
            // The floor is the step size itself, not a spec field. A Room that could reach zero
            // would be absorbing: truncation pins it there and the market dies silently.
            return u < F.HALF_WAD ? _clampPrice(price + m.step) : _max(price - m.step, m.step);
        }
        revert UnsupportedFamily(m.family);
    }

    /// @notice A whole round: every sub-tick, with the high and low across them.
    /// @dev High and low are tracked because a path-dependent payoff asks whether a barrier was
    /// touched *during* the round, not only where it closed. They start at the incoming price, so
    /// a round that only moves one way still reports the open as one extreme.
    function deriveRound(
        Model memory m,
        int256 price,
        bytes32 r
    ) internal pure returns (int256 close, int256 high, int256 low) {
        high = price;
        low = price;
        for (uint8 j = 0; j < m.subTicks; j++) {
            price = stepOnce(m, price, r, j);
            if (price > high) high = price;
            if (price < low) low = price;
        }
        close = price;
    }

    /// @dev `exp(clampLn(ln(P) − var_half + σ_t·Z))`, clamped. The subtraction of `var_half` is
    /// the martingale correction: without it a symmetric shock drifts the price upward forever,
    /// because the average of multiplying by `u` or by `1/u` always exceeds one. See
    /// `math_breakdown.md` §7.
    ///
    /// The association is copied exactly: `((ln P − var_half) + σ_t·Z)`. Addition is exact, so the
    /// order of the sum does not matter, but the single truncation inside `σ_t·Z` does.
    function _diffuse(
        Model memory m,
        int256 price,
        int256 z
    ) private pure returns (int256) {
        int256 lnNew = (F.lnWad(price) - m.varHalf) + F.mulWad(m.sigmaT, z);
        return _clampPrice(F.expWad(_clampLn(lnNew)));
    }

    function _clampPrice(
        int256 p
    ) private pure returns (int256) {
        if (p < PRICE_MIN) return PRICE_MIN;
        if (p > PRICE_MAX) return PRICE_MAX;
        return p;
    }

    function _clampLn(
        int256 x
    ) private pure returns (int256) {
        if (x < F.EXP_MIN_INPUT) return F.EXP_MIN_INPUT;
        if (x > LN_PRICE_MAX) return LN_PRICE_MAX;
        return x;
    }

    function _max(
        int256 a,
        int256 b
    ) private pure returns (int256) {
        return a > b ? a : b;
    }
}
