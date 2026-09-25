// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @title FixedPointMath
/// @notice 18-decimal fixed point on `i128`, ported from `croom-core`'s `fixed.rs`.
///
/// This is a **port of a frozen reference**, not a design. Every definition here is transcribed
/// from `reference/croom-core/docs/core-v1.md` §1 and checked against the 7,253 cases in
/// `vectors/maths.json`. Where this disagrees with the vectors, this is wrong.
///
/// # Two things Solidity does not give us for free
///
/// **The reference is `i128`.** Rust gets the bound from the type system; we hold values in
/// `int256` and must check. Two `i128` operands multiply to at most 2^254, so the product fits
/// `int256` exactly and no 512-bit `mulDiv` is needed — but a result outside `i128` is an *error*
/// in the reference, and `int256` would carry it silently. Every result is therefore bounded.
///
/// **Truncation and floor are both used.** `/` truncates toward zero in Solidity, which is right
/// for `mulDiv` and friends. `expWad` needs a genuine floor on a possibly-negative value, so it
/// gets an explicit helper — without it, `expWad` diverges for every negative input, which is half
/// of them. See `docs/porting-notes.md` §2.
library FixedPointMath {
    int256 internal constant WAD = 1e18;
    /// @dev The same constant unsigned, so the magnitude paths need no casts of their own.
    uint256 internal constant WAD_U = 1e18;
    int256 internal constant HALF_WAD = 5e17;

    /// @dev ln 2, truncated to 18 decimals.
    int256 internal constant LN2_WAD = 693_147_180_559_945_309;
    /// @dev e^46.5 is the largest exponential that fits; above this is an error, not a saturation.
    int256 internal constant EXP_MAX_INPUT = 46_500_000_000_000_000_000;
    /// @dev ln(10^-18) truncated. Below this, `expWad` is exactly zero.
    int256 internal constant EXP_MIN_INPUT = -41_446_531_673_892_822_312;

    int256 internal constant INT128_MAX = type(int128).max;
    int256 internal constant INT128_MIN = type(int128).min;

    /// @dev Largest input to `sqrtWad`: `x · WAD` must still fit in 128 unsigned bits.
    // casting is safe because the quotient is ~1.7e20, far inside int256.
    // forge-lint: disable-next-line(unsafe-typecast)
    int256 internal constant SQRT_MAX_INPUT = int256(uint256(type(uint128).max) / WAD_U);

    /// @dev The reference's `MathError`, kept as three distinct errors because the vectors
    /// distinguish them: `mul_div` reports `DivByZero` for `d == 0` and `Overflow` for a result
    /// outside `i128`, and a port that collapsed them would pass the values and fail the cases.
    error Overflow();
    error DivByZero();
    error Domain();

    /// @notice `truncate(a · b / d)`, the product formed at full width.
    /// @dev Computed in magnitudes with the sign taken from the parity of the three operands'
    /// signs, mirroring the reference exactly. A negative result may reach magnitude 2^127 —
    /// that is `type(int128).min` and is permitted; the positive side stops one short.
    function mulDiv(
        int256 a,
        int256 b,
        int256 d
    ) internal pure returns (int256) {
        if (d == 0) revert DivByZero();

        bool negative = ((a < 0) != (b < 0)) != (d < 0);
        uint256 q = (abs(a) * abs(b)) / abs(d);

        if (negative) {
            if (q > uint256(1) << 127) revert Overflow();
            // casting is safe because q <= 2^127 was just checked; negating in int256 reaches
            // exactly type(int128).min without wrapping.
            // forge-lint: disable-next-line(unsafe-typecast)
            return -int256(q);
        }
        // casting INT128_MAX is safe because it is positive.
        // forge-lint: disable-next-line(unsafe-typecast)
        if (q > uint256(INT128_MAX)) revert Overflow();
        // casting is safe because q <= INT128_MAX was just checked.
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(q);
    }

    /// @notice `a · b / WAD`, truncated toward zero.
    function mulWad(
        int256 a,
        int256 b
    ) internal pure returns (int256) {
        return mulDiv(a, b, WAD);
    }

    /// @notice `a · WAD / b`, truncated toward zero.
    function divWad(
        int256 a,
        int256 b
    ) internal pure returns (int256) {
        return mulDiv(a, WAD, b);
    }

    /// @notice `a / n` for a plain integer divisor, truncated toward zero.
    function divInt(
        int256 a,
        int256 n
    ) internal pure returns (int256) {
        if (n == 0) revert DivByZero();
        return a / n;
    }

    /// @notice `⌊a / b⌋` — rounds toward negative infinity.
    /// @dev Solidity's `/` truncates toward zero, which differs from this whenever the operands
    /// have opposite signs and the division is inexact. `expWad` depends on the difference.
    function floorDiv(
        int256 a,
        int256 b
    ) internal pure returns (int256 q) {
        if (b == 0) revert DivByZero();
        q = a / b;
        if ((a % b != 0) && ((a < 0) != (b < 0))) q -= 1;
    }

    /// @notice `⌊√n⌋`, exact.
    /// @dev Newton's method from `2^⌈bits/2⌉`, an initial guess at or above the root, so the
    /// iteration descends and the first non-decreasing step is the floor. Same shape as the
    /// reference's `isqrt_u128`.
    function isqrt(
        uint256 n
    ) internal pure returns (uint256) {
        if (n < 2) return n;

        uint256 x = uint256(1) << ((bitLength(n) + 1) / 2);
        while (true) {
            uint256 y = (x + n / x) >> 1;
            if (y >= x) return x;
            x = y;
        }
        // Unreachable: the sequence is strictly decreasing until it stops.
        revert Overflow();
    }

    /// @notice `⌊√(x · WAD)⌋`, the square root in WAD.
    function sqrtWad(
        int256 x
    ) internal pure returns (int256) {
        if (x < 0 || x > SQRT_MAX_INPUT) revert Domain();
        // casting is safe because x is in [0, SQRT_MAX_INPUT], so x*WAD fits 128 unsigned bits
        // and its square root fits comfortably in int256.
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(isqrt(uint256(x) * WAD_U));
    }

    /// @notice `max(1, ⌊u · WAD / 2^64⌋)` — a 64-bit draw mapped into `(0, WAD)`.
    /// @dev The `max(1, …)` floor is what keeps `U` strictly positive, which `lnWad` and
    /// `invPhiWad` both require: a zero draw would take the inverse normal outside its domain.
    function u64ToWad(
        uint256 u
    ) internal pure returns (int256) {
        uint256 scaled = (u * WAD_U) >> 64;
        // casting is safe because u is at most 2^64-1, so scaled < WAD.
        // forge-lint: disable-next-line(unsafe-typecast)
        return scaled == 0 ? int256(1) : int256(scaled);
    }

    function abs(
        int256 x
    ) internal pure returns (uint256) {
        // casting to 'uint256' is safe because both branches are non-negative by construction.
        // forge-lint: disable-next-line(unsafe-typecast)
        return x < 0 ? uint256(-x) : uint256(x);
    }

    function bitLength(
        uint256 n
    ) internal pure returns (uint256 bits) {
        while (n != 0) {
            bits++;
            n >>= 1;
        }
    }
}
