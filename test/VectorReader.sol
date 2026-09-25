// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {FixedPointMath} from "../src/FixedPointMath.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Reads the packed fixtures produced by `bin/pack-vectors.py` from the reference's frozen
/// JSON vectors. Format is documented there and in `spec/README.md`.
abstract contract VectorReader is Test {
    /// @dev The packer's magic, as an 8-byte literal so no cast is needed at the comparison.
    bytes8 internal constant MAGIC = 0x43524f4f4d465831; // "CROOMFX1"

    uint8 internal constant OK = 0;
    uint8 internal constant ERR_OVERFLOW = 1;
    uint8 internal constant ERR_DIV_BY_ZERO = 2;
    uint8 internal constant ERR_DOMAIN = 3;

    struct Vectors {
        bytes data;
        uint256 arity;
        uint256 count;
        uint256 recordSize;
    }

    function _load(
        string memory name
    ) internal view returns (Vectors memory v) {
        v.data = vm.readFileBinary(string.concat("test/fixtures/vectors/maths/", name, ".bin"));

        require(v.data.length >= 13, "fixture too short for a header");
        require(bytes8(_word(v.data, 0)) == MAGIC, "bad fixture magic");

        v.arity = uint8(v.data[8]);
        v.count = uint32(uint256(_word(v.data, 9) >> 224));
        v.recordSize = v.arity * 32 + 33;

        // A reader that has consumed `count` records must be exactly at end of file. Anything
        // else means a truncated or corrupt fixture, and a partial pass is worse than a failure.
        require(v.data.length == 13 + v.count * v.recordSize, "fixture length disagrees with count");
        // An empty fixture would let every loop below pass without executing once. A suite that
        // silently tests nothing reports the same green as one that tests everything.
        require(v.count > 0, "fixture is empty");
    }

    function _input(
        Vectors memory v,
        uint256 record,
        uint256 index
    ) internal pure returns (int256) {
        return int256(uint256(_word(v.data, 13 + record * v.recordSize + index * 32)));
    }

    function _status(
        Vectors memory v,
        uint256 record
    ) internal pure returns (uint8) {
        return uint8(v.data[13 + record * v.recordSize + v.arity * 32]);
    }

    function _expected(
        Vectors memory v,
        uint256 record
    ) internal pure returns (int256) {
        return int256(uint256(_word(v.data, 13 + record * v.recordSize + v.arity * 32 + 1)));
    }

    /// @dev Maps low-level revert data onto the reference's `MathError` variants.
    function _statusOf(
        bytes memory err
    ) internal pure returns (uint8) {
        if (err.length < 4) return type(uint8).max;
        bytes4 selector = bytes4(_word(err, 0));
        if (selector == FixedPointMath.Overflow.selector) return ERR_OVERFLOW;
        if (selector == FixedPointMath.DivByZero.selector) return ERR_DIV_BY_ZERO;
        if (selector == FixedPointMath.Domain.selector) return ERR_DOMAIN;
        return type(uint8).max;
    }

    function _word(
        bytes memory b,
        uint256 offset
    ) private pure returns (bytes32 w) {
        assembly ("memory-safe") {
            w := mload(add(add(b, 0x20), offset))
        }
    }
}
