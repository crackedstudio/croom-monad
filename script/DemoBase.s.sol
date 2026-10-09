// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Ladder} from "../src/Ladder.sol";
import {Merkle} from "../src/Merkle.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Tick} from "../src/Tick.sol";
import {OpenRooms} from "./OpenRooms.s.sol";
import {Script, console} from "forge-std/Script.sol";

/// @notice Shared derivation for the Gate 3 demo, used by both halves.
///
/// The epoch is derived inside the script's own EVM from the 20 real beacon signatures in
/// `demo/epoch0.json`. Because the derivation is deterministic, the liar and the challenger
/// recompute **byte-identical** leaves without passing anything between them — which is the whole
/// point: a watcher needs no privileged data, only the public beacon and the specification.
///
/// One leaf's closing price is moved by a single unit, 10^-18 of a price. That is the smallest lie
/// the encoding can express, and it is caught as decisively as a large one, because the contract
/// asks whether the committed value *equals* the re-executed one, not whether it is close.
abstract contract DemoBase is Script {
    uint64 internal constant GENESIS = 21_193_055;
    uint32 internal constant EPOCH_ROUNDS = 20;
    /// @dev Which leaf to corrupt. Mid-epoch, so the disproof uses the adjacent-pair path rather
    /// than either boundary case.
    uint256 internal constant LIE_AT = 9;

    /// @dev Derives the epoch and plants the lie, propagating it so every later leaf follows from
    /// it — which is what a liar who wants a self-consistent tree would actually do.
    function _deriveEpoch(
        RoomSpec.Spec memory spec
    )
        internal
        view
        returns (bytes32[] memory leaves, int256[] memory closes, int256[] memory highs, int256[] memory lows)
    {
        Tick.Model memory model = Tick.compile(spec);
        leaves = new bytes32[](EPOCH_ROUNDS);
        closes = new int256[](EPOCH_ROUNDS);
        highs = new int256[](EPOCH_ROUNDS);
        lows = new int256[](EPOCH_ROUNDS);

        int256 price = spec.initialPrice;
        for (uint256 i = 0; i < EPOCH_ROUNDS; i++) {
            uint64 round = GENESIS + uint64(i);
            (int256 close, int256 high, int256 low) = Tick.deriveRound(model, price, sha256(_sig(i)));
            if (i == LIE_AT) close = close + 1;
            closes[i] = close;
            highs[i] = high;
            lows[i] = low;
            leaves[i] = Merkle.leafHash(round, close, high, low);
            price = close;
        }
    }

    function _claim(
        bytes32[] memory leaves,
        int256[] memory closes,
        int256[] memory highs,
        int256[] memory lows,
        uint256 index
    ) internal pure returns (Ladder.LeafClaim memory c) {
        c.round = GENESIS + uint64(index);
        c.close = int128(closes[index]);
        c.high = int128(highs[index]);
        c.low = int128(lows[index]);
        c.path = Merkle.proof(_clone(leaves), index);
    }

    function _sig(
        uint256 index
    ) internal view returns (bytes memory) {
        string memory json = vm.readFile("demo/epoch0.json");
        return vm.parseBytes(
            string.concat(
                "0x", vm.parseJsonString(json, string.concat(".signatures[", vm.toString(index), "]"))
            )
        );
    }

    function _clone(
        bytes32[] memory a
    ) internal pure returns (bytes32[] memory b) {
        b = new bytes32[](a.length);
        for (uint256 i = 0; i < a.length; i++) {
            b[i] = a[i];
        }
    }
}
