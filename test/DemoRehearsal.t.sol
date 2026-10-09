// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;
import {DemoFraudProof} from "../script/DemoFraudProof.s.sol";
import {Entropy} from "../src/Entropy.sol";
import {Ladder} from "../src/Ladder.sol";
import {OpenRooms} from "../script/OpenRooms.s.sol";
import {Registry} from "../src/Registry.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Rehearses the Gate 3 script end to end locally, so the live run cannot be the first
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
        DemoFraudProof demo = new DemoFraudProof();

        vm.setEnv("LADDER", vm.toString(address(ladder)));
        // run() sees the test as its caller, so that is the address its guard must accept;
        // the bond is paid by the script itself, which is why the ETH goes there.
        vm.setEnv("EXPECTED_DEPLOYER", vm.toString(address(this)));
        vm.deal(address(demo), 1 ether);

        uint256 before = address(demo).balance;
        demo.run();

        bytes32 roomId = RoomSpec.roomId(spec);
        (,,,,, Ladder.Status status,) = ladder.checkpoints(roomId, 0);
        assertEq(uint8(status), uint8(Ladder.Status.Rejected), "checkpoint must be rejected");
        assertEq(address(demo).balance, before, "bond posted then reclaimed by the same actor");
        assertEq(address(ladder).balance, 0, "ladder holds nothing");
    }
}
