// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Ladder} from "../src/Ladder.sol";
import {Merkle} from "../src/Merkle.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Tick} from "../src/Tick.sol";
import {OpenRooms} from "./OpenRooms.s.sol";
import {Script, console} from "forge-std/Script.sol";

/// @notice **Gate 3.** Posts a knowingly dishonest checkpoint on public testnet, then defeats it
/// and takes the bond — in two transactions anyone can inspect.
///
/// ```bash
/// make demo-fraud-proof LADDER=0x...
/// ```
///
/// The epoch is derived here, inside the script's own EVM, from the 20 real beacon signatures in
/// `demo/epoch0.json`. Only the two state-changing calls are broadcast, so what lands on chain is
/// exactly what a liar and a watcher would each send.
///
/// One leaf's closing price is moved by a single unit — 10^-18 of a price. That is the smallest
/// lie the encoding can express, and it is caught as decisively as a large one, because the
/// contract asks whether the committed value *equals* the re-executed one and not whether it is
/// close.
contract DemoFraudProof is Script {
    address internal constant EXPECTED_DEPLOYER = 0xc50f1FbD1c36a2305B257376eb2264C3bB6179e8;

    uint64 internal constant GENESIS = 21_193_055;
    uint32 internal constant EPOCH_ROUNDS = 20;
    /// @dev Which leaf to corrupt. Mid-epoch, so the disproof uses the adjacent-pair path rather
    /// than either boundary case.
    uint256 internal constant LIE_AT = 9;

    function run() external {
        address expected = vm.envOr("EXPECTED_DEPLOYER", EXPECTED_DEPLOYER);
        if (msg.sender != expected) {
            console.log("expected deployer:", expected);
            console.log("actual deployer:  ", msg.sender);
            revert("wrong deployer: pass --sender as well as --account");
        }

        Ladder ladder = Ladder(vm.envAddress("LADDER"));
        RoomSpec.Spec memory spec = new OpenRooms().specAt(0, GENESIS);
        bytes32 roomId = RoomSpec.roomId(spec);

        console.log("room:  ");
        console.logBytes32(roomId);
        console.log("floor: ", Entropy(address(ladder.entropy())).provenFloor());

        (bytes32[] memory leaves, int256[] memory closes, int256[] memory highs, int256[] memory lows) =
            _deriveEpoch(spec);

        bytes32 root = Merkle.root(_clone(leaves));
        bytes32 priorHash = RoomSpec.stateHash(
            spec.family, RoomSpec.State({price: int128(spec.initialPrice), level: 0, lo: 0, hi: 0})
        );
        bytes32 endHash = RoomSpec.stateHash(
            spec.family, RoomSpec.State({price: int128(closes[EPOCH_ROUNDS - 1]), level: 0, lo: 0, hi: 0})
        );

        console.log("posting a checkpoint whose leaf at index", LIE_AT, "is wrong by 1 wei of price");

        vm.startBroadcast();
        ladder.post{value: ladder.bond()}(spec, 0, priorHash, endHash, root);

        ladder.disproveTransition(
            spec,
            0,
            _claim(leaves, closes, highs, lows, LIE_AT - 1),
            _claim(leaves, closes, highs, lows, LIE_AT),
            _sig(LIE_AT)
        );
        vm.stopBroadcast();

        console.log("checkpoint rejected; bond forfeited to the challenger");
    }

    /// @dev Derives the epoch and plants the lie, propagating it so every later leaf follows from
    /// it — which is what a liar who wants a self-consistent tree would actually do.
    function _deriveEpoch(
        RoomSpec.Spec memory spec
    )
        private
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
    ) private pure returns (Ladder.LeafClaim memory c) {
        c.round = GENESIS + uint64(index);
        c.close = int128(closes[index]);
        c.high = int128(highs[index]);
        c.low = int128(lows[index]);
        c.path = Merkle.proof(_clone(leaves), index);
    }

    function _sig(
        uint256 index
    ) private view returns (bytes memory) {
        string memory json = vm.readFile("demo/epoch0.json");
        return vm.parseBytes(
            string.concat(
                "0x", vm.parseJsonString(json, string.concat(".signatures[", vm.toString(index), "]"))
            )
        );
    }

    function _clone(
        bytes32[] memory a
    ) private pure returns (bytes32[] memory b) {
        b = new bytes32[](a.length);
        for (uint256 i = 0; i < a.length; i++) {
            b[i] = a[i];
        }
    }
}
