// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ladder} from "../src/Ladder.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {DemoBase} from "./DemoBase.s.sol";
import {OpenRooms} from "./OpenRooms.s.sol";
import {console} from "forge-std/Script.sol";

/// @notice **Gate 3, part two.** The watcher. Recomputes the epoch from the public beacon, finds
/// the leaf that does not follow, and takes the bond.
///
/// ```bash
/// make demo-disprove LADDER=0x... ACCOUNT=croom-challenger FROM=0x...
/// ```
///
/// Nothing was passed from the liar. This script derives the same leaves independently, which is
/// why it can locate the lie at all — and why it needs no bond of its own: there is no interactive
/// game to stall, so there is nothing to punish.
contract DemoDisprove is DemoBase {
    function run() external {
        Ladder ladder = Ladder(vm.envAddress("LADDER"));
        RoomSpec.Spec memory spec = new OpenRooms().specAt(0, GENESIS);

        console.log("watcher:", msg.sender);
        console.log("bond at stake (wei):", ladder.bond());

        (bytes32[] memory leaves, int256[] memory closes, int256[] memory highs, int256[] memory lows) =
            _deriveEpoch(spec);

        vm.startBroadcast();
        ladder.disproveTransition(
            spec,
            0,
            _claim(leaves, closes, highs, lows, LIE_AT - 1),
            _claim(leaves, closes, highs, lows, LIE_AT),
            _sig(LIE_AT)
        );
        vm.stopBroadcast();

        console.log("checkpoint rejected at leaf", LIE_AT, "- bond forfeited to the watcher");
    }
}
