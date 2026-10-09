// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "./Entropy.sol";
import {Ladder} from "./Ladder.sol";
import {Registry} from "./Registry.sol";
import {RoomSpec} from "./RoomSpec.sol";

/// @title Market
/// @notice Parimutuel rounds on a Room's direction. Participants face each other; the protocol
/// takes a published rake and never takes a side.
///
/// # Why parimutuel
///
/// There is no vault, no house, and **no protocol risk**: payouts come out of the pot, so they
/// cannot exceed it. No capital is required to launch a market on any Room, which is what makes
/// the registry's permissionless supply useful rather than decorative.
///
/// # The fairness mechanism
///
/// Entry closes before the randomness that decides the outcome exists. A stake is accepted only
/// while `provenFloor + ENTRY_BUFFER <= startRound`, so by the time anyone could know the beacon
/// output for the market's first round, the book is shut.
///
/// That guarantee is only as strong as the floor is fresh. A floor far behind the beacon admits
/// stakes on rounds whose outcome is already public — a **safety** property, not a cosmetic one.
/// See `docs/findings/0001-floor-freshness.md`, and the test that demonstrates it.
///
/// # Settlement
///
/// Nobody tells this contract a price. A settler shows it two prices, each with a Merkle proof
/// against a **finalised** epoch of the ladder. Pending checkpoints are refused: paying out
/// against a root that might still be disproved would make the fraud proof pointless, because the
/// lie would already have been cashed.
contract Market {
    enum Side {
        Up,
        Down
    }

    enum State {
        None,
        Open,
        Settled,
        Void
    }

    struct Book {
        bytes32 roomId;
        uint64 startRound;
        uint64 endRound;
        uint128 upTotal;
        uint128 downTotal;
        uint128 payoutPool;
        State state;
        Side winner;
    }

    Registry public immutable registry;
    Ladder public immutable ladder;
    Entropy public immutable entropy;

    /// @notice The only fee, in basis points. Spec v1.1 §9.1's default of 1.0%.
    /// @dev Published as a constant, shown before every stake, not buried. 1% rather than more for
    /// the reason the spec gives: lifetime value works out to bankroll ÷ velocity, so the rake
    /// cancels — a higher one extracts the same amount faster and ends the relationship sooner.
    uint256 public constant RAKE_BPS = 100;

    /// @notice `B` — how far above the proven floor a market's first round must sit at entry.
    uint64 public constant ENTRY_BUFFER = 2;

    mapping(bytes32 marketId => Book) public books;
    mapping(bytes32 marketId => mapping(address staker => mapping(Side side => uint128))) public stakeOf;
    mapping(bytes32 marketId => mapping(address staker => bool)) public claimed;

    event MarketOpened(bytes32 indexed marketId, bytes32 indexed roomId, uint64 startRound, uint64 endRound);
    event Staked(bytes32 indexed marketId, address indexed staker, Side side, uint128 amount);
    event Settled(bytes32 indexed marketId, Side winner, int128 startClose, int128 endClose, uint128 rake);
    event Voided(bytes32 indexed marketId, string reason);
    event Claimed(bytes32 indexed marketId, address indexed staker, uint256 amount);

    error RoomNotOpen(bytes32 roomId);
    error BadWindow(uint64 startRound, uint64 endRound);
    error AlreadyOpen(bytes32 marketId);
    error NotOpen(State state);
    error EntryClosed(uint64 provenFloor, uint64 startRound);
    error NothingStaked();
    error AlreadyClaimed();
    error NothingToClaim();
    error WrongRound(uint64 expected, uint64 given);
    error TransferFailed();

    constructor(
        Ladder ladder_
    ) {
        ladder = ladder_;
        registry = ladder_.registry();
        entropy = ladder_.entropy();
    }

    function marketId(
        bytes32 roomId,
        uint64 startRound,
        uint64 endRound
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(roomId, startRound, endRound));
    }

    /// @notice Opens a market over `[startRound, endRound]`. Permissionless.
    function open(
        RoomSpec.Spec calldata spec,
        uint64 startRound,
        uint64 endRound
    ) external returns (bytes32 id) {
        bytes32 roomId = RoomSpec.roomId(spec);
        if (!registry.isOpen(roomId)) revert RoomNotOpen(roomId);
        if (endRound <= startRound || startRound < spec.genesisRound) revert BadWindow(startRound, endRound);

        uint64 floor = entropy.provenFloor();
        if (startRound < floor + ENTRY_BUFFER) revert EntryClosed(floor, startRound);

        id = marketId(roomId, startRound, endRound);
        if (books[id].state != State.None) revert AlreadyOpen(id);

        books[id] = Book({
            roomId: roomId,
            startRound: startRound,
            endRound: endRound,
            upTotal: 0,
            downTotal: 0,
            payoutPool: 0,
            state: State.Open,
            winner: Side.Up
        });

        emit MarketOpened(id, roomId, startRound, endRound);
    }

    /// @notice Stakes on a direction. Closes `ENTRY_BUFFER` rounds before the market's first round.
    function enter(
        bytes32 id,
        Side side
    ) external payable {
        Book storage b = books[id];
        if (b.state != State.Open) revert NotOpen(b.state);
        if (msg.value == 0) revert NothingStaked();

        // The fairness guarantee, and the only thing between this market and a bet on a known
        // outcome.
        uint64 floor = entropy.provenFloor();
        if (floor + ENTRY_BUFFER > b.startRound) revert EntryClosed(floor, b.startRound);

        uint128 amount = uint128(msg.value);
        if (side == Side.Up) {
            b.upTotal += amount;
        } else {
            b.downTotal += amount;
        }
        stakeOf[id][msg.sender][side] += amount;

        emit Staked(id, msg.sender, side, amount);
    }

    /// @notice Settles against two prices, each proven against a finalised epoch. Anyone may call.
    function settle(
        RoomSpec.Spec calldata spec,
        bytes32 id,
        uint64 startEpoch,
        Ladder.LeafClaim calldata startClaim,
        uint64 endEpoch,
        Ladder.LeafClaim calldata endClaim
    ) external {
        Book storage b = books[id];
        if (b.state != State.Open) revert NotOpen(b.state);
        if (startClaim.round != b.startRound) revert WrongRound(b.startRound, startClaim.round);
        if (endClaim.round != b.endRound) revert WrongRound(b.endRound, endClaim.round);

        // A one-sided pot has nobody to pay from. Refunding is the honest outcome; the protocol
        // never keeps a stake it cannot match.
        if (b.upTotal == 0 || b.downTotal == 0) {
            b.state = State.Void;
            emit Voided(id, "one-sided");
            return;
        }

        int128 startClose = ladder.provenClose(spec, startEpoch, startClaim);
        int128 endClose = ladder.provenClose(spec, endEpoch, endClaim);

        // A dead flat window has no winner. Picking a side would be the protocol inventing a
        // result the beacon did not produce.
        if (endClose == startClose) {
            b.state = State.Void;
            emit Voided(id, "flat");
            return;
        }

        Side winner = endClose > startClose ? Side.Up : Side.Down;
        uint256 pot = uint256(b.upTotal) + uint256(b.downTotal);
        uint256 rake = (pot * RAKE_BPS) / 10_000;

        b.winner = winner;
        b.payoutPool = uint128(pot - rake);
        b.state = State.Settled;

        // The rake goes to the Room's creator — the supply-side incentive that makes the registry
        // generate its own supply (spec v1.1 §7.3). The protocol's full four-way split
        // (treasury / creator / jackpot / operations) is **not** implemented in this port; the
        // creator share is, because it is the one the registry depends on.
        _pay(registry.creatorOf(b.roomId), rake);

        emit Settled(id, winner, startClose, endClose, uint128(rake));
    }

    /// @notice Claims a winning share, or a refund from a voided market.
    function claim(
        bytes32 id
    ) external {
        Book storage b = books[id];
        if (b.state != State.Settled && b.state != State.Void) revert NotOpen(b.state);
        if (claimed[id][msg.sender]) revert AlreadyClaimed();

        uint256 amount;
        if (b.state == State.Void) {
            amount = uint256(stakeOf[id][msg.sender][Side.Up]) + uint256(stakeOf[id][msg.sender][Side.Down]);
        } else {
            uint128 stake = stakeOf[id][msg.sender][b.winner];
            uint128 winnerTotal = b.winner == Side.Up ? b.upTotal : b.downTotal;
            // Truncates, so a few wei of dust stays here rather than the last claimant failing
            // for want of one.
            amount = (uint256(stake) * uint256(b.payoutPool)) / uint256(winnerTotal);
        }

        if (amount == 0) revert NothingToClaim();
        claimed[id][msg.sender] = true;
        _pay(msg.sender, amount);

        emit Claimed(id, msg.sender, amount);
    }

    /// @notice What a stake of `amount` would pay if the market settled this way, rake included.
    /// @dev A view, so an interface can show the odds before anyone commits. The odds move as the
    /// pot does: that is what parimutuel means, and it is shown rather than implied.
    function quote(
        bytes32 id,
        Side side,
        uint128 amount
    ) external view returns (uint256) {
        Book storage b = books[id];
        uint256 pot = uint256(b.upTotal) + uint256(b.downTotal) + amount;
        uint256 sideTotal = (side == Side.Up ? uint256(b.upTotal) : uint256(b.downTotal)) + amount;
        if (sideTotal == 0) return 0;
        return (uint256(amount) * (pot - (pot * RAKE_BPS) / 10_000)) / sideTotal;
    }

    function _pay(
        address to,
        uint256 amount
    ) private {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
