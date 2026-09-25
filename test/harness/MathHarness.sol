// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {FixedPointMath} from "../../src/FixedPointMath.sol";

/// @notice External wrappers so the conformance suite can observe reverts. A library call that
/// reverts inside the test would abort the test; through an external call it is a value the
/// harness can compare against the vector's expected error variant.
contract MathHarness {
    function mulDiv(
        int256 a,
        int256 b,
        int256 d
    ) external pure returns (int256) {
        return FixedPointMath.mulDiv(a, b, d);
    }

    function sqrtWad(
        int256 x
    ) external pure returns (int256) {
        return FixedPointMath.sqrtWad(x);
    }

    function expWad(
        int256 x
    ) external pure returns (int256) {
        return FixedPointMath.expWad(x);
    }

    function lnWad(
        int256 x
    ) external pure returns (int256) {
        return FixedPointMath.lnWad(x);
    }

    function u64ToWad(
        uint256 u
    ) external pure returns (int256) {
        return FixedPointMath.u64ToWad(u);
    }
}
