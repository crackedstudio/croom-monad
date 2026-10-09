// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Ladder} from "../src/Ladder.sol";
import {Merkle} from "../src/Merkle.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {DemoBase} from "./DemoBase.s.sol";
import {OpenRooms} from "./OpenRooms.s.sol";
import {console} from "forge-std/Script.sol";

/// @notice **Gate 3, part one.** The liar. Posts a checkpoint whose leaf at index 9 is wrong by a
/// single unit of price, and escrows the bond.
///
/// ```bash
/// make demo-post-lie LADDER=0x... ACCOUNT=croom-liar FROM=0x...
/// ```
///
/// Run from a **different account** to the challenger. The two halves being visibly unrelated
/// addresses is part of what the demonstration shows: the watcher holds no privilege, no shared
/// secret, and no prior arrangement.
contract DemoPostLie is DemoBase {
    function run() external {
        Ladder ladder = Ladder(vm.envAddress("LADDER"));
        RoomSpec.Spec memory spec = new OpenRooms().specAt(0, GENESIS);

        console.log("liar:  ", msg.sender);
        console.log("room:  ");
        console.logBytes32(RoomSpec.roomId(spec));
        console.log("floor: ", Entropy(address(ladder.entropy())).provenFloor());

        (bytes32[] memory leaves, int256[] memory closes,,) = _deriveEpoch(spec);

        bytes32 priorHash = RoomSpec.stateHash(
            spec.family, RoomSpec.State({price: int128(spec.initialPrice), level: 0, lo: 0, hi: 0})
        );
        bytes32 endHash = RoomSpec.stateHash(
            spec.family, RoomSpec.State({price: int128(closes[EPOCH_ROUNDS - 1]), level: 0, lo: 0, hi: 0})
        );

        vm.startBroadcast();
        ladder.post{value: ladder.bond()}(spec, 0, priorHash, endHash, Merkle.root(_clone(leaves)));
        vm.stopBroadcast();

        console.log("posted a dishonest checkpoint; leaf", LIE_AT, "is wrong by 1");
        console.log("bond escrowed (wei):", ladder.bond());
    }
}
