// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {FixedPointMath as F} from "../src/FixedPointMath.sol";
import {InverseNormal} from "../src/InverseNormal.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Pins every number quoted in `math_breakdown.md` to the real implementation.
///
/// An explanation that drifts from the code is worse than no explanation, because it is believed.
/// If a figure in that document stops being true, this test fails and says which one.
contract WorkedExampleTest is Test {
    int256 internal constant SECONDS_PER_YEAR = 31_536_000;
    int256 internal constant ROUND_SECONDS = 3;
    int256 internal constant SIGMA_75 = 750_000_000_000_000_000; // 75% a year

    /// @dev §5 of the document — turning an annual volatility into a per-round one.
    function test_PerRoundVolatility() public pure {
        int256 dt = F.divInt(ROUND_SECONDS * F.WAD, 1 * SECONDS_PER_YEAR);
        assertEq(dt, 95_129_375_951, "dt: one round as a fraction of a year");

        int256 sdt = F.sqrtWad(dt);
        assertEq(sdt, 308_430_504_248_525, "sqrt(dt) ~ 3.0843e-4");

        int256 sigmaT = F.mulWad(SIGMA_75, sdt);
        assertEq(sigmaT, 231_322_878_186_393, "75% a year is ~0.0231% a round");

        assertEq(F.divInt(F.mulWad(sigmaT, sigmaT), 2), 26_755_136_986, "var_half");
    }

    /// @dev §4 — the inverse normal against values published to 16 decimal places.
    function test_InversePhiMatchesPublishedValues() public pure {
        assertEq(InverseNormal.invPhiWad(1e17), -1_281_551_565_544_600_443, "phi^-1(0.10)");
        assertEq(InverseNormal.invPhiWad(3e17), -524_400_512_708_040_796, "phi^-1(0.30)");
        assertEq(InverseNormal.invPhiWad(6e17), 253_347_103_135_799_810, "phi^-1(0.60)");
        assertEq(InverseNormal.invPhiWad(99e16), 2_326_347_874_040_841_086, "phi^-1(0.99)");
        // Symmetric about a half, to the last unit the representation allows.
        assertEq(InverseNormal.invPhiWad(5e17 + 1), 2, "phi^-1 just above a half is ~0");
        assertEq(InverseNormal.invPhiWad(4e17), -InverseNormal.invPhiWad(6e17), "odd about 1/2");
    }

    /// @dev §6 — one complete Drift tick.
    function test_OneDriftTick() public pure {
        int256 sigmaT = F.mulWad(SIGMA_75, F.sqrtWad(F.divInt(ROUND_SECONDS * F.WAD, SECONDS_PER_YEAR)));
        int256 varHalf = F.divInt(F.mulWad(sigmaT, sigmaT), 2);

        int256 price = 100 * F.WAD;
        int256 z = InverseNormal.invPhiWad(6e17);

        assertEq(F.lnWad(price), 4_605_170_185_988_091_354, "ln(100)");

        int256 next = F.expWad(F.lnWad(price) - varHalf + F.mulWad(sigmaT, z));
        assertEq(next, 100_005_857_994_167_833_280, "100 -> 100.005857994...");
        assertGt(next, price, "an above-median draw moves the price up");
    }

    /// @dev §7 — why the correction term is there at all. Averaging the multiplier over a
    /// symmetric pair of draws leaves the price where it started, to within truncation. Drop
    /// `var_half` and the same average drifts upward forever.
    function test_TheCorrectionKeepsTheAverageFlat() public pure {
        int256 sigmaT = F.mulWad(SIGMA_75, F.sqrtWad(F.divInt(ROUND_SECONDS * F.WAD, SECONDS_PER_YEAR)));
        int256 varHalf = F.divInt(F.mulWad(sigmaT, sigmaT), 2);
        int256 z = InverseNormal.invPhiWad(84e16); // ~+0.9945

        int256 up = F.expWad(F.mulWad(sigmaT, z) - varHalf);
        int256 down = F.expWad(-F.mulWad(sigmaT, z) - varHalf);
        int256 withCorrection = (up + down) / 2;

        int256 upNo = F.expWad(F.mulWad(sigmaT, z));
        int256 downNo = F.expWad(-F.mulWad(sigmaT, z));
        int256 withoutCorrection = (upNo + downNo) / 2;

        assertLt(_distanceFromOne(withCorrection), _distanceFromOne(withoutCorrection), "correction helps");
        assertGt(withoutCorrection, F.WAD, "without it, the average multiplier exceeds 1");
    }

    function _distanceFromOne(
        int256 x
    ) private pure returns (int256) {
        return x > F.WAD ? x - F.WAD : F.WAD - x;
    }
}
