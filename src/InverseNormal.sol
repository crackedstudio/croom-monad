// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {FixedPointMath as F} from "./FixedPointMath.sol";

/// @title InverseNormal
/// @notice Φ⁻¹ — the inverse standard normal CDF, by Wichura's AS241 (PPND16), ported from
/// `croom-core`'s `fixed.rs` and checked against 2,631 frozen vectors.
///
/// This is the function that turns a uniform draw into a bell-curve one, and it is why the price
/// series looks like a market rather than like noise. Everything else in the derivation is
/// arithmetic; this is the statistics.
///
/// AS241 is a rational approximation: two polynomials divided by one another, with three regions
/// and a different coefficient pair in each. The coefficients are the published decimals times
/// 10^18, truncated toward zero. **They are data, not parameters** — a single mistyped digit gives
/// a function that looks right in the middle and is wrong in the tails, which is precisely where a
/// price model spends its interesting moments.
///
/// It lives in its own file because the 48 constants would otherwise dominate `FixedPointMath`.
library InverseNormal {
    /// @dev 0.425 — the half-width of the central region.
    int256 private constant SPLIT1 = 425_000_000_000_000_000;
    /// @dev 0.180625 = 0.425².
    int256 private constant CONST1 = 180_625_000_000_000_000;
    /// @dev 5.0 — the boundary between the middle tail and the far tail.
    int256 private constant SPLIT2 = 5e18;
    /// @dev 1.6 — the middle tail's re-centring offset.
    int256 private constant CONST2 = 1_600_000_000_000_000_000;

    error Domain();

    /// @notice Φ⁻¹(p) in WAD. Requires `0 < p < WAD`.
    /// @dev Three regions:
    ///  - `|p − ½| ≤ 0.425` — the central 84%: a rational function of `q²`.
    ///  - beyond that, re-express in `r = √(−ln min(p, 1−p))`, which grows slowly enough that a degree-7 rational stays accurate, and split again at `r = 5`.
    /// The result is odd about `p = ½`, so only the upper half is computed and the sign restored.
    function invPhiWad(
        int256 p
    ) internal pure returns (int256) {
        if (p <= 0 || p >= F.WAD) revert Domain();

        int256 q = p - F.HALF_WAD;

        if (_abs(q) <= SPLIT1) {
            int256 centre = CONST1 - F.mulWad(q, q);
            return F.divWad(F.mulWad(q, _horner(_a(), centre)), _horner(_b(), centre));
        }

        // The tails. `r0` is the smaller of the two tail masses, so this is always the same
        // computation reflected, which is what makes the sign restoration at the end sound.
        int256 r0 = q < 0 ? p : F.WAD - p;
        int256 r = F.sqrtWad(-F.lnWad(r0));

        int256 value;
        if (r <= SPLIT2) {
            value = F.divWad(_horner(_c(), r - CONST2), _horner(_d(), r - CONST2));
        } else {
            value = F.divWad(_horner(_e(), r - SPLIT2), _horner(_f(), r - SPLIT2));
        }
        return q < 0 ? -value : value;
    }

    /// @dev `((c7·r + c6)·r + … )·r + c0`, every multiplication truncating in WAD.
    function _horner(
        int256[8] memory c,
        int256 r
    ) private pure returns (int256 acc) {
        acc = c[7];
        for (uint256 i = 7; i > 0; i--) {
            acc = F.mulWad(acc, r) + c[i - 1];
        }
    }

    function _abs(
        int256 x
    ) private pure returns (int256) {
        return x < 0 ? -x : x;
    }

    // ── AS241 PPND16 coefficients ×10^18, truncated toward zero ──────────────────────────────
    // B[0] = D[0] = F[0] = WAD. Transcribed from croom-core; see docs/core-v1.md Appendix A.

    function _a() private pure returns (int256[8] memory) {
        return [
            int256(3_387_132_872_796_366_608),
            133_141_667_891_784_377_450,
            1_971_590_950_306_551_442_700,
            13_731_693_765_509_461_125_000,
            45_921_953_931_549_871_457_000,
            67_265_770_927_008_700_853_000,
            33_430_575_583_588_128_105_000,
            2_509_080_928_730_122_672_700
        ];
    }

    function _b() private pure returns (int256[8] memory) {
        return [
            F.WAD,
            int256(42_313_330_701_600_911_252),
            687_187_007_492_057_908_300,
            5_394_196_021_424_751_107_700,
            21_213_794_301_586_595_867_000,
            39_307_895_800_092_710_610_000,
            28_729_085_735_721_942_674_000,
            5_226_495_278_852_854_561_000
        ];
    }

    function _c() private pure returns (int256[8] memory) {
        return [
            int256(1_423_437_110_749_683_577),
            4_630_337_846_156_545_295,
            5_769_497_221_460_691_405,
            3_647_848_324_763_204_605,
            1_270_458_252_452_368_382,
            241_780_725_177_450_611,
            22_723_844_989_269_184,
            774_545_014_278_341
        ];
    }

    function _d() private pure returns (int256[8] memory) {
        return [
            F.WAD,
            int256(2_053_191_626_637_758_821),
            1_676_384_830_183_803_849,
            689_767_334_985_100_004,
            148_103_976_427_480_074,
            15_198_666_563_616_457,
            547_593_808_499_534,
            1_050_750_071
        ];
    }

    function _e() private pure returns (int256[8] memory) {
        return [
            int256(6_657_904_643_501_103_777),
            5_463_784_911_164_114_369,
            1_784_826_539_917_291_335,
            296_560_571_828_504_891,
            26_532_189_526_576_123,
            1_242_660_947_388_078,
            27_115_555_687_434,
            201_033_439_929
        ];
    }

    function _f() private pure returns (int256[8] memory) {
        return [
            F.WAD,
            int256(599_832_206_555_887_937),
            136_929_880_922_735_805,
            14_875_361_290_850_614,
            786_869_131_145_613,
            18_463_183_175_100,
            142_151_175_831,
            2044
        ];
    }
}
