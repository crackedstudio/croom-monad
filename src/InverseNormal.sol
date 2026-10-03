// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {FixedPointMath as FP} from "./FixedPointMath.sol";

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
///
/// The Horner evaluations are **unrolled over named constants rather than looping over a memory
/// array**. An earlier version held each table in `int256[8] memory`, which was tidier and wrong
/// in two ways: EVM memory only ever grows, so 10,000 ticks of allocation exhausted the test
/// runner's memory limit outright; and the same waste would be paid on chain, in the fraud proof's
/// terminal step, which is the one place cost is adversarial.
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
        if (p <= 0 || p >= FP.WAD) revert Domain();

        int256 q = p - FP.HALF_WAD;

        if (_abs(q) <= SPLIT1) {
            int256 centre = CONST1 - FP.mulWad(q, q);
            return FP.divWad(FP.mulWad(q, _hornerA(centre)), _hornerB(centre));
        }

        // The tails. `r0` is the smaller of the two tail masses, so this is always the same
        // computation reflected, which is what makes the sign restoration at the end sound.
        int256 r0 = q < 0 ? p : FP.WAD - p;
        int256 r = FP.sqrtWad(-FP.lnWad(r0));

        int256 value;
        if (r <= SPLIT2) {
            value = FP.divWad(_hornerC(r - CONST2), _hornerD(r - CONST2));
        } else {
            value = FP.divWad(_hornerE(r - SPLIT2), _hornerF(r - SPLIT2));
        }
        return q < 0 ? -value : value;
    }

    function _abs(
        int256 x
    ) private pure returns (int256) {
        return x < 0 ? -x : x;
    }

    function _hornerA(
        int256 r
    ) private pure returns (int256 acc) {
        acc = A7;
        acc = FP.mulWad(acc, r) + A6;
        acc = FP.mulWad(acc, r) + A5;
        acc = FP.mulWad(acc, r) + A4;
        acc = FP.mulWad(acc, r) + A3;
        acc = FP.mulWad(acc, r) + A2;
        acc = FP.mulWad(acc, r) + A1;
        acc = FP.mulWad(acc, r) + A0;
    }

    function _hornerB(
        int256 r
    ) private pure returns (int256 acc) {
        acc = B7;
        acc = FP.mulWad(acc, r) + B6;
        acc = FP.mulWad(acc, r) + B5;
        acc = FP.mulWad(acc, r) + B4;
        acc = FP.mulWad(acc, r) + B3;
        acc = FP.mulWad(acc, r) + B2;
        acc = FP.mulWad(acc, r) + B1;
        acc = FP.mulWad(acc, r) + B0;
    }

    function _hornerC(
        int256 r
    ) private pure returns (int256 acc) {
        acc = C7;
        acc = FP.mulWad(acc, r) + C6;
        acc = FP.mulWad(acc, r) + C5;
        acc = FP.mulWad(acc, r) + C4;
        acc = FP.mulWad(acc, r) + C3;
        acc = FP.mulWad(acc, r) + C2;
        acc = FP.mulWad(acc, r) + C1;
        acc = FP.mulWad(acc, r) + C0;
    }

    function _hornerD(
        int256 r
    ) private pure returns (int256 acc) {
        acc = D7;
        acc = FP.mulWad(acc, r) + D6;
        acc = FP.mulWad(acc, r) + D5;
        acc = FP.mulWad(acc, r) + D4;
        acc = FP.mulWad(acc, r) + D3;
        acc = FP.mulWad(acc, r) + D2;
        acc = FP.mulWad(acc, r) + D1;
        acc = FP.mulWad(acc, r) + D0;
    }

    function _hornerE(
        int256 r
    ) private pure returns (int256 acc) {
        acc = E7;
        acc = FP.mulWad(acc, r) + E6;
        acc = FP.mulWad(acc, r) + E5;
        acc = FP.mulWad(acc, r) + E4;
        acc = FP.mulWad(acc, r) + E3;
        acc = FP.mulWad(acc, r) + E2;
        acc = FP.mulWad(acc, r) + E1;
        acc = FP.mulWad(acc, r) + E0;
    }

    function _hornerF(
        int256 r
    ) private pure returns (int256 acc) {
        acc = F7;
        acc = FP.mulWad(acc, r) + F6;
        acc = FP.mulWad(acc, r) + F5;
        acc = FP.mulWad(acc, r) + F4;
        acc = FP.mulWad(acc, r) + F3;
        acc = FP.mulWad(acc, r) + F2;
        acc = FP.mulWad(acc, r) + F1;
        acc = FP.mulWad(acc, r) + F0;
    }

    // AS241 table A.
    int256 private constant A0 = 3_387_132_872_796_366_608;
    int256 private constant A1 = 133_141_667_891_784_377_450;
    int256 private constant A2 = 1_971_590_950_306_551_442_700;
    int256 private constant A3 = 13_731_693_765_509_461_125_000;
    int256 private constant A4 = 45_921_953_931_549_871_457_000;
    int256 private constant A5 = 67_265_770_927_008_700_853_000;
    int256 private constant A6 = 33_430_575_583_588_128_105_000;
    int256 private constant A7 = 2_509_080_928_730_122_672_700;

    // AS241 table B.
    int256 private constant B0 = FP.WAD;
    int256 private constant B1 = 42_313_330_701_600_911_252;
    int256 private constant B2 = 687_187_007_492_057_908_300;
    int256 private constant B3 = 5_394_196_021_424_751_107_700;
    int256 private constant B4 = 21_213_794_301_586_595_867_000;
    int256 private constant B5 = 39_307_895_800_092_710_610_000;
    int256 private constant B6 = 28_729_085_735_721_942_674_000;
    int256 private constant B7 = 5_226_495_278_852_854_561_000;

    // AS241 table C.
    int256 private constant C0 = 1_423_437_110_749_683_577;
    int256 private constant C1 = 4_630_337_846_156_545_295;
    int256 private constant C2 = 5_769_497_221_460_691_405;
    int256 private constant C3 = 3_647_848_324_763_204_605;
    int256 private constant C4 = 1_270_458_252_452_368_382;
    int256 private constant C5 = 241_780_725_177_450_611;
    int256 private constant C6 = 22_723_844_989_269_184;
    int256 private constant C7 = 774_545_014_278_341;

    // AS241 table D.
    int256 private constant D0 = FP.WAD;
    int256 private constant D1 = 2_053_191_626_637_758_821;
    int256 private constant D2 = 1_676_384_830_183_803_849;
    int256 private constant D3 = 689_767_334_985_100_004;
    int256 private constant D4 = 148_103_976_427_480_074;
    int256 private constant D5 = 15_198_666_563_616_457;
    int256 private constant D6 = 547_593_808_499_534;
    int256 private constant D7 = 1_050_750_071;

    // AS241 table E.
    int256 private constant E0 = 6_657_904_643_501_103_777;
    int256 private constant E1 = 5_463_784_911_164_114_369;
    int256 private constant E2 = 1_784_826_539_917_291_335;
    int256 private constant E3 = 296_560_571_828_504_891;
    int256 private constant E4 = 26_532_189_526_576_123;
    int256 private constant E5 = 1_242_660_947_388_078;
    int256 private constant E6 = 27_115_555_687_434;
    int256 private constant E7 = 201_033_439_929;

    // AS241 table F.
    int256 private constant F0 = FP.WAD;
    int256 private constant F1 = 599_832_206_555_887_937;
    int256 private constant F2 = 136_929_880_922_735_805;
    int256 private constant F3 = 14_875_361_290_850_614;
    int256 private constant F4 = 786_869_131_145_613;
    int256 private constant F5 = 18_463_183_175_100;
    int256 private constant F6 = 142_151_175_831;
    int256 private constant F7 = 2044;
}
