// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @title Merkle
/// @notice The epoch commitment. Ported from `croom-core`'s `merkle.rs`; definition in
/// `docs/core-v1.md` §7.
///
/// Three choices here are load-bearing and all three are the reference's:
///
/// **Leaves are hashed twice** — `H(H(leafBytes))`. A single hash would let a 32-byte internal
/// node be presented as if it were a leaf, because both are just 32 bytes to the verifier.
/// Double-hashing puts leaves and nodes in disjoint domains.
///
/// **Pairs are sorted** — `node(a, b) = H(min(a, b) ‖ max(a, b))`. A proof therefore carries no
/// direction bits, which makes it smaller and removes a whole class of "the prover chose the
/// wrong side" bug.
///
/// **An odd element carries up unchanged** rather than being duplicated. Duplicating a node is the
/// classic second-preimage hole in Bitcoin-style trees; carrying it is not.
library Merkle {
    /// @dev `round u64 ‖ close i128 ‖ high i128 ‖ low i128` — 56 bytes.
    uint256 internal constant LEAF_ENCODED_LEN = 8 + 16 + 16 + 16;

    error OutOfRange(uint256 index, uint256 length);

    function leafBytes(
        uint64 round,
        int256 close,
        int256 high,
        int256 low
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(round, _i128(close), _i128(high), _i128(low));
    }

    function leafHash(
        uint64 round,
        int256 close,
        int256 high,
        int256 low
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(keccak256(leafBytes(round, close, high, low))));
    }

    function nodeHash(
        bytes32 a,
        bytes32 b
    ) internal pure returns (bytes32) {
        // Byte-wise comparison. Comparing two bytes32 as uint256 is big-endian byte order, which
        // is what "byte-wise" means here.
        return
            uint256(a) <= uint256(b) ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /// @notice Folds a list of leaf hashes to a single root. An empty list roots to zero.
    /// @dev Pairs adjacent elements level by level, carrying an odd last element up unchanged.
    /// Rewrites the input array in place, so the caller's copy is consumed.
    function root(
        bytes32[] memory leaves
    ) internal pure returns (bytes32) {
        uint256 n = leaves.length;
        if (n == 0) return bytes32(0);

        while (n > 1) {
            uint256 out = 0;
            for (uint256 i = 0; i + 1 < n; i += 2) {
                leaves[out++] = nodeHash(leaves[i], leaves[i + 1]);
            }
            if (n % 2 == 1) leaves[out++] = leaves[n - 1];
            n = out;
        }
        return leaves[0];
    }

    /// @notice The sibling path for one leaf, bottom-up.
    /// @dev At each level the sibling is `index ^ 1` when it exists; a lone last element has no
    /// sibling at that level and contributes nothing to the path.
    function proof(
        bytes32[] memory leaves,
        uint256 index
    ) internal pure returns (bytes32[] memory path) {
        uint256 n = leaves.length;
        if (index >= n) revert OutOfRange(index, n);

        // Depth is bounded by the bit length of n, which is where the path can never be longer.
        bytes32[] memory scratch = new bytes32[](256);
        uint256 depth = 0;

        while (n > 1) {
            uint256 sibling = index ^ 1;
            if (sibling < n) scratch[depth++] = leaves[sibling];

            uint256 out = 0;
            for (uint256 i = 0; i + 1 < n; i += 2) {
                leaves[out++] = nodeHash(leaves[i], leaves[i + 1]);
            }
            if (n % 2 == 1) leaves[out++] = leaves[n - 1];

            n = out;
            index /= 2;
        }

        path = new bytes32[](depth);
        for (uint256 i = 0; i < depth; i++) {
            path[i] = scratch[i];
        }
    }

    /// @notice Folds a leaf up its path and compares with the root.
    /// @dev No direction bits, because pairs are sorted. The fold is the whole verification.
    function verify(
        bytes32 expectedRoot,
        bytes32 leaf,
        bytes32[] memory path
    ) internal pure returns (bool) {
        bytes32 acc = leaf;
        for (uint256 i = 0; i < path.length; i++) {
            acc = nodeHash(acc, path[i]);
        }
        return acc == expectedRoot;
    }

    function _i128(
        int256 v
    ) private pure returns (bytes16) {
        // casting is safe because every value reaching a leaf is a price or a bound the model has
        // already clamped into the i128 range.
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes16(uint128(int128(v)));
    }
}
