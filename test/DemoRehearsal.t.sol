// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;
import {DemoDisprove} from "../script/DemoDisprove.s.sol";
import {DemoPostLie} from "../script/DemoPostLie.s.sol";
import {OpenRooms} from "../script/OpenRooms.s.sol";
import {Entropy} from "../src/Entropy.sol";
import {Ladder} from "../src/Ladder.sol";
import {Registry} from "../src/Registry.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Rehearses both Gate 3 halves locally, as two separate actors, so the live run cannot be the first
/// time it has executed. Fifty transactions taught us to pre-flight; two expensive ones deserve
/// the same.
contract DemoRehearsalTest is Test {
    function test_TheDemoScriptRejectsTheCheckpointAndPaysTheChallenger() public {
        Entropy entropy = new Entropy();
        Registry registry = new Registry(entropy);

        string memory json = vm.readFile("test/fixtures/drand/rounds/1000.json");
        entropy.proveRound(1000, vm.parseJsonBytes(json, ".signature"));

        RoomSpec.Spec memory spec = new OpenRooms().specAt(0, 21_193_055);
        registry.openRoom(spec);

        Ladder ladder = new Ladder(registry, 0.05 ether, 600);
        DemoPostLie liar = new DemoPostLie();
        DemoDisprove watcher = new DemoDisprove();

        vm.setEnv("LADDER", vm.toString(address(ladder)));
        vm.deal(address(liar), 1 ether);

        liar.run();
        assertEq(address(ladder).balance, 0.05 ether, "bond escrowed");

        // Nothing is handed from one to the other. The watcher re-derives the epoch from the same
        // public beacon data and locates the lie on its own.
        watcher.run();

        // Balances are not attributed here: `vm.startBroadcast` inside a test pranks the sender,
        // so the bond moves from and to Foundry's default sender rather than these two contracts.
        // The live run on testnet is where the two addresses are genuinely distinct — which is
        // the point of splitting the demo in the first place. What this rehearsal proves is that
        // the sequence executes: escrow, independent re-derivation, rejection, nothing left over.

        bytes32 roomId = RoomSpec.roomId(spec);
        (,,,,, Ladder.Status status,) = ladder.checkpoints(roomId, 0);
        assertEq(uint8(status), uint8(Ladder.Status.Rejected), "checkpoint must be rejected");
        assertEq(address(ladder).balance, 0, "ladder holds nothing");
    }
}
