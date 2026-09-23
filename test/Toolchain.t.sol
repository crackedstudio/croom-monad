// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

/// @notice The first test in this repository states the rule the entire derivation rests on:
/// every fixed-point operation truncates toward zero, and it inherits that from Solidity's `/`
/// operator rather than from a rounding helper of ours (PLAN.md §6). If a future compiler bump
/// or an `unchecked` block ever changes this, it fails here first rather than in a conformance
/// vector three weeks later.
contract ToolchainTest is Test {
    function test_DivisionTruncatesTowardZero() public pure {
        assertEq(int256(7) / 2, int256(3));
        assertEq(int256(-7) / 2, int256(-3)); // toward zero, not toward negative infinity
        assertEq(int256(7) / -2, int256(-3));
        assertEq(int256(-7) / -2, int256(3));
    }

    function test_ModuloTakesTheSignOfTheDividend() public pure {
        assertEq(int256(-7) % 2, int256(-1));
        assertEq(int256(7) % -2, int256(1));
    }

    function testFuzz_DivisionTruncatesTowardZero(
        int256 a,
        int256 b
    ) public pure {
        vm.assume(b != 0);
        vm.assume(!(a == type(int256).min && b == -1)); // the single quotient that overflows

        int256 q = a / b;

        // Exact: there is no rounding slack anywhere in the identity.
        assertEq(q * b + (a % b), a);
        // Magnitude matches unsigned division, so nothing ever rounds away from zero.
        assertEq(_abs(q), _abs(a) / _abs(b));
    }

    function _abs(
        int256 x
    ) private pure returns (uint256) {
        // type(int256).min has no positive counterpart, so negate in two steps.
        return x < 0 ? uint256(-(x + 1)) + 1 : uint256(x);
    }
}
