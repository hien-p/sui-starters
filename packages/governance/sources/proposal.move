/// @title Proposal
/// @notice Governance proposal creation and management
/// @dev Part of @sui-starters/governance package
module sui_starters_governance::proposal {
    use std::string::String;
    use sui::event;

    // === Errors ===

    const EInvalidStatus: u64 = 0;
    const ENotProposer: u64 = 1;
    const EVotingNotEnded: u64 = 2;
    const EProposalExpired: u64 = 3;
    const EAlreadyExecuted: u64 = 4;

    // === Constants ===

    const STATUS_ACTIVE: u8 = 0;
    const STATUS_PASSED: u8 = 1;
    const STATUS_FAILED: u8 = 2;
    const STATUS_EXECUTED: u8 = 3;
    const STATUS_CANCELLED: u8 = 4;

    // === Structs ===

    /// Governance proposal
    public struct Proposal has key, store {
        id: UID,
        /// Proposal number
        proposal_id: u64,
        /// Proposer address
        proposer: address,
        /// Title
        title: String,
        /// Description
        description: String,
        /// For votes
        votes_for: u64,
        /// Against votes
        votes_against: u64,
        /// Abstain votes
        votes_abstain: u64,
        /// Start epoch
        start_epoch: u64,
        /// End epoch
        end_epoch: u64,
        /// Execution epoch (after timelock)
        execution_epoch: u64,
        /// Current status
        status: u8,
    }

    /// Vote receipt
    public struct VoteReceipt has key, store {
        id: UID,
        proposal_id: ID,
        voter: address,
        /// 0=against, 1=for, 2=abstain
        vote_type: u8,
        voting_power: u64,
    }

    // === Events ===

    public struct ProposalCreated has copy, drop {
        proposal_id: ID,
        proposal_number: u64,
        proposer: address,
        title: String,
        start_epoch: u64,
        end_epoch: u64,
    }

    public struct ProposalStatusChanged has copy, drop {
        proposal_id: ID,
        old_status: u8,
        new_status: u8,
    }

    // === Create Functions ===

    /// Create new proposal
    public fun new(
        proposal_number: u64,
        title: String,
        description: String,
        voting_period: u64,
        execution_delay: u64,
        ctx: &mut TxContext,
    ): Proposal {
        let start_epoch = ctx.epoch();
        let end_epoch = start_epoch + voting_period;
        let execution_epoch = end_epoch + execution_delay;

        let proposal = Proposal {
            id: object::new(ctx),
            proposal_id: proposal_number,
            proposer: ctx.sender(),
            title,
            description,
            votes_for: 0,
            votes_against: 0,
            votes_abstain: 0,
            start_epoch,
            end_epoch,
            execution_epoch,
            status: STATUS_ACTIVE,
        };

        event::emit(ProposalCreated {
            proposal_id: object::id(&proposal),
            proposal_number,
            proposer: ctx.sender(),
            title: proposal.title,
            start_epoch,
            end_epoch,
        });

        proposal
    }

    // === Voting Functions ===

    /// Cast vote on proposal
    public fun vote(
        proposal: &mut Proposal,
        vote_type: u8, // 0=against, 1=for, 2=abstain
        voting_power: u64,
        ctx: &mut TxContext,
    ): VoteReceipt {
        assert!(proposal.status == STATUS_ACTIVE, EInvalidStatus);
        assert!(ctx.epoch() <= proposal.end_epoch, EProposalExpired);

        // Add votes
        if (vote_type == 0) {
            proposal.votes_against = proposal.votes_against + voting_power;
        } else if (vote_type == 1) {
            proposal.votes_for = proposal.votes_for + voting_power;
        } else {
            proposal.votes_abstain = proposal.votes_abstain + voting_power;
        };

        VoteReceipt {
            id: object::new(ctx),
            proposal_id: object::id(proposal),
            voter: ctx.sender(),
            vote_type,
            voting_power,
        }
    }

    /// Finalize proposal after voting ends
    public fun finalize(
        proposal: &mut Proposal,
        quorum: u64,
        ctx: &TxContext,
    ) {
        assert!(proposal.status == STATUS_ACTIVE, EInvalidStatus);
        assert!(ctx.epoch() > proposal.end_epoch, EVotingNotEnded);

        let total_votes = proposal.votes_for + proposal.votes_against + proposal.votes_abstain;
        let old_status = proposal.status;

        // Check quorum and majority
        if (total_votes >= quorum && proposal.votes_for > proposal.votes_against) {
            proposal.status = STATUS_PASSED;
        } else {
            proposal.status = STATUS_FAILED;
        };

        event::emit(ProposalStatusChanged {
            proposal_id: object::id(proposal),
            old_status,
            new_status: proposal.status,
        });
    }

    /// Mark proposal as executed
    public fun mark_executed(
        proposal: &mut Proposal,
        ctx: &TxContext,
    ) {
        assert!(proposal.status == STATUS_PASSED, EInvalidStatus);
        assert!(ctx.epoch() >= proposal.execution_epoch, EInvalidStatus);

        let old_status = proposal.status;
        proposal.status = STATUS_EXECUTED;

        event::emit(ProposalStatusChanged {
            proposal_id: object::id(proposal),
            old_status,
            new_status: STATUS_EXECUTED,
        });
    }

    /// Cancel proposal (by proposer)
    public fun cancel(
        proposal: &mut Proposal,
        ctx: &TxContext,
    ) {
        assert!(proposal.status == STATUS_ACTIVE, EInvalidStatus);
        assert!(ctx.sender() == proposal.proposer, ENotProposer);

        let old_status = proposal.status;
        proposal.status = STATUS_CANCELLED;

        event::emit(ProposalStatusChanged {
            proposal_id: object::id(proposal),
            old_status,
            new_status: STATUS_CANCELLED,
        });
    }

    // === View Functions ===

    /// Get proposal status
    public fun status(proposal: &Proposal): u8 {
        proposal.status
    }

    /// Get vote counts
    public fun vote_counts(proposal: &Proposal): (u64, u64, u64) {
        (proposal.votes_for, proposal.votes_against, proposal.votes_abstain)
    }

    /// Get total votes
    public fun total_votes(proposal: &Proposal): u64 {
        proposal.votes_for + proposal.votes_against + proposal.votes_abstain
    }

    /// Is voting active
    public fun is_voting_active(proposal: &Proposal, current_epoch: u64): bool {
        proposal.status == STATUS_ACTIVE &&
        current_epoch >= proposal.start_epoch &&
        current_epoch <= proposal.end_epoch
    }

    /// Is ready to execute
    public fun is_executable(proposal: &Proposal, current_epoch: u64): bool {
        proposal.status == STATUS_PASSED && current_epoch >= proposal.execution_epoch
    }

    /// Get proposer
    public fun proposer(proposal: &Proposal): address {
        proposal.proposer
    }

    /// Get proposal number
    public fun proposal_number(proposal: &Proposal): u64 {
        proposal.proposal_id
    }

    /// Get voting period
    public fun voting_period(proposal: &Proposal): (u64, u64) {
        (proposal.start_epoch, proposal.end_epoch)
    }

    /// Get execution epoch
    public fun execution_epoch(proposal: &Proposal): u64 {
        proposal.execution_epoch
    }

    /// Get receipt info
    public fun receipt_info(receipt: &VoteReceipt): (address, u8, u64) {
        (receipt.voter, receipt.vote_type, receipt.voting_power)
    }

    /// Status constants
    public fun status_active(): u8 { STATUS_ACTIVE }
    public fun status_passed(): u8 { STATUS_PASSED }
    public fun status_failed(): u8 { STATUS_FAILED }
    public fun status_executed(): u8 { STATUS_EXECUTED }
    public fun status_cancelled(): u8 { STATUS_CANCELLED }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use std::string;

    #[test]
    fun test_create_proposal() {
        let proposer = @0x1;
        let mut scenario = test_scenario::begin(proposer);

        {
            let proposal = new(
                1,
                string::utf8(b"Test Proposal"),
                string::utf8(b"Description"),
                7,
                2,
                scenario.ctx(),
            );

            assert!(status(&proposal) == STATUS_ACTIVE, 0);
            assert!(proposal_number(&proposal) == 1, 1);
            assert!(proposer(&proposal) == proposer, 2);

            transfer::public_share_object(proposal);
        };

        scenario.end();
    }

    #[test]
    fun test_vote() {
        let proposer = @0x1;
        let voter = @0x2;
        let mut scenario = test_scenario::begin(proposer);

        // Create proposal
        {
            let proposal = new(
                1,
                string::utf8(b"Test Proposal"),
                string::utf8(b"Description"),
                7,
                2,
                scenario.ctx(),
            );
            transfer::public_share_object(proposal);
        };

        // Vote
        scenario.next_tx(voter);
        {
            let mut proposal = scenario.take_shared<Proposal>();

            let receipt = vote(&mut proposal, 1, 100, scenario.ctx()); // Vote for

            let (for_votes, against, abstain) = vote_counts(&proposal);
            assert!(for_votes == 100, 0);
            assert!(against == 0, 1);
            assert!(abstain == 0, 2);

            transfer::public_transfer(receipt, voter);
            test_scenario::return_shared(proposal);
        };

        scenario.end();
    }

    #[test]
    fun test_cancel_proposal() {
        let proposer = @0x1;
        let mut scenario = test_scenario::begin(proposer);

        {
            let mut proposal = new(
                1,
                string::utf8(b"Test Proposal"),
                string::utf8(b"Description"),
                7,
                2,
                scenario.ctx(),
            );

            cancel(&mut proposal, scenario.ctx());
            assert!(status(&proposal) == STATUS_CANCELLED, 0);

            transfer::public_share_object(proposal);
        };

        scenario.end();
    }
}
