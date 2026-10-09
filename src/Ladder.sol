// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Entropy} from "./Entropy.sol";
import {Merkle} from "./Merkle.sol";
import {Registry} from "./Registry.sol";
import {RoomSpec} from "./RoomSpec.sol";
import {Tick} from "./Tick.sol";

/// @title Ladder
/// @notice Epoch commitments and the fraud proof. The chain stores a 32-byte root per epoch, not
/// prices, and anyone who can show a root is wrong takes the poster's bond.
///
/// # Why there is no bisection, and no challenger bond
///
/// The reference plays a bisection game: challenger and poster halve a disputed range until they
/// disagree on one round. Bisection exists for games where the challenger **cannot cheaply compute
/// the truth** and must search for the divergence interactively.
///
/// That is not our situation. The derivation is deterministic and public, so a challenger running
/// the reference implementation already knows exactly which round diverges. And a correct epoch is
/// exactly one where:
///
/// 1. the first leaf follows from the previously finalised state,
/// 2. every leaf follows from the leaf before it, and
/// 3. the claimed end state matches the last leaf.
///
/// Each of those is **locally checkable in one transaction**. If a committed root is wrong, at
/// least one of them fails — so naming the failure is a complete disproof, not an approximation of
/// one. There is nothing bisection would find that a challenger with the reference cannot name
/// directly.
///
/// Two consequences, both good:
///
/// - **The proof is one shot and atomic.** A challenger submits the disproof itself, not a claim that they will later substantiate. An invalid disproof simply reverts.
/// - **The challenger posts no bond.** Bonds on both sides exist to punish stalling in a multi-round game. With no rounds to stall, there is nothing to punish, so watching costs nothing but gas — which is exactly the property the design wants, because the system's safety rests on someone bothering to watch.
///
/// Positions are bound by the round number *inside* each leaf rather than by position in the tree,
/// which matters because sorted-pair Merkle proofs cannot prove an index. A leaf says which round
/// it is, so a proof of membership is a proof about that round.
contract Ladder {
    enum Status {
        None,
        Pending,
        Final,
        Rejected
    }

    struct Checkpoint {
        bytes32 prevStateHash;
        bytes32 endStateHash;
        bytes32 merkleRoot;
        address poster;
        uint64 deadlineRound;
        Status status;
        uint96 bond;
    }

    /// @notice A Room's hot state, deliberately in **one slot**.
    /// @dev `int128` price plus `uint64` epoch is 192 bits, so both fields share a slot and a
    /// checkpoint operation pays **one** cold page touch of 8,000 gas rather than one per field.
    /// On Ethereum this packing would save 2,100 a field and be a nicety; here a cold page is
    /// 8,100 and scattering three fields across three pages costs 24,000 instead of 8,000
    /// (`bench/storage-paging.md`).
    ///
    /// `level`, `lo` and `hi` are not stored because neither shipped family ever leaves them at
    /// zero; `_state` reconstructs the full struct for hashing.
    struct RoomState {
        int128 finalPrice;
        uint64 nextEpoch;
    }

    Registry public immutable registry;
    Entropy public immutable entropy;

    /// @notice Bond a poster must escrow per checkpoint.
    uint256 public immutable bond;

    /// @notice The challenge window, **in beacon rounds above the proven floor**.
    /// @dev Never in seconds. A chain timestamp is an estimate of when a round existed, and on
    /// Monad it cannot distinguish adjacent blocks. Spec v1.1 Appendix C puts production at 30
    /// minutes (600 rounds); this is a constructor parameter so a demo deployment can use a window
    /// that elapses while someone is watching, and the writeup states both.
    uint64 public immutable challengeRounds;

    mapping(bytes32 roomId => RoomState) public roomState;
    mapping(bytes32 roomId => mapping(uint64 epoch => Checkpoint)) public checkpoints;

    event CheckpointPosted(
        bytes32 indexed roomId,
        uint64 indexed epoch,
        address indexed poster,
        bytes32 merkleRoot,
        uint64 deadlineRound,
        PostedLeaf[] leaves
    );
    event CheckpointFinalized(bytes32 indexed roomId, uint64 indexed epoch, int128 endPrice);
    event CheckpointRejected(
        bytes32 indexed roomId, uint64 indexed epoch, address indexed challenger, uint64 round, string reason
    );

    error RoomNotOpen(bytes32 roomId);
    error WrongEpoch(uint64 expected, uint64 given);
    error EpochAlreadyPosted(uint64 epoch, Status status);
    error WrongBond(uint256 expected, uint256 given);
    error WrongLeafCount(uint256 expected, uint256 given);
    error LeafOutOfOrder(uint64 expected, uint64 given);
    error PrevStateMismatch(bytes32 expected, bytes32 given);
    error NotPending(Status status);
    error NotFinal(Status status);
    error WindowOpen(uint64 provenFloor, uint64 deadlineRound);
    error WindowClosed(uint64 provenFloor, uint64 deadlineRound);
    error RoundOutOfEpoch(uint64 round);
    error LeafNotCommitted(uint64 round);
    error NotAdjacent(uint64 prevRound, uint64 round);
    error CheckpointIsHonest();
    error TransferFailed();

    constructor(
        Registry registry_,
        uint256 bond_,
        uint64 challengeRounds_
    ) {
        registry = registry_;
        entropy = registry_.entropy();
        bond = bond_;
        challengeRounds = challengeRounds_;
    }

    // ── posting and finalizing ───────────────────────────────────────────────────────────────

    /// @notice Commits an epoch of ticks, **publishing every round's result**. Permissionless.
    ///
    /// @dev The leaves are passed in full and the root is computed here rather than asserted by
    /// the poster. Three things follow, and the first is the reason this function does not simply
    /// take a root:
    ///
    /// **Data availability.** A disproof must exhibit a committed leaf with its Merkle path, and
    /// nobody can produce a path for a leaf they have never seen. A poster who committed only a
    /// root could withhold its preimages: a challenger re-deriving honestly would *know* the root
    /// was wrong and still be unable to prove it, the checkpoint would finalise, and from then on
    /// only the poster could produce `provenClose` proofs — which is to say, only the poster would
    /// decide what price settles a market.
    ///
    /// This is what the reference's bisection game provides implicitly: each round of that protocol
    /// forces the poster to disclose a midpoint. Replacing bisection with a one-shot disproof kept
    /// the completeness argument and removed the mechanism that made its premise true. Publishing
    /// the leaves restores it, at a cost of roughly 56 bytes of calldata per round.
    ///
    /// **Structural correctness by construction.** Rounds must be exactly the epoch's, in order,
    /// with no gaps, repeats or extras. A sorted-pair Merkle proof cannot bind a leaf's *position*,
    /// so a tree holding two different leaves for the same round would let both verify — and the
    /// poster would pick whichever suited them at settlement. Checked here, that tree cannot be
    /// committed at all.
    ///
    /// **The root cannot disagree with the leaves**, because it is derived from them.
    function post(
        RoomSpec.Spec calldata spec,
        uint64 epoch,
        bytes32 prevStateHash,
        bytes32 endStateHash,
        PostedLeaf[] calldata leaves
    ) external payable {
        bytes32 roomId = RoomSpec.roomId(spec);
        if (!registry.isOpen(roomId)) revert RoomNotOpen(roomId);
        if (msg.value != bond) revert WrongBond(bond, msg.value);

        RoomState memory rs = roomState[roomId];
        if (epoch != rs.nextEpoch) revert WrongEpoch(rs.nextEpoch, epoch);

        // A second post to a live epoch would overwrite the first checkpoint — replacing its
        // poster and zeroing the record of its bond, leaving that bond stranded and the first
        // poster unable to reclaim it. `nextEpoch` alone does not prevent this: it only advances
        // on finalize. A **rejected** epoch may be re-posted, since somebody still has to commit
        // the correct one and its bond has already gone to whoever disproved it.
        Status existing = checkpoints[roomId][epoch].status;
        if (existing != Status.None && existing != Status.Rejected) {
            revert EpochAlreadyPosted(epoch, existing);
        }

        bytes32 expectedPrev = _stateHashOf(spec.family, _priorState(spec, rs));
        if (prevStateHash != expectedPrev) revert PrevStateMismatch(expectedPrev, prevStateHash);

        bytes32 merkleRoot = _rootOf(spec, epoch, leaves);

        uint64 deadline = entropy.provenFloor() + challengeRounds;
        checkpoints[roomId][epoch] = Checkpoint({
            prevStateHash: prevStateHash,
            endStateHash: endStateHash,
            merkleRoot: merkleRoot,
            poster: msg.sender,
            deadlineRound: deadline,
            status: Status.Pending,
            bond: uint96(msg.value)
        });

        // Emitted as well as being in calldata, so an indexer never has to read transactions.
        emit CheckpointPosted(roomId, epoch, msg.sender, merkleRoot, deadline, leaves);
    }

    /// @dev Validates the shape of a published epoch and returns its root.
    function _rootOf(
        RoomSpec.Spec calldata spec,
        uint64 epoch,
        PostedLeaf[] calldata leaves
    ) private pure returns (bytes32) {
        if (leaves.length != spec.epochRounds) revert WrongLeafCount(spec.epochRounds, leaves.length);

        uint64 start = spec.genesisRound + epoch * spec.epochRounds;
        bytes32[] memory hashes = new bytes32[](leaves.length);
        for (uint256 i = 0; i < leaves.length; i++) {
            // Contiguous and ascending from the epoch's first round: no gaps, no repeats, no
            // leaves belonging to some other epoch.
            if (leaves[i].round != start + uint64(i)) {
                revert LeafOutOfOrder(start + uint64(i), leaves[i].round);
            }
            hashes[i] = Merkle.leafHash(leaves[i].round, leaves[i].close, leaves[i].high, leaves[i].low);
        }
        return Merkle.root(hashes);
    }

    /// @notice Settles an unchallenged checkpoint once the window has passed. Callable by anyone.
    /// @dev No privileged finalizer. The poster's bond returns to the poster regardless of who
    /// calls, so a stranger finalizing costs them only gas and benefits the system.
    function finalize(
        RoomSpec.Spec calldata spec,
        uint64 epoch,
        int128 endPrice
    ) external {
        bytes32 roomId = RoomSpec.roomId(spec);
        Checkpoint storage cp = checkpoints[roomId][epoch];
        if (cp.status != Status.Pending) revert NotPending(cp.status);

        uint64 floor = entropy.provenFloor();
        if (floor < cp.deadlineRound) revert WindowOpen(floor, cp.deadlineRound);

        // The caller supplies the end price; it is accepted only if it hashes to the committed end
        // state. The contract never has to be told anything it cannot check.
        RoomState memory candidate = RoomState({finalPrice: endPrice, nextEpoch: epoch + 1});
        if (_stateHashOf(spec.family, candidate) != cp.endStateHash) {
            revert PrevStateMismatch(cp.endStateHash, _stateHashOf(spec.family, candidate));
        }

        cp.status = Status.Final;
        roomState[roomId] = candidate;

        uint256 refund = cp.bond;
        cp.bond = 0;
        _pay(cp.poster, refund);

        emit CheckpointFinalized(roomId, epoch, endPrice);
    }

    // ── the fraud proof ──────────────────────────────────────────────────────────────────────

    /// @notice One round's result, as published by the poster.
    struct PostedLeaf {
        uint64 round;
        int128 close;
        int128 high;
        int128 low;
    }

    /// @notice A committed leaf and the Merkle path proving it belongs to the epoch's root.
    struct LeafClaim {
        uint64 round;
        int128 close;
        int128 high;
        int128 low;
        bytes32[] path;
    }

    /// @notice Disproves a checkpoint by naming two adjacent committed leaves where the second
    /// does not follow from the first. One shot, no bond, anyone.
    /// @param signature The beacon signature for `cur.round`, verified here. Supplying it is what
    /// makes the re-execution authoritative rather than a claim.
    function disproveTransition(
        RoomSpec.Spec calldata spec,
        uint64 epoch,
        LeafClaim calldata prev,
        LeafClaim calldata cur,
        bytes calldata signature
    ) external {
        bytes32 roomId = RoomSpec.roomId(spec);
        Checkpoint storage cp = _pendingOpen(roomId, epoch);

        if (cur.round != prev.round + 1) revert NotAdjacent(prev.round, cur.round);
        _requireInEpoch(spec, epoch, prev.round);
        _requireInEpoch(spec, epoch, cur.round);

        _requireCommitted(cp.merkleRoot, prev);
        _requireCommitted(cp.merkleRoot, cur);

        _rejectIfWrong(roomId, epoch, cp, spec, prev.close, cur, signature, "transition");
    }

    /// @notice Disproves a checkpoint whose **first** leaf does not follow from the state this
    /// contract already finalised.
    /// @dev The prior state comes from storage rather than from a leaf, which is why this is a
    /// separate entry point: at the epoch boundary there is no earlier leaf to compare against.
    function disproveFirstTransition(
        RoomSpec.Spec calldata spec,
        uint64 epoch,
        LeafClaim calldata first,
        bytes calldata signature
    ) external {
        bytes32 roomId = RoomSpec.roomId(spec);
        Checkpoint storage cp = _pendingOpen(roomId, epoch);

        uint64 start = spec.genesisRound + epoch * spec.epochRounds;
        if (first.round != start) revert RoundOutOfEpoch(first.round);
        _requireCommitted(cp.merkleRoot, first);

        _rejectIfWrong(
            roomId,
            epoch,
            cp,
            spec,
            _priorState(spec, roomState[roomId]).finalPrice,
            first,
            signature,
            "first"
        );
    }

    /// @notice Disproves a checkpoint whose claimed end state does not match its own last leaf.
    /// @dev No signature and no re-execution: this is a pure inconsistency between two things the
    /// poster committed to in the same transaction. The cheapest disproof available.
    function disproveEndState(
        RoomSpec.Spec calldata spec,
        uint64 epoch,
        LeafClaim calldata last
    ) external {
        bytes32 roomId = RoomSpec.roomId(spec);
        Checkpoint storage cp = _pendingOpen(roomId, epoch);

        uint64 end = spec.genesisRound + (epoch + 1) * spec.epochRounds - 1;
        if (last.round != end) revert RoundOutOfEpoch(last.round);
        _requireCommitted(cp.merkleRoot, last);

        RoomState memory claimed = RoomState({finalPrice: last.close, nextEpoch: epoch + 1});
        if (_stateHashOf(spec.family, claimed) == cp.endStateHash) revert CheckpointIsHonest();

        _reject(roomId, epoch, cp, last.round, "endState");
    }

    // ── reading a settled price ──────────────────────────────────────────────────────────────

    /// @notice The closing price of a round, proven against a **finalised** epoch.
    /// @dev This is how anything built on top of the ladder learns a price: not by being told one,
    /// but by being shown one with a proof. The chain stores a 32-byte root per epoch; the caller
    /// supplies the leaf and its path, and the contract checks them.
    ///
    /// Only finalised epochs count. A pending checkpoint might still be thrown out, and settling a
    /// market against a root that later turns out to be a lie would make the fraud proof pointless
    /// — the lie would already have been paid out.
    function provenClose(
        RoomSpec.Spec calldata spec,
        uint64 epoch,
        LeafClaim calldata claim
    ) external view returns (int128) {
        bytes32 roomId = RoomSpec.roomId(spec);
        Checkpoint storage cp = checkpoints[roomId][epoch];
        if (cp.status != Status.Final) revert NotFinal(cp.status);

        _requireInEpoch(spec, epoch, claim.round);
        _requireCommitted(cp.merkleRoot, claim);
        return claim.close;
    }

    // ── internals ────────────────────────────────────────────────────────────────────────────

    function _rejectIfWrong(
        bytes32 roomId,
        uint64 epoch,
        Checkpoint storage cp,
        RoomSpec.Spec calldata spec,
        int128 priceBefore,
        LeafClaim calldata cur,
        bytes calldata signature,
        string memory reason
    ) private {
        bytes32 randomness = entropy.verifyRound(cur.round, signature);

        Tick.Model memory model = Tick.compile(spec);
        (int256 close, int256 high, int256 low) = Tick.deriveRound(model, priceBefore, randomness);

        // The poster is honest about this transition, so there is nothing to disprove here. The
        // challenger pays gas and the checkpoint stands.
        if (close == cur.close && high == cur.high && low == cur.low) revert CheckpointIsHonest();

        _reject(roomId, epoch, cp, cur.round, reason);
    }

    function _reject(
        bytes32 roomId,
        uint64 epoch,
        Checkpoint storage cp,
        uint64 round,
        string memory reason
    ) private {
        cp.status = Status.Rejected;
        uint256 forfeit = cp.bond;
        cp.bond = 0;
        _pay(msg.sender, forfeit);

        emit CheckpointRejected(roomId, epoch, msg.sender, round, reason);
    }

    function _pendingOpen(
        bytes32 roomId,
        uint64 epoch
    ) private view returns (Checkpoint storage cp) {
        cp = checkpoints[roomId][epoch];
        if (cp.status != Status.Pending) revert NotPending(cp.status);

        uint64 floor = entropy.provenFloor();
        if (floor >= cp.deadlineRound) revert WindowClosed(floor, cp.deadlineRound);
    }

    function _requireInEpoch(
        RoomSpec.Spec calldata spec,
        uint64 epoch,
        uint64 round
    ) private pure {
        uint64 start = spec.genesisRound + epoch * spec.epochRounds;
        if (round < start || round >= start + spec.epochRounds) revert RoundOutOfEpoch(round);
    }

    function _requireCommitted(
        bytes32 root,
        LeafClaim calldata claim
    ) private pure {
        bytes32 leaf = Merkle.leafHash(claim.round, claim.close, claim.high, claim.low);
        if (!Merkle.verify(root, leaf, claim.path)) revert LeafNotCommitted(claim.round);
    }

    /// @notice The state an epoch starts from.
    /// @dev Before epoch 0 finalises there is no stored state, and the prior price is the Room's
    /// `initialPrice` — which lives in the spec, because the spec *is* the Room. Reading the empty
    /// slot instead would have the contract expect a prior price of zero for every Room's first
    /// epoch, so no honest first checkpoint could ever be posted.
    function _priorState(
        RoomSpec.Spec calldata spec,
        RoomState memory rs
    ) private pure returns (RoomState memory) {
        if (rs.nextEpoch != 0) return rs;
        // The registry bounds initialPrice to PRICE_MAX (1e38), inside int128.
        return RoomState({finalPrice: int128(spec.initialPrice), nextEpoch: 0});
    }

    /// @dev Reconstructs the reference's full state struct for hashing. `level`, `lo` and `hi`
    /// are zero for both shipped families, so they are not stored — but they *are* hashed, because
    /// the encoding is frozen and must match the other implementations byte for byte.
    ///
    /// The family is taken from the caller's spec rather than storage. It has to be: the state
    /// hash binds the family, so a Step room and a Drift room at the same price hash differently,
    /// and an earlier draft that assumed Drift would have silently mis-hashed every Step room.
    function _stateHashOf(
        uint8 family,
        RoomState memory rs
    ) private pure returns (bytes32) {
        return RoomSpec.stateHash(family, RoomSpec.State({price: rs.finalPrice, level: 0, lo: 0, hi: 0}));
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
