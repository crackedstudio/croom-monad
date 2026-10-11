// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Ladder} from "../src/Ladder.sol";
import {Market} from "../src/Market.sol";
import {Merkle} from "../src/Merkle.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Tick} from "../src/Tick.sol";
import {DemoBase} from "./DemoBase.s.sol";
import {OpenRooms} from "./OpenRooms.s.sol";
import {console} from "forge-std/Script.sol";

/// @notice Settles the demo market and claims. Anyone may call the settlement.
///
/// ```bash
/// make demo-market-settle LADDER=0x... MARKET=0x...
/// ```
///
/// Nothing tells this contract a price. It is **shown** two prices, each with a Merkle path
/// proving the value belongs to an epoch the ladder has finalised — so the settlement rests on the
/// same commitment the fraud proof protects, and on nothing else.
contract DemoMarketSettle is DemoBase {
    uint64 internal constant MARKET_START = GENESIS + 2;
    uint64 internal constant MARKET_END = GENESIS + 15;

    function run() external {
        Ladder ladder = Ladder(vm.envAddress("LADDER"));
        Market market = Market(vm.envAddress("MARKET"));

        RoomSpec.Spec memory spec = new OpenRooms().specAt(0, GENESIS);
        (bytes32[] memory leaves, int256[] memory closes, int256[] memory highs, int256[] memory lows) =
            _deriveHonest(spec);

        bytes32 id = market.marketId(RoomSpec.roomId(spec), MARKET_START, MARKET_END);

        (,,, uint128 upTotal, uint128 downTotal,, Market.State state,) = market.books(id);
        console.log("market state (1=open)", uint8(state));
        console.log("staked up / down (wei):", upTotal, downTotal);

        Ladder.LeafClaim memory startClaim = _claim(leaves, closes, highs, lows, MARKET_START - GENESIS);
        Ladder.LeafClaim memory endClaim = _claim(leaves, closes, highs, lows, MARKET_END - GENESIS);

        console.log("open  price:");
        console.logInt(startClaim.close);
        console.log("close price:");
        console.logInt(endClaim.close);

        vm.startBroadcast();
        market.settle(spec, id, 0, startClaim, 0, endClaim);
        console.log("settled");

        // Claiming is attempted and allowed to fail: the caller may be on the losing side, and a
        // losing claim reverting is correct behaviour rather than an error in the demo.
        try market.claim(id) {
            console.log("claimed a payout for this account");
        } catch {
            console.log("nothing to claim for this account (it backed the losing side)");
        }
        vm.stopBroadcast();
    }
}
