// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Merkle} from "../src/Merkle.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Tick} from "../src/Tick.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Epoch commitments against the reference's frozen roots and sample proofs.
///
/// This is the test that ties the whole derivation together: it derives every round of an epoch
/// from the beacon, commits to them, and checks the root against a value computed by a different
/// implementation in a different language before this one existed. It also checks the state hashes
/// either side of the epoch, which is exactly what the ladder stores.
contract MerkleTest is Test {
    uint256 internal constant R_HEADER = 12;
    uint256 internal constant R_RECORD = 153;
    uint256 internal constant E_HEADER = 12;
    uint256 internal constant E_RECORD = 1007;
    uint256 internal constant PROOF_BLOCK = 297;
    uint256 internal constant PROOFS_AT = 116;

    struct Ctx {
        Tick.Model model;
        uint8 family;
        uint32 epochRounds;
        bytes rounds;
        bytes epochs;
    }

    function _spec(
        string memory name
    ) internal view returns (RoomSpec.Spec memory s) {
        string memory json = vm.readFile(string.concat("test/fixtures/vectors/rooms/", name, ".json"));
        s.family = keccak256(bytes(vm.parseJsonString(json, ".family"))) == keccak256("drift")
            ? RoomSpec.FAMILY_DRIFT
            : RoomSpec.FAMILY_STEP;
        s.beacon = uint8(vm.parseJsonUint(json, ".beacon"));
        s.subTicks = uint8(vm.parseJsonUint(json, ".subTicks"));
        s.epochRounds = uint32(vm.parseJsonUint(json, ".epochRounds"));
        s.genesisRound = uint64(vm.parseUint(vm.parseJsonString(json, ".genesisRound")));
        s.initialPrice = vm.parseInt(vm.parseJsonString(json, ".initialPrice"));
        s.decimals = uint8(vm.parseJsonUint(json, ".decimals"));
        s.mathVersion = uint8(vm.parseJsonUint(json, ".mathVersion"));
        s.hashFn = uint8(vm.parseJsonUint(json, ".hashFn"));
        s.param = vm.parseInt(vm.parseJsonString(json, ".param"));
    }

    function _run(
        string memory name
    ) internal view {
        RoomSpec.Spec memory spec = _spec(name);
        Ctx memory c = Ctx({
            model: Tick.compile(spec),
            family: spec.family,
            epochRounds: spec.epochRounds,
            rounds: vm.readFileBinary(string.concat("test/fixtures/vectors/rounds/", name, ".bin")),
            epochs: vm.readFileBinary(string.concat("test/fixtures/vectors/epochs/", name, ".bin"))
        });

        uint256 epochCount = uint32(uint256(_word(c.epochs, 8) >> 224));
        require(c.epochs.length == E_HEADER + epochCount * E_RECORD, "epoch length disagrees");
        require(epochCount > 0, "no epochs");

        uint256 limit = vm.envOr("CROOM_FULL_VECTORS", uint256(0)) == 1 ? epochCount : 10;
        if (limit > epochCount) limit = epochCount;

        int256 price = spec.initialPrice;
        for (uint256 e = 0; e < limit; e++) {
            price = _checkEpoch(c, e, price);
        }
    }

    function _checkEpoch(
        Ctx memory c,
        uint256 e,
        int256 price
    ) private view returns (int256) {
        uint256 at = E_HEADER + e * E_RECORD;

        RoomSpec.State memory st = RoomSpec.State({price: price, level: 0, lo: 0, hi: 0});
        bytes32 prev = RoomSpec.stateHash(c.family, st);
        if (prev != _word(c.epochs, at + 20)) {
            assertEq(prev, _word(c.epochs, at + 20), _why(e, "prev_state_hash"));
        }

        bytes32[] memory leaves;
        (leaves, price) = _buildLeaves(c, e, price);

        st.price = price;
        bytes32 endHash = RoomSpec.stateHash(c.family, st);
        if (endHash != _word(c.epochs, at + 52)) {
            assertEq(endHash, _word(c.epochs, at + 52), _why(e, "end_state_hash"));
        }

        bytes32 expectedRoot = _word(c.epochs, at + 84);
        bytes32 got = Merkle.root(_clone(leaves));
        if (got != expectedRoot) assertEq(got, expectedRoot, _why(e, "merkle_root"));

        _checkProofs(c, at, leaves, expectedRoot, e);
        return price;
    }

    /// @dev Its own frame: the derivation returns three values and the record needs four offsets,
    /// which together with the loop state is past what the legacy codegen can hold.
    function _buildLeaves(
        Ctx memory c,
        uint256 e,
        int256 price
    ) private view returns (bytes32[] memory leaves, int256 endPrice) {
        leaves = new bytes32[](c.epochRounds);
        for (uint256 j = 0; j < c.epochRounds; j++) {
            uint256 rAt = R_HEADER + (e * c.epochRounds + j) * R_RECORD;
            (int256 close, int256 high, int256 low) =
                Tick.deriveRound(c.model, price, _word(c.rounds, rAt + 8));
            leaves[j] = Merkle.leafHash(uint64(uint256(_word(c.rounds, rAt) >> 192)), close, high, low);
            price = close;
        }
        endPrice = price;
    }

    /// @dev `Merkle.root` and `Merkle.proof` consume the array they are given, so each use needs
    /// its own copy.
    function _clone(
        bytes32[] memory a
    ) private pure returns (bytes32[] memory b) {
        b = new bytes32[](a.length);
        for (uint256 i = 0; i < a.length; i++) {
            b[i] = a[i];
        }
    }

    function _checkProofs(
        Ctx memory c,
        uint256 at,
        bytes32[] memory leaves,
        bytes32 expectedRoot,
        uint256 e
    ) private view {
        for (uint256 k = 0; k < 3; k++) {
            uint256 pAt = at + PROOFS_AT + k * PROOF_BLOCK;
            uint64 round = uint64(uint256(_word(c.epochs, pAt) >> 192));
            bytes32 leaf = _word(c.epochs, pAt + 8);
            uint256 pathLen = uint8(c.epochs[pAt + 40]);

            uint256 index = round - uint64(uint256(_word(c.epochs, at + 4) >> 192));
            if (leaves[index] != leaf) assertEq(leaves[index], leaf, _why(e, "sample leaf hash"));

            bytes32[] memory path = new bytes32[](pathLen);
            for (uint256 i = 0; i < pathLen; i++) {
                path[i] = _word(c.epochs, pAt + 41 + i * 32);
            }
            assertTrue(Merkle.verify(expectedRoot, leaf, path), _why(e, "sample proof"));
        }
    }

    function test_DriftEpochsMatchTheReference() public view {
        _run("drift");
    }

    function test_StepEpochsMatchTheReference() public view {
        _run("step");
    }

    /// @dev Our own proof generator must agree with the reference's verifier shape: build a tree,
    /// prove every leaf, and check each one folds to the root.
    function test_EveryLeafProvesAgainstItsOwnRoot() public pure {
        uint256 n = 37; // deliberately odd, so the carry path is exercised at several levels
        bytes32[] memory leaves = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            leaves[i] = Merkle.leafHash(uint64(1000 + i), int256(i + 1) * 1e18, 0, 0);
        }

        bytes32 r = Merkle.root(_clone(leaves));

        for (uint256 i = 0; i < n; i++) {
            assertTrue(Merkle.verify(r, leaves[i], Merkle.proof(_clone(leaves), i)), "leaf must prove");
        }
    }

    function test_EmptyTreeRootsToZero() public pure {
        assertEq(Merkle.root(new bytes32[](0)), bytes32(0));
    }

    /// @dev Leaves are double-hashed so an internal node can never be passed off as a leaf.
    function test_LeavesAndNodesAreInDifferentDomains() public pure {
        bytes memory encoded = Merkle.leafBytes(1000, 1e18, 1e18, 1e18);
        assertEq(encoded.length, 56, "56 bytes");
        assertTrue(Merkle.leafHash(1000, 1e18, 1e18, 1e18) != keccak256(encoded), "leaf must be hashed twice");
    }

    function _word(
        bytes memory b,
        uint256 offset
    ) private pure returns (bytes32 w) {
        assembly ("memory-safe") {
            w := mload(add(add(b, 0x20), offset))
        }
    }

    function _why(
        uint256 e,
        string memory field
    ) private pure returns (string memory) {
        return string.concat("epoch ", vm.toString(e), ": ", field);
    }
}
