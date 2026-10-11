// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "../src/Entropy.sol";
import {Ladder} from "../src/Ladder.sol";
import {Market} from "../src/Market.sol";
import {Merkle} from "../src/Merkle.sol";
import {Registry} from "../src/Registry.sol";
import {RoomSpec} from "../src/RoomSpec.sol";
import {Tick} from "../src/Tick.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Parimutuel markets: payouts, refunds, the rake, and the fairness boundary.
contract MarketTest is Test {
    uint64 internal constant START = 21_173_060;
    uint32 internal constant EPOCH_ROUNDS = 20;
    uint64 internal constant CHALLENGE_ROUNDS = 50;
    uint256 internal constant BOND = 0.01 ether;

    uint64 internal constant MARKET_START = START + 2;
    uint64 internal constant MARKET_END = START + 15;

    Entropy internal entropy;
    Registry internal registry;
    Ladder internal ladder;
    Market internal market;

    string[] internal sigs;
    address internal alice;
    address internal bob;
    address internal creator;

    int256[] internal closes;
    int256[] internal highs;
    int256[] internal lows;
    bytes32[] internal leaves;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        creator = makeAddr("creator");

        entropy = new Entropy();
        registry = new Registry(entropy);
        ladder = new Ladder(registry, BOND, CHALLENGE_ROUNDS);
        market = new Market(ladder);

        string memory json = vm.readFile("test/fixtures/drand/consecutive/rounds.json");
        for (uint256 i = 0; i < 25; i++) {
            sigs.push(vm.parseJsonString(json, string.concat(".signatures[", vm.toString(i), "]")));
        }

        vm.prank(creator);
        registry.openRoom(_spec());

        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(address(this), 10 ether);

        _deriveEpoch();
        _postAndFinalize();
    }

    // ── the happy path ───────────────────────────────────────────────────────────────────────

    function test_WinnersSplitThePotLessRake() public {
        bytes32 id = _openMarket();

        // Whichever way the beacon went, stake the winning side with alice.
        Market.Side winning =
            closes[MARKET_END - START] > closes[MARKET_START - START] ? Market.Side.Up : Market.Side.Down;
        Market.Side losing = winning == Market.Side.Up ? Market.Side.Down : Market.Side.Up;

        vm.prank(alice);
        market.enter{value: 3 ether}(id, winning);
        vm.prank(bob);
        market.enter{value: 1 ether}(id, losing);

        _settle(id);

        uint256 pot = 4 ether;
        uint256 rake = pot / 100;
        assertEq(market.rakeOwed(creator), rake, "the rake is credited to the Room's creator");

        uint256 c0 = creator.balance;
        vm.prank(creator);
        market.withdrawRake();
        assertEq(creator.balance - c0, rake, "and withdrawable");

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        market.claim(id);
        assertEq(alice.balance - aliceBefore, pot - rake, "sole winner takes the pool");

        vm.prank(bob);
        vm.expectRevert(Market.NothingToClaim.selector);
        market.claim(id);
    }

    function test_TwoWinnersSplitProRata() public {
        bytes32 id = _openMarket();
        Market.Side winning =
            closes[MARKET_END - START] > closes[MARKET_START - START] ? Market.Side.Up : Market.Side.Down;
        Market.Side losing = winning == Market.Side.Up ? Market.Side.Down : Market.Side.Up;

        vm.prank(alice);
        market.enter{value: 3 ether}(id, winning);
        vm.prank(address(this));
        market.enter{value: 1 ether}(id, winning);
        vm.prank(bob);
        market.enter{value: 4 ether}(id, losing);

        _settle(id);

        uint256 pool = 8 ether - (8 ether / 100);
        uint256 a0 = alice.balance;
        vm.prank(alice);
        market.claim(id);
        assertEq(alice.balance - a0, pool * 3 / 4, "three quarters of the pool");

        uint256 s0 = address(this).balance;
        market.claim(id);
        assertEq(address(this).balance - s0, pool / 4, "one quarter");
    }

    function test_NoFundsAreStrandedBeyondDust() public {
        bytes32 id = _openMarket();
        Market.Side winning =
            closes[MARKET_END - START] > closes[MARKET_START - START] ? Market.Side.Up : Market.Side.Down;
        Market.Side losing = winning == Market.Side.Up ? Market.Side.Down : Market.Side.Up;

        // Deliberately awkward amounts so the pro-rata division cannot come out even.
        vm.prank(alice);
        market.enter{value: 1_000_000_000_000_000_001}(id, winning);
        vm.prank(address(this));
        market.enter{value: 333_333_333_333_333_333}(id, winning);
        vm.prank(bob);
        market.enter{value: 777_777_777_777_777_777}(id, losing);

        _settle(id);
        vm.prank(alice);
        market.claim(id);
        market.claim(id);

        vm.prank(creator);
        market.withdrawRake();

        // Truncation keeps a few wei. It must be a few wei, not a share.
        assertLt(address(market).balance, 100, "only truncation dust remains");
    }

    // ── voids ────────────────────────────────────────────────────────────────────────────────

    /// @dev A one-sided pot has nobody to pay from. The protocol refunds rather than keeping a
    /// stake it cannot match.
    function test_AOneSidedPotVoidsAndRefunds() public {
        bytes32 id = _openMarket();

        vm.prank(alice);
        market.enter{value: 2 ether}(id, Market.Side.Up);

        _settle(id);

        uint256 before = alice.balance;
        vm.prank(alice);
        market.claim(id);
        assertEq(alice.balance - before, 2 ether, "stake refunded in full");
        assertEq(market.rakeOwed(creator), 0, "no rake on a voided market");
    }

    // ── the fairness boundary ────────────────────────────────────────────────────────────────

    /// @dev Entry must close before the randomness that decides the outcome can exist.
    function test_EntryClosesOnceTheFloorReachesTheWindow() public {
        bytes32 id = _openMarket();

        vm.prank(alice);
        market.enter{value: 1 ether}(id, Market.Side.Up); // still open

        // Advance the floor to the market's own first round. From here the beacon output for that
        // round is provably public, so the book must be shut.
        _proveRound(MARKET_START);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Market.EntryClosed.selector, MARKET_START, MARKET_START));
        market.enter{value: 1 ether}(id, Market.Side.Down);
    }

    /// @dev **A known hazard, demonstrated rather than hidden.** The entry rule compares against
    /// the *proven floor*, so its guarantee is only as strong as the floor is fresh. With a floor
    /// far behind the beacon, this contract happily accepts a stake on a window whose outcome is
    /// already public — here the test stakes on rounds it has itself already derived.
    ///
    /// Spec v1.1 §8.5 calls floor freshness "an operator concern, not a safety one". This test is
    /// the counter-example: see `docs/findings/0001-floor-freshness.md`.
    function test_KnownHazard_AStaleFloorAdmitsStakesOnDecidedRounds() public {
        bytes32 id = _openMarket();

        // The floor sits at round 1000 while the market covers rounds ~21,173,062 onward — twenty
        // million rounds of beacon output that already exist.
        assertLt(entropy.provenFloor(), MARKET_START);

        vm.prank(alice);
        market.enter{value: 1 ether}(id, Market.Side.Up);

        assertEq(
            market.stakeOf(id, alice, Market.Side.Up),
            1 ether,
            "accepted: the rule passes because the floor, not the beacon, is the reference"
        );
    }

    // ── settlement rules ─────────────────────────────────────────────────────────────────────

    /// @dev Settling against a checkpoint that could still be disproved would pay out a lie
    /// before the fraud proof had a chance to catch it.
    function test_CannotSettleAgainstANonFinalisedEpoch() public {
        // A second Room whose epoch is posted but never finalised.
        RoomSpec.Spec memory other = _spec();
        other.param = 500e15;
        vm.prank(creator);
        registry.openRoom(other);

        bytes32 id = _openMarket();
        vm.prank(alice);
        market.enter{value: 1 ether}(id, Market.Side.Up);
        vm.prank(bob);
        market.enter{value: 1 ether}(id, Market.Side.Down);

        Ladder.LeafClaim memory s = _claim(MARKET_START);
        Ladder.LeafClaim memory e = _claim(MARKET_END);

        vm.expectRevert(abi.encodeWithSelector(Ladder.NotFinal.selector, Ladder.Status.None));
        market.settle(other, id, 0, s, 0, e);
    }

    function test_SettleRejectsTheWrongRounds() public {
        bytes32 id = _openMarket();
        vm.prank(alice);
        market.enter{value: 1 ether}(id, Market.Side.Up);
        vm.prank(bob);
        market.enter{value: 1 ether}(id, Market.Side.Down);

        Ladder.LeafClaim memory wrong = _claim(MARKET_START + 1);
        Ladder.LeafClaim memory e = _claim(MARKET_END);

        vm.expectRevert(abi.encodeWithSelector(Market.WrongRound.selector, MARKET_START, MARKET_START + 1));
        market.settle(_spec(), id, 0, wrong, 0, e);
    }

    function test_CannotClaimTwice() public {
        bytes32 id = _openMarket();
        vm.prank(alice);
        market.enter{value: 1 ether}(id, Market.Side.Up);
        _settle(id);

        vm.prank(alice);
        market.claim(id);
        vm.prank(alice);
        vm.expectRevert(Market.AlreadyClaimed.selector);
        market.claim(id);
    }

    function test_OpeningTheSameMarketTwiceIsRejected() public {
        bytes32 id = _openMarket();
        vm.expectRevert(abi.encodeWithSelector(Market.AlreadyOpen.selector, id));
        market.open(_spec(), MARKET_START, MARKET_END);
    }

    function test_RakeIsPublishedAndOnePercent() public view {
        assertEq(market.RAKE_BPS(), 100, "1.00%");
    }

    // ── conservation ────────────────────────────────────────────────────────────────────────

    /// @dev Everything staked leaves again: as payouts, as rake, or as truncation dust bounded by
    /// the number of claimants. A parimutuel market has no treasury and no house, so the only
    /// acceptable residue is the few wei integer division cannot distribute.
    function testFuzz_EverythingStakedIsAccountedFor(
        uint96 upA,
        uint96 upB,
        uint96 down
    ) public {
        uint256 a = 1e15 + (uint256(upA) % 5 ether);
        uint256 b = 1e15 + (uint256(upB) % 5 ether);
        uint256 d = 1e15 + (uint256(down) % 5 ether);

        vm.deal(alice, a);
        vm.deal(bob, d);
        vm.deal(address(this), b + 1 ether);

        bytes32 id = _openMarket();
        Market.Side winning =
            closes[MARKET_END - START] > closes[MARKET_START - START] ? Market.Side.Up : Market.Side.Down;
        Market.Side losing = winning == Market.Side.Up ? Market.Side.Down : Market.Side.Up;

        vm.prank(alice);
        market.enter{value: a}(id, winning);
        market.enter{value: b}(id, winning);
        vm.prank(bob);
        market.enter{value: d}(id, losing);

        uint256 pot = a + b + d;
        assertEq(address(market).balance, pot, "the pot is exactly what was staked");

        _settle(id);

        vm.prank(alice);
        market.claim(id);
        market.claim(id);
        vm.prank(creator);
        market.withdrawRake();

        // Two winners, so at most two units of truncation.
        assertLe(address(market).balance, 2, "only dust remains");
    }

    /// @dev A loser's stake funds the winners and nothing else. Checked explicitly because the
    /// payout formula is the one place a rounding error would quietly favour the contract.
    function test_ThePayoutPoolIsThePotLessRake() public {
        bytes32 id = _openMarket();
        Market.Side winning =
            closes[MARKET_END - START] > closes[MARKET_START - START] ? Market.Side.Up : Market.Side.Down;
        Market.Side losing = winning == Market.Side.Up ? Market.Side.Down : Market.Side.Up;

        vm.prank(alice);
        market.enter{value: 3 ether}(id, winning);
        vm.prank(bob);
        market.enter{value: 1 ether}(id, losing);
        _settle(id);

        (,,,,, uint128 payoutPool,,) = market.books(id);
        assertEq(uint256(payoutPool), 4 ether - (4 ether / 100), "pot less exactly the published rake");
        assertEq(market.rakeOwed(creator), 4 ether / 100, "and the rake is the remainder");
    }

    // ── the money must never be trapped ─────────────────────────────────────────────────────

    /// @dev Settlement needs a *finalised* epoch, and nothing obliges anyone to post one. Without
    /// a release path, a Room nobody checkpoints would hold its stakers' money permanently.
    function test_AnUnsettleableMarketReleasesItsStakes() public {
        // A market over a window in an epoch that will never be posted.
        uint64 start = START + EPOCH_ROUNDS + 2;
        uint64 end = start + 5;
        bytes32 id = market.open(_spec(), start, end);

        vm.prank(alice);
        market.enter{value: 2 ether}(id, Market.Side.Up);
        vm.prank(bob);
        market.enter{value: 1 ether}(id, Market.Side.Down);

        uint64 required = end + market.SETTLEMENT_GRACE();
        vm.expectRevert(
            abi.encodeWithSelector(Market.TooEarlyToVoid.selector, entropy.provenFloor(), required)
        );
        market.voidStale(_spec(), id);

        // The floor only rises by proof, so the grace period passes by a later round being
        // proven — there is no clock to advance.
        _advanceFloorTo("21250000", 21_250_000);
        assertGe(entropy.provenFloor(), required);

        market.voidStale(_spec(), id);

        uint256 a0 = alice.balance;
        vm.prank(alice);
        market.claim(id);
        assertEq(alice.balance - a0, 2 ether, "stake returned");

        uint256 b0 = bob.balance;
        vm.prank(bob);
        market.claim(id);
        assertEq(bob.balance - b0, 1 ether, "stake returned");
        assertEq(address(market).balance, 0, "nothing retained");
    }

    /// @dev A settleable market must not be voidable: discarding a real outcome because somebody
    /// was slow would be the protocol inventing a result, in the other direction.
    function test_ASettleableMarketCannotBeVoided() public {
        bytes32 id = _openMarket();
        vm.prank(alice);
        market.enter{value: 1 ether}(id, Market.Side.Up);

        _advanceFloorTo("21250000", 21_250_000);

        vm.expectRevert(Market.SettlementIsPossible.selector);
        market.voidStale(_spec(), id);
    }

    /// @dev A Room creator who cannot receive ether must not be able to freeze other people's
    /// money. The rake is credited and pulled, so settlement never depends on the creator's
    /// address behaving.
    function test_ACreatorWhoRejectsPaymentCannotBlockSettlement() public {
        RoomSpec.Spec memory hostile = _spec();
        hostile.param = 250e15;

        Rejector rejector = new Rejector();
        vm.prank(address(rejector));
        registry.openRoom(hostile);

        // Post and finalise the hostile Room's epoch so its markets can settle.
        _postAndFinalizeFor(hostile);

        bytes32 id = market.open(hostile, MARKET_START, MARKET_END);
        vm.prank(alice);
        market.enter{value: 1 ether}(id, Market.Side.Up);
        vm.prank(bob);
        market.enter{value: 1 ether}(id, Market.Side.Down);

        // Would revert if the rake were pushed to the creator.
        market.settle(hostile, id, 0, _claimFor(hostile, MARKET_START), 0, _claimFor(hostile, MARKET_END));

        assertGt(market.rakeOwed(address(rejector)), 0, "rake credited, not sent");
        vm.prank(address(rejector));
        vm.expectRevert(Market.TransferFailed.selector);
        market.withdrawRake();
    }

    // ── helpers ──────────────────────────────────────────────────────────────────────────────

    receive() external payable {}

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

    function _deriveEpoch() internal {
        Tick.Model memory model = Tick.compile(_spec());
        int256 price = _spec().initialPrice;
        for (uint256 i = 0; i < EPOCH_ROUNDS; i++) {
            (int256 c, int256 h, int256 l) = Tick.deriveRound(model, price, sha256(_sig(START + uint64(i))));
            closes.push(c);
            highs.push(h);
            lows.push(l);
            leaves.push(Merkle.leafHash(START + uint64(i), c, h, l));
            price = c;
        }
    }

    function _claim(
        uint64 round
    ) internal view returns (Ladder.LeafClaim memory c) {
        uint256 i = round - START;
        c.round = round;
        c.close = int128(closes[i]);
        c.high = int128(highs[i]);
        c.low = int128(lows[i]);
        c.path = Merkle.proof(_clone(leaves), i);
    }

    function _postAndFinalize() internal {
        bytes32 prior = RoomSpec.stateHash(
            RoomSpec.FAMILY_DRIFT, RoomSpec.State({price: 1000e18, level: 0, lo: 0, hi: 0})
        );
        bytes32 end = RoomSpec.stateHash(
            RoomSpec.FAMILY_DRIFT,
            RoomSpec.State({price: int128(closes[EPOCH_ROUNDS - 1]), level: 0, lo: 0, hi: 0})
        );
        Ladder.PostedLeaf[] memory published = new Ladder.PostedLeaf[](EPOCH_ROUNDS);
        for (uint256 i = 0; i < EPOCH_ROUNDS; i++) {
            published[i] = Ladder.PostedLeaf({
                round: START + uint64(i),
                close: int128(closes[i]),
                high: int128(highs[i]),
                low: int128(lows[i])
            });
        }
        ladder.post{value: BOND}(_spec(), 0, prior, end, published);

        string memory json = vm.readFile("test/fixtures/drand/rounds/1000.json");
        entropy.proveRound(1000, vm.parseJsonBytes(json, ".signature"));
        ladder.finalize(_spec(), 0, int128(closes[EPOCH_ROUNDS - 1]));
    }

    /// @dev Advances the floor to a pinned round, skipping if it is already past. The floor is
    /// monotone, so re-proving an old round reverts rather than quietly doing nothing.
    function _advanceFloorTo(
        string memory fixtureRound,
        uint64 round
    ) internal {
        if (entropy.provenFloor() >= round) return;
        string memory json = vm.readFile(string.concat("test/fixtures/drand/rounds/", fixtureRound, ".json"));
        entropy.proveRound(round, vm.parseJsonBytes(json, ".signature"));
    }

    function _proveRound(
        uint64 round
    ) internal {
        entropy.proveRound(round, _sig(round));
    }

    function _openMarket() internal returns (bytes32) {
        return market.open(_spec(), MARKET_START, MARKET_END);
    }

    function _settle(
        bytes32 id
    ) internal {
        market.settle(_spec(), id, 0, _claim(MARKET_START), 0, _claim(MARKET_END));
    }

    /// @dev Derives, posts and finalises epoch 0 for an arbitrary Room.
    function _postAndFinalizeFor(
        RoomSpec.Spec memory spec
    ) internal {
        Tick.Model memory model = Tick.compile(spec);
        Ladder.PostedLeaf[] memory published = new Ladder.PostedLeaf[](EPOCH_ROUNDS);
        int256 price = spec.initialPrice;

        for (uint256 i = 0; i < EPOCH_ROUNDS; i++) {
            (int256 c, int256 h, int256 l) = Tick.deriveRound(model, price, sha256(_sig(START + uint64(i))));
            published[i] = Ladder.PostedLeaf({
                round: START + uint64(i), close: int128(c), high: int128(h), low: int128(l)
            });
            price = c;
        }

        bytes32 prior = RoomSpec.stateHash(
            spec.family, RoomSpec.State({price: int128(spec.initialPrice), level: 0, lo: 0, hi: 0})
        );
        bytes32 end =
            RoomSpec.stateHash(spec.family, RoomSpec.State({price: int128(price), level: 0, lo: 0, hi: 0}));
        ladder.post{value: BOND}(spec, 0, prior, end, published);
        _advanceFloorTo("20880831", 20_880_831);
        ladder.finalize(spec, 0, int128(price));
    }

    /// @dev A proof of one round against an arbitrary Room's epoch 0.
    function _claimFor(
        RoomSpec.Spec memory spec,
        uint64 round
    ) internal view returns (Ladder.LeafClaim memory c) {
        Tick.Model memory model = Tick.compile(spec);
        bytes32[] memory hashes = new bytes32[](EPOCH_ROUNDS);
        int256 price = spec.initialPrice;
        uint256 want = round - START;

        for (uint256 i = 0; i < EPOCH_ROUNDS; i++) {
            (int256 cl, int256 h, int256 l) = Tick.deriveRound(model, price, sha256(_sig(START + uint64(i))));
            hashes[i] = Merkle.leafHash(START + uint64(i), cl, h, l);
            if (i == want) {
                c.round = round;
                c.close = int128(cl);
                c.high = int128(h);
                c.low = int128(l);
            }
            price = cl;
        }
        c.path = Merkle.proof(_clone(hashes), want);
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

/// @notice A Room creator that cannot receive ether. Its existence must not be anyone else's
/// problem.
contract Rejector {
    receive() external payable {
        revert("no");
    }
}
