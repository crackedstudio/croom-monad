// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Ladder} from "../src/Ladder.sol";
import {Merkle} from "../src/Merkle.sol";
import {Registry} from "../src/Registry.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Tick} from "../src/Tick.sol";
import {Test} from "forge-std/Test.sol";

/// @notice The ladder, and the invariant the whole protocol rests on:
///
///   **a dishonest poster loses their bond to anyone who bothers to look.**
///
/// Everything runs against real drand signatures for 25 consecutive rounds, so the fraud proof is
/// exercised through the path it will take on chain. No mocked beacon.
contract LadderTest is Test {
    uint64 internal constant START = 21_173_060;
    uint32 internal constant EPOCH_ROUNDS = 20;
    uint64 internal constant CHALLENGE_ROUNDS = 50;
    uint256 internal constant BOND = 0.01 ether;
    uint256 internal constant HONEST = type(uint256).max;

    struct Row {
        int256 close;
        int256 high;
        int256 low;
    }

    Entropy internal entropy;
    Registry internal registry;
    Ladder internal ladder;

    string[] internal sigs;
    address internal poster;
    address internal watcher;

    function setUp() public {
        poster = makeAddr("poster");
        watcher = makeAddr("watcher");

        entropy = new Entropy();
        registry = new Registry(entropy);
        ladder = new Ladder(registry, BOND, CHALLENGE_ROUNDS);

        string memory json = vm.readFile("test/fixtures/drand/consecutive/rounds.json");
        for (uint256 i = 0; i < 25; i++) {
            sigs.push(vm.parseJsonString(json, string.concat(".signatures[", vm.toString(i), "]")));
        }

        registry.openRoom(_spec());
        vm.deal(poster, 1 ether);
        vm.deal(watcher, 1 ether);
    }

    // ── the honest path ──────────────────────────────────────────────────────────────────────

    function test_PostThenFinalizeReturnsTheBondAndAdvancesTheRoom() public {
        (Row[] memory rows,, bytes32 root) = _epoch(HONEST);
        int128 endPrice = int128(rows[EPOCH_ROUNDS - 1].close);

        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

        uint256 before = poster.balance;
        _closeTheWindow();
        ladder.finalize(_spec(), 0, endPrice);

        assertEq(poster.balance, before + BOND, "bond returned to the poster");

        (int128 finalPrice, uint64 nextEpoch) = ladder.roomState(RoomSpec.roomId(_spec()));
        assertEq(finalPrice, endPrice, "room advanced to the closing price");
        assertEq(nextEpoch, 1, "next epoch is one");
    }

    /// @dev Anyone may finalize, and the bond still goes to the poster — so a stranger finalizing
    /// costs them gas and benefits everyone. There is no privileged finalizer to bribe or stall.
    function test_AnyoneCanFinalize() public {
        (Row[] memory rows,, bytes32 root) = _epoch(HONEST);
        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

        _closeTheWindow();
        uint256 before = poster.balance;

        vm.prank(watcher);
        ladder.finalize(_spec(), 0, int128(rows[EPOCH_ROUNDS - 1].close));
        assertEq(poster.balance, before + BOND, "bond goes to the poster, not the caller");
    }

    // ── the invariant: a liar loses ──────────────────────────────────────────────────────────

    function test_ALiarWhoCorruptsAMiddleLeafLosesTheBond() public {
        uint256 at = 9;
        (Row[] memory rows, bytes32[] memory leaves, bytes32 root) = _epoch(at);

        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

        Ladder.LeafClaim memory prev = _claim(rows, leaves, at - 1);
        Ladder.LeafClaim memory cur = _claim(rows, leaves, at);
        bytes memory signature = _sig(START + uint64(at));

        uint256 before = watcher.balance;
        vm.prank(watcher);
        ladder.disproveTransition(_spec(), 0, prev, cur, signature);

        assertEq(watcher.balance, before + BOND, "the watcher takes the bond");
        assertEq(uint8(_status(0)), uint8(Ladder.Status.Rejected), "checkpoint rejected");

        (, uint64 nextEpoch) = ladder.roomState(RoomSpec.roomId(_spec()));
        assertEq(nextEpoch, 0, "the room did not advance");
    }

    /// @dev Corrupting the *first* leaf cannot be caught by comparing adjacent leaves — there is
    /// no earlier leaf in the epoch. The prior state comes from the Room instead.
    function test_ALiarWhoCorruptsTheFirstLeafLosesTheBond() public {
        (Row[] memory rows, bytes32[] memory leaves, bytes32 root) = _epoch(0);

        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

        Ladder.LeafClaim memory first = _claim(rows, leaves, 0);
        bytes memory signature = _sig(START);

        uint256 before = watcher.balance;
        vm.prank(watcher);
        ladder.disproveFirstTransition(_spec(), 0, first, signature);

        assertEq(watcher.balance, before + BOND, "the watcher takes the bond");
    }

    /// @dev Every leaf correct, but the claimed end state is not. No signature and no
    /// re-execution: two things the poster committed to in one breath that disagree.
    function test_ALiarWhoMisstatesTheEndStateLosesTheBond() public {
        (Row[] memory rows, bytes32[] memory leaves, bytes32 root) = _epoch(HONEST);

        bytes32 wrongEnd = RoomSpec.stateHash(
            RoomSpec.FAMILY_DRIFT,
            RoomSpec.State({price: int128(rows[EPOCH_ROUNDS - 1].close) + 1e18, level: 0, lo: 0, hi: 0})
        );

        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), wrongEnd, root);

        Ladder.LeafClaim memory last = _claim(rows, leaves, EPOCH_ROUNDS - 1);

        uint256 before = watcher.balance;
        vm.prank(watcher);
        ladder.disproveEndState(_spec(), 0, last);

        assertEq(watcher.balance, before + BOND, "the watcher takes the bond");
    }

    /// @dev Position by position. The invariant is not "a liar usually loses" — it is that there
    /// is **no index at which lying is safe**.
    function test_NoPositionInTheEpochIsSafeToLieAt() public {
        for (uint256 at = 1; at < EPOCH_ROUNDS; at++) {
            uint256 snapshot = vm.snapshotState();

            (Row[] memory rows, bytes32[] memory leaves, bytes32 root) = _epoch(at);
            vm.prank(poster);
            ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

            Ladder.LeafClaim memory prev = _claim(rows, leaves, at - 1);
            Ladder.LeafClaim memory cur = _claim(rows, leaves, at);
            bytes memory signature = _sig(START + uint64(at));

            vm.prank(watcher);
            ladder.disproveTransition(_spec(), 0, prev, cur, signature);

            assertEq(uint8(_status(0)), uint8(Ladder.Status.Rejected), "a liar survived here");
            vm.revertToState(snapshot);
        }
    }

    // ── an honest checkpoint cannot be robbed ────────────────────────────────────────────────

    /// @dev The mirror of the invariant. Without it the fraud proof would be a theft primitive.
    function test_AnHonestCheckpointCannotBeDisproved() public {
        (Row[] memory rows, bytes32[] memory leaves, bytes32 root) = _epoch(HONEST);
        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

        // Every claim and signature is built *before* arming expectRevert: these helpers call
        // cheatcodes, and a cheatcode between arming and the call confuses the expectation.
        Ladder.LeafClaim memory prev = _claim(rows, leaves, 5);
        Ladder.LeafClaim memory cur = _claim(rows, leaves, 6);
        Ladder.LeafClaim memory first = _claim(rows, leaves, 0);
        Ladder.LeafClaim memory last = _claim(rows, leaves, EPOCH_ROUNDS - 1);
        bytes memory sigSix = _sig(START + 6);
        bytes memory sigFirst = _sig(START);

        vm.expectRevert(Ladder.CheckpointIsHonest.selector);
        ladder.disproveTransition(_spec(), 0, prev, cur, sigSix);

        vm.expectRevert(Ladder.CheckpointIsHonest.selector);
        ladder.disproveFirstTransition(_spec(), 0, first, sigFirst);

        vm.expectRevert(Ladder.CheckpointIsHonest.selector);
        ladder.disproveEndState(_spec(), 0, last);

        assertEq(uint8(_status(0)), uint8(Ladder.Status.Pending), "still pending");
    }

    function test_AnUncommittedLeafIsRejected() public {
        (Row[] memory rows, bytes32[] memory leaves, bytes32 root) = _epoch(HONEST);
        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

        Ladder.LeafClaim memory prev = _claim(rows, leaves, 5);
        Ladder.LeafClaim memory fake = _claim(rows, leaves, 6);
        fake.close = fake.close + 1e18; // not the leaf its path proves
        bytes memory signature = _sig(START + 6);

        vm.expectRevert(abi.encodeWithSelector(Ladder.LeafNotCommitted.selector, fake.round));
        ladder.disproveTransition(_spec(), 0, prev, fake, signature);
    }

    function test_NonAdjacentLeavesAreRejected() public {
        (Row[] memory rows, bytes32[] memory leaves, bytes32 root) = _epoch(HONEST);
        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

        Ladder.LeafClaim memory prev = _claim(rows, leaves, 4);
        Ladder.LeafClaim memory cur = _claim(rows, leaves, 6);
        bytes memory signature = _sig(START + 6);

        vm.expectRevert(abi.encodeWithSelector(Ladder.NotAdjacent.selector, START + 4, START + 6));
        ladder.disproveTransition(_spec(), 0, prev, cur, signature);
    }

    // ── windows, counted in rounds and nothing else ──────────────────────────────────────────

    function test_CannotFinalizeWhileTheWindowIsOpen() public {
        (Row[] memory rows,, bytes32 root) = _epoch(HONEST);
        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

        int128 endPrice = int128(rows[EPOCH_ROUNDS - 1].close);

        vm.expectRevert(abi.encodeWithSelector(Ladder.WindowOpen.selector, uint64(0), CHALLENGE_ROUNDS));
        ladder.finalize(_spec(), 0, endPrice);
    }

    /// @dev A liar who survives the window keeps the bond. That is the design: safety rests on
    /// someone watching, and the writeup says so rather than implying otherwise.
    function test_CannotDisproveAfterTheWindowCloses() public {
        uint256 at = 9;
        (Row[] memory rows, bytes32[] memory leaves, bytes32 root) = _epoch(at);
        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

        Ladder.LeafClaim memory prev = _claim(rows, leaves, at - 1);
        Ladder.LeafClaim memory cur = _claim(rows, leaves, at);
        bytes memory signature = _sig(START + uint64(at));

        _closeTheWindow();

        vm.expectRevert(
            abi.encodeWithSelector(Ladder.WindowClosed.selector, entropy.provenFloor(), CHALLENGE_ROUNDS)
        );
        ladder.disproveTransition(_spec(), 0, prev, cur, signature);
    }

    // ── posting rules ────────────────────────────────────────────────────────────────────────

    function test_PostRejectsWrongEpochWrongBondAndWrongPriorState() public {
        bytes32 prior = _priorHash();
        vm.startPrank(poster);

        vm.expectRevert(abi.encodeWithSelector(Ladder.WrongEpoch.selector, uint64(0), uint64(1)));
        ladder.post{value: BOND}(_spec(), 1, prior, bytes32(0), bytes32(0));

        vm.expectRevert(abi.encodeWithSelector(Ladder.WrongBond.selector, BOND, uint256(0)));
        ladder.post{value: 0}(_spec(), 0, prior, bytes32(0), bytes32(0));

        vm.expectRevert();
        ladder.post{value: BOND}(_spec(), 0, keccak256("fiction"), bytes32(0), bytes32(0));

        vm.stopPrank();
    }

    function test_PostRejectsAnUnopenedRoom() public {
        RoomSpec.Spec memory other = _spec();
        other.param = 123e15; // never registered
        bytes32 id = RoomSpec.roomId(other);
        bytes32 prior = _priorHash();

        vm.prank(poster);
        vm.expectRevert(abi.encodeWithSelector(Ladder.RoomNotOpen.selector, id));
        ladder.post{value: BOND}(other, 0, prior, bytes32(0), bytes32(0));
    }

    function test_CannotPostTheSameEpochTwice() public {
        (Row[] memory rows,, bytes32 root) = _epoch(HONEST);
        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);

        bytes32 prior = _priorHash();
        bytes32 end = _endHash(rows);

        vm.prank(poster);
        vm.expectRevert(
            abi.encodeWithSelector(Ladder.EpochAlreadyPosted.selector, uint64(0), Ladder.Status.Pending)
        );
        ladder.post{value: BOND}(_spec(), 0, prior, end, root);
    }

    /// @dev A rejected epoch must be re-postable: a liar's checkpoint has been thrown out and
    /// somebody still has to commit the correct one. Its bond is already gone to the challenger,
    /// so nothing is stranded.
    function test_ARejectedEpochCanBeRepostedHonestly() public {
        uint256 at = 4;
        (Row[] memory bad, bytes32[] memory badLeaves, bytes32 badRoot) = _epoch(at);
        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(bad), badRoot);

        Ladder.LeafClaim memory prev = _claim(bad, badLeaves, at - 1);
        Ladder.LeafClaim memory cur = _claim(bad, badLeaves, at);
        bytes memory signature = _sig(START + uint64(at));

        vm.prank(watcher);
        ladder.disproveTransition(_spec(), 0, prev, cur, signature);
        assertEq(uint8(_status(0)), uint8(Ladder.Status.Rejected));

        (Row[] memory good,, bytes32 goodRoot) = _epoch(HONEST);
        address honest = makeAddr("honestPoster");
        vm.deal(honest, 1 ether);

        vm.prank(honest);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(good), goodRoot);
        assertEq(uint8(_status(0)), uint8(Ladder.Status.Pending), "re-posted");

        _closeTheWindow();
        uint256 before = honest.balance;
        ladder.finalize(_spec(), 0, int128(good[EPOCH_ROUNDS - 1].close));
        assertEq(honest.balance, before + BOND, "the honest re-poster is paid");
    }

    /// @dev The stranded-bond bug this guards against: the contract must never hold more than the
    /// bonds it still owes.
    function test_NoBondIsEverStranded() public {
        (Row[] memory rows,, bytes32 root) = _epoch(HONEST);
        vm.prank(poster);
        ladder.post{value: BOND}(_spec(), 0, _priorHash(), _endHash(rows), root);
        assertEq(address(ladder).balance, BOND, "holding exactly one bond");

        _closeTheWindow();
        ladder.finalize(_spec(), 0, int128(rows[EPOCH_ROUNDS - 1].close));
        assertEq(address(ladder).balance, 0, "holding nothing once settled");
    }

    // ── helpers ──────────────────────────────────────────────────────────────────────────────

    function _spec() internal pure returns (RoomSpec.Spec memory s) {
        s.family = RoomSpec.FAMILY_DRIFT;
        s.beacon = RoomSpec.BEACON_EVMNET;
        s.subTicks = 1;
        s.epochRounds = EPOCH_ROUNDS;
        s.genesisRound = START;
        s.initialPrice = 1000e18;
        s.decimals = 2;
        s.mathVersion = RoomSpec.MATH_VERSION;
        s.hashFn = RoomSpec.HASH_FN;
        s.param = 750e15;
    }

    function _sig(
        uint64 round
    ) internal view returns (bytes memory) {
        return vm.parseBytes(string.concat("0x", sigs[round - START]));
    }

    function _r(
        uint64 round
    ) internal view returns (bytes32) {
        return sha256(_sig(round));
    }

    /// @dev Builds an epoch. `lieAt == HONEST` gives an honest one; otherwise the leaf at that
    /// index carries a close one whole unit off, and every later leaf follows from the lie.
    ///
    /// The rows returned are **exactly** the values the leaves were hashed from. An earlier
    /// version recomputed `high` and `low` when building a claim, which disagreed with the tree
    /// whenever a lie moved the close past one of them — so the claim failed its membership check
    /// and the test blamed the contract for the test's own inconsistency.
    function _epoch(
        uint256 lieAt
    ) internal view returns (Row[] memory rows, bytes32[] memory leaves, bytes32 root) {
        Tick.Model memory model = Tick.compile(_spec());
        rows = new Row[](EPOCH_ROUNDS);
        leaves = new bytes32[](EPOCH_ROUNDS);

        int256 price = _spec().initialPrice;
        for (uint256 i = 0; i < EPOCH_ROUNDS; i++) {
            uint64 round = START + uint64(i);
            (int256 close, int256 high, int256 low) = Tick.deriveRound(model, price, _r(round));
            if (i == lieAt) close = close + 1e18;
            rows[i] = Row({close: close, high: high, low: low});
            leaves[i] = Merkle.leafHash(round, close, high, low);
            price = close;
        }
        root = Merkle.root(_clone(leaves));
    }

    function _claim(
        Row[] memory rows,
        bytes32[] memory leaves,
        uint256 index
    ) internal pure returns (Ladder.LeafClaim memory c) {
        c.round = START + uint64(index);
        c.close = int128(rows[index].close);
        c.high = int128(rows[index].high);
        c.low = int128(rows[index].low);
        c.path = Merkle.proof(_clone(leaves), index);
    }

    function _priorHash() internal pure returns (bytes32) {
        return
            RoomSpec.stateHash(
                RoomSpec.FAMILY_DRIFT, RoomSpec.State({price: 1000e18, level: 0, lo: 0, hi: 0})
            );
    }

    function _endHash(
        Row[] memory rows
    ) internal pure returns (bytes32) {
        return RoomSpec.stateHash(
            RoomSpec.FAMILY_DRIFT,
            RoomSpec.State({price: int128(rows[EPOCH_ROUNDS - 1].close), level: 0, lo: 0, hi: 0})
        );
    }

    /// @dev The floor only rises by proof, so closing a window means proving a later round. There
    /// is no clock to warp, which is the point.
    function _closeTheWindow() internal {
        string memory json = vm.readFile("test/fixtures/drand/rounds/20880831.json");
        entropy.proveRound(20_880_831, vm.parseJsonBytes(json, ".signature"));
        assertGt(entropy.provenFloor(), CHALLENGE_ROUNDS);
    }

    function _status(
        uint64 epoch
    ) internal view returns (Ladder.Status status) {
        (,,,,, status,) = ladder.checkpoints(RoomSpec.roomId(_spec()), epoch);
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
