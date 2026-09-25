// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {FixedPointMath} from "../src/FixedPointMath.sol";
import {VectorReader} from "./VectorReader.sol";
import {MathHarness} from "./harness/MathHarness.sol";

/// @notice Conformance of the fixed-point core against `croom-core`'s frozen vectors.
///
/// These are not tests we wrote to describe behaviour we chose. They are an artefact the
/// reference froze before this port existed, and the only acceptable result is bit-for-bit
/// agreement on every case, including which error each failure raises.
contract FixedPointMathTest is VectorReader {
    MathHarness internal harness;

    function setUp() public {
        harness = new MathHarness();
    }

    function test_MulDivVectors() public view {
        Vectors memory v = _load("mul_div");
        assertEq(v.arity, 3, "mul_div arity");

        for (uint256 i = 0; i < v.count; i++) {
            int256 a = _input(v, i, 0);
            int256 b = _input(v, i, 1);
            int256 d = _input(v, i, 2);
            uint8 want = _status(v, i);

            try harness.mulDiv(a, b, d) returns (int256 got) {
                assertEq(want, OK, _case("mul_div", i, "expected an error, got a value"));
                assertEq(got, _expected(v, i), _case("mul_div", i, "wrong value"));
            } catch (bytes memory err) {
                assertEq(_statusOf(err), want, _case("mul_div", i, "wrong error variant"));
            }
        }
    }

    function test_SqrtWadVectors() public view {
        Vectors memory v = _load("sqrt_wad");
        assertEq(v.arity, 1, "sqrt_wad arity");

        for (uint256 i = 0; i < v.count; i++) {
            uint8 want = _status(v, i);
            try harness.sqrtWad(_input(v, i, 0)) returns (int256 got) {
                assertEq(want, OK, _case("sqrt_wad", i, "expected an error, got a value"));
                assertEq(got, _expected(v, i), _case("sqrt_wad", i, "wrong value"));
            } catch (bytes memory err) {
                assertEq(_statusOf(err), want, _case("sqrt_wad", i, "wrong error variant"));
            }
        }
    }

    function test_U64ToWadVectors() public view {
        Vectors memory v = _load("u64_to_wad");

        for (uint256 i = 0; i < v.count; i++) {
            assertEq(_status(v, i), OK, "u64_to_wad has no error cases");
            assertEq(
                harness.u64ToWad(uint256(_input(v, i, 0))),
                _expected(v, i),
                _case("u64_to_wad", i, "wrong value")
            );
        }
    }

    function test_ExpWadVectors() public view {
        Vectors memory v = _load("exp_wad");

        for (uint256 i = 0; i < v.count; i++) {
            uint8 want = _status(v, i);
            try harness.expWad(_input(v, i, 0)) returns (int256 got) {
                assertEq(want, OK, _case("exp_wad", i, "expected an error, got a value"));
                assertEq(got, _expected(v, i), _case("exp_wad", i, "wrong value"));
            } catch (bytes memory err) {
                assertEq(_statusOf(err), want, _case("exp_wad", i, "wrong error variant"));
            }
        }
    }

    function test_LnWadVectors() public view {
        Vectors memory v = _load("ln_wad");

        for (uint256 i = 0; i < v.count; i++) {
            uint8 want = _status(v, i);
            try harness.lnWad(_input(v, i, 0)) returns (int256 got) {
                assertEq(want, OK, _case("ln_wad", i, "expected an error, got a value"));
                assertEq(got, _expected(v, i), _case("ln_wad", i, "wrong value"));
            } catch (bytes memory err) {
                assertEq(_statusOf(err), want, _case("ln_wad", i, "wrong error variant"));
            }
        }
    }

    /// @dev The tails are the point. A mistyped coefficient leaves the central region looking
    /// perfectly reasonable and corrupts only the extremes — which is where a price model spends
    /// its interesting moments, and where a market would notice first.
    function test_InvPhiWadVectors() public view {
        Vectors memory v = _load("inv_phi_wad");

        for (uint256 i = 0; i < v.count; i++) {
            uint8 want = _status(v, i);
            try harness.invPhiWad(_input(v, i, 0)) returns (int256 got) {
                assertEq(want, OK, _case("inv_phi_wad", i, "expected an error, got a value"));
                assertEq(got, _expected(v, i), _case("inv_phi_wad", i, "wrong value"));
            } catch (bytes memory err) {
                assertEq(_statusOf(err), want, _case("inv_phi_wad", i, "wrong error variant"));
            }
        }
    }

    /// @dev `expWad` floors `k = ⌊x / LN2_WAD⌋` and `k` is negative for every negative input, so
    /// this helper is on the path for half of all exponentials. Solidity's `/` truncates, and the
    /// two disagree exactly when the operands' signs differ and the division is inexact.
    function test_FloorDivRoundsTowardNegativeInfinity() public pure {
        assertEq(FixedPointMath.floorDiv(7, 2), 3);
        assertEq(FixedPointMath.floorDiv(-7, 2), -4, "floor, not truncation");
        assertEq(FixedPointMath.floorDiv(7, -2), -4, "floor, not truncation");
        assertEq(FixedPointMath.floorDiv(-7, -2), 3);
        // Exact divisions agree with truncation on both signs.
        assertEq(FixedPointMath.floorDiv(-8, 2), -4);
        assertEq(FixedPointMath.floorDiv(8, -2), -4);
    }

    /// @dev The property that separates the two: they differ by exactly one whenever the signs
    /// differ and there is a remainder, and agree otherwise.
    function testFuzz_FloorDivAgreesWithTruncationExceptWhenItMust(
        int256 a,
        int256 b
    ) public pure {
        vm.assume(b != 0);
        vm.assume(!(a == type(int256).min && b == -1));

        int256 floored = FixedPointMath.floorDiv(a, b);
        int256 truncated = a / b;

        if (a % b != 0 && ((a < 0) != (b < 0))) {
            assertEq(floored, truncated - 1, "should differ by one");
        } else {
            assertEq(floored, truncated, "should agree");
        }
    }

    function test_DivIntTruncatesAndRejectsZero() public {
        assertEq(FixedPointMath.divInt(-7, 2), -3, "truncates toward zero");
        vm.expectRevert(FixedPointMath.DivByZero.selector);
        harness.mulDiv(1, 1, 0);
    }

    function _case(
        string memory name,
        uint256 i,
        string memory why
    ) private pure returns (string memory) {
        return string.concat(name, " case ", vm.toString(i), ": ", why);
    }
}
