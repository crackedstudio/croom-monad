// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Ladder} from "../src/Ladder.sol";
import {Market} from "../src/Market.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Tick} from "../src/Tick.sol";
import {DemoBase} from "./DemoBase.s.sol";
import {OpenRooms} from "./OpenRooms.s.sol";
import {console} from "forge-std/Script.sol";

/// @notice A complete parimutuel round, end to end, in one broadcast.
///
/// ```bash
/// make demo-market-setup LADDER=0x... MARKET=0x...
/// ```
///
/// Posts an **honest** epoch, advances the floor past the challenge window, finalises, opens a
/// market over rounds inside that epoch, and stakes one side. A second account takes the other
/// side; settlement then pays out against a price proved from the committed root.
///
/// # The ordering is constrained, and the constraint is easy to get backwards
///
/// Finalising needs the floor **above** `post_floor + challengeRounds`. Entry needs the market's
/// first round **above** the floor. So the floor has to land in the gap between them:
///
/// ```
///   [ post_floor + 600 , marketStart - 2 ]
/// ```
///
/// Proving the beacon's *latest* round instead — the obvious thing to do — pushes the floor past
/// every round of the epoch and the market can never be opened at all. The window is the whole
/// trick, and it is the same rule that stops anyone betting on a round whose outcome is already
/// public.
contract DemoMarketSetup is DemoBase {
    /// @dev Inside epoch 0 (rounds GENESIS .. GENESIS+19), with room either side.
    uint64 internal constant MARKET_START = GENESIS + 2;
    uint64 internal constant MARKET_END = GENESIS + 15;

    /// @dev Clears the challenge window while staying below the market's first round.
    uint64 internal constant FLOOR_TARGET = 21_180_000;

    uint256 internal constant STAKE = 0.03 ether;

    function run() external {
        Ladder ladder = Ladder(vm.envAddress("LADDER"));
        Market market = Market(vm.envAddress("MARKET"));
        Entropy entropy = Entropy(address(ladder.entropy()));

        RoomSpec.Spec memory spec = new OpenRooms().specAt(0, GENESIS);
        (, int256[] memory closes, int256[] memory highs, int256[] memory lows) = _deriveHonest(spec);

        // The outcome is already determined by the beacon — we are reading it, not choosing it.
        // The script deliberately takes the *losing* side so the payout goes to the other account,
        // which is the point worth showing.
        bool up = closes[MARKET_END - GENESIS] > closes[MARKET_START - GENESIS];
        uint8 ourSide = up ? 1 : 0; // Side.Down : Side.Up

        console.log("market window  ", MARKET_START, "->", MARKET_END);
        console.log("beacon says the price goes", up ? "UP" : "DOWN");
        console.log("this account stakes the losing side on purpose:", up ? "DOWN" : "UP");

        Ladder.PostedLeaf[] memory published = new Ladder.PostedLeaf[](EPOCH_ROUNDS);
        for (uint256 i = 0; i < EPOCH_ROUNDS; i++) {
            published[i] = Ladder.PostedLeaf({
                round: GENESIS + uint64(i),
                close: int128(closes[i]),
                high: int128(highs[i]),
                low: int128(lows[i])
            });
        }

        bytes32 prior = RoomSpec.stateHash(
            spec.family, RoomSpec.State({price: int128(spec.initialPrice), level: 0, lo: 0, hi: 0})
        );
        bytes32 endHash = RoomSpec.stateHash(
            spec.family, RoomSpec.State({price: int128(closes[EPOCH_ROUNDS - 1]), level: 0, lo: 0, hi: 0})
        );

        string memory floorJson = vm.readFile("demo/floor-round.json");
        bytes memory floorSig =
            vm.parseBytes(string.concat("0x", vm.parseJsonString(floorJson, ".signatures[0]")));

        vm.startBroadcast();

        ladder.post{value: ladder.bond()}(spec, 0, prior, endHash, published);
        console.log("1/5 honest epoch posted");

        if (entropy.provenFloor() < FLOOR_TARGET) {
            entropy.proveRound(FLOOR_TARGET, floorSig);
        }
        console.log("2/5 floor advanced to", FLOOR_TARGET);

        ladder.finalize(spec, 0, int128(closes[EPOCH_ROUNDS - 1]));
        console.log("3/5 epoch finalised, bond returned");

        bytes32 id = market.open(spec, MARKET_START, MARKET_END);
        console.log("4/5 market opened");
        console.logBytes32(id);

        market.enter{value: STAKE}(id, Market.Side(ourSide));
        console.log("5/5 staked (wei):", STAKE);

        vm.stopBroadcast();

        console.log("");
        console.log("next: the other account takes the winning side, then settle.");
    }
}
