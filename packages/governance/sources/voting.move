/// @title Voting
/// @notice Vote tracking and management
/// @dev Part of @sui-starters/governance package
module sui_starters_governance::voting {
    use sui::event;
    use sui::table::{Self, Table};

    // === Errors ===

    const EAlreadyVoted: u64 = 0;
    const ENotVoted: u64 = 1;
    const EVotingEnded: u64 = 2;
    const EInvalidVoteType: u64 = 3;

    // === Constants ===

    const VOTE_AGAINST: u8 = 0;
    const VOTE_FOR: u8 = 1;
    const VOTE_ABSTAIN: u8 = 2;

    // === Structs ===

    /// Voting tracker for a proposal
    public struct VoteTracker has key, store {
        id: UID,
        proposal_id: ID,
        /// Voter -> vote info (vote_type, power)
        votes: Table<address, VoteInfo>,
        /// Total for votes
        total_for: u64,
        /// Total against votes
        total_against: u64,
        /// Total abstain votes
        total_abstain: u64,
        /// Total unique voters
        voter_count: u64,
        /// Voting end epoch
        end_epoch: u64,
    }

    /// Individual vote info
    public struct VoteInfo has store, copy, drop {
        vote_type: u8,
        power: u64,
        epoch: u64,
    }

    // === Events ===

    public struct VoteCast has copy, drop {
        proposal_id: ID,
        voter: address,
        vote_type: u8,
        power: u64,
    }

    public struct VoteChanged has copy, drop {
        proposal_id: ID,
        voter: address,
        old_vote_type: u8,
        new_vote_type: u8,
        power: u64,
    }

    // === Create Functions ===

    /// Create vote tracker for proposal
    public fun new(
        proposal_id: ID,
        end_epoch: u64,
        ctx: &mut TxContext,
    ): VoteTracker {
        VoteTracker {
            id: object::new(ctx),
            proposal_id,
            votes: table::new(ctx),
            total_for: 0,
            total_against: 0,
            total_abstain: 0,
            voter_count: 0,
            end_epoch,
        }
    }

    // === Core Functions ===

    /// Cast a vote
    public fun cast_vote(
        tracker: &mut VoteTracker,
        voter: address,
        vote_type: u8,
        power: u64,
        ctx: &TxContext,
    ) {
        assert!(ctx.epoch() <= tracker.end_epoch, EVotingEnded);
        assert!(vote_type <= VOTE_ABSTAIN, EInvalidVoteType);
        assert!(!table::contains(&tracker.votes, voter), EAlreadyVoted);

        // Record vote
        table::add(&mut tracker.votes, voter, VoteInfo {
            vote_type,
            power,
            epoch: ctx.epoch(),
        });

        // Update totals
        if (vote_type == VOTE_FOR) {
            tracker.total_for = tracker.total_for + power;
        } else if (vote_type == VOTE_AGAINST) {
            tracker.total_against = tracker.total_against + power;
        } else {
            tracker.total_abstain = tracker.total_abstain + power;
        };

        tracker.voter_count = tracker.voter_count + 1;

        event::emit(VoteCast {
            proposal_id: tracker.proposal_id,
            voter,
            vote_type,
            power,
        });
    }

    /// Change vote (same power, different type)
    public fun change_vote(
        tracker: &mut VoteTracker,
        voter: address,
        new_vote_type: u8,
        ctx: &TxContext,
    ) {
        assert!(ctx.epoch() <= tracker.end_epoch, EVotingEnded);
        assert!(new_vote_type <= VOTE_ABSTAIN, EInvalidVoteType);
        assert!(table::contains(&tracker.votes, voter), ENotVoted);

        let vote_info = table::borrow_mut(&mut tracker.votes, voter);
        let old_vote_type = vote_info.vote_type;
        let power = vote_info.power;

        // Remove from old total
        if (old_vote_type == VOTE_FOR) {
            tracker.total_for = tracker.total_for - power;
        } else if (old_vote_type == VOTE_AGAINST) {
            tracker.total_against = tracker.total_against - power;
        } else {
            tracker.total_abstain = tracker.total_abstain - power;
        };

        // Add to new total
        if (new_vote_type == VOTE_FOR) {
            tracker.total_for = tracker.total_for + power;
        } else if (new_vote_type == VOTE_AGAINST) {
            tracker.total_against = tracker.total_against + power;
        } else {
            tracker.total_abstain = tracker.total_abstain + power;
        };

        vote_info.vote_type = new_vote_type;
        vote_info.epoch = ctx.epoch();

        event::emit(VoteChanged {
            proposal_id: tracker.proposal_id,
            voter,
            old_vote_type,
            new_vote_type,
            power,
        });
    }

    // === View Functions ===

    /// Has voted
    public fun has_voted(tracker: &VoteTracker, voter: address): bool {
        table::contains(&tracker.votes, voter)
    }

    /// Get vote info for voter
    public fun get_vote(tracker: &VoteTracker, voter: address): (u8, u64) {
        let info = table::borrow(&tracker.votes, voter);
        (info.vote_type, info.power)
    }

    /// Get totals
    public fun totals(tracker: &VoteTracker): (u64, u64, u64) {
        (tracker.total_for, tracker.total_against, tracker.total_abstain)
    }

    /// Get total votes
    public fun total_votes(tracker: &VoteTracker): u64 {
        tracker.total_for + tracker.total_against + tracker.total_abstain
    }

    /// Get voter count
    public fun voter_count(tracker: &VoteTracker): u64 {
        tracker.voter_count
    }

    /// Is voting ended
    public fun is_ended(tracker: &VoteTracker, current_epoch: u64): bool {
        current_epoch > tracker.end_epoch
    }

    /// Did proposal pass (for > against)
    public fun is_passing(tracker: &VoteTracker): bool {
        tracker.total_for > tracker.total_against
    }

    /// Vote type constants
    public fun vote_against(): u8 { VOTE_AGAINST }
    public fun vote_for(): u8 { VOTE_FOR }
    public fun vote_abstain(): u8 { VOTE_ABSTAIN }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_tracker() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let proposal_id = object::id_from_address(@0x123);
            let tracker = new(proposal_id, 100, scenario.ctx());

            assert!(total_votes(&tracker) == 0, 0);
            assert!(voter_count(&tracker) == 0, 1);

            transfer::public_share_object(tracker);
        };

        scenario.end();
    }

    #[test]
    fun test_cast_vote() {
        let admin = @0xAD;
        let voter1 = @0x1;
        let voter2 = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // Create tracker
        {
            let proposal_id = object::id_from_address(@0x123);
            let tracker = new(proposal_id, 100, scenario.ctx());
            transfer::public_share_object(tracker);
        };

        // Voter 1 votes for
        scenario.next_tx(voter1);
        {
            let mut tracker = scenario.take_shared<VoteTracker>();
            cast_vote(&mut tracker, voter1, VOTE_FOR, 100, scenario.ctx());

            assert!(has_voted(&tracker, voter1), 0);
            let (vote_type, power) = get_vote(&tracker, voter1);
            assert!(vote_type == VOTE_FOR, 1);
            assert!(power == 100, 2);

            test_scenario::return_shared(tracker);
        };

        // Voter 2 votes against
        scenario.next_tx(voter2);
        {
            let mut tracker = scenario.take_shared<VoteTracker>();
            cast_vote(&mut tracker, voter2, VOTE_AGAINST, 50, scenario.ctx());

            let (for_votes, against, _) = totals(&tracker);
            assert!(for_votes == 100, 3);
            assert!(against == 50, 4);
            assert!(voter_count(&tracker) == 2, 5);
            assert!(is_passing(&tracker), 6);

            test_scenario::return_shared(tracker);
        };

        scenario.end();
    }

    #[test]
    fun test_change_vote() {
        let admin = @0xAD;
        let voter = @0x3;
        let mut scenario = test_scenario::begin(admin);

        // Create tracker
        {
            let proposal_id = object::id_from_address(@0x123);
            let tracker = new(proposal_id, 100, scenario.ctx());
            transfer::public_share_object(tracker);
        };

        // Cast initial vote
        scenario.next_tx(voter);
        {
            let mut tracker = scenario.take_shared<VoteTracker>();
            cast_vote(&mut tracker, voter, VOTE_FOR, 100, scenario.ctx());
            test_scenario::return_shared(tracker);
        };

        // Change vote
        scenario.next_tx(voter);
        {
            let mut tracker = scenario.take_shared<VoteTracker>();
            change_vote(&mut tracker, voter, VOTE_AGAINST, scenario.ctx());

            let (for_votes, against, _) = totals(&tracker);
            assert!(for_votes == 0, 0);
            assert!(against == 100, 1);

            test_scenario::return_shared(tracker);
        };

        scenario.end();
    }
}
