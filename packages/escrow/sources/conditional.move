/// @title Conditional Escrow
/// @notice Escrow with conditions that must be met
/// @dev Part of @sui-starters/escrow package
module sui_starters_escrow::conditional {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;

    // === Errors ===

    /// Condition not met
    const EConditionNotMet: u64 = 0;

    /// Already released
    const EAlreadyReleased: u64 = 1;

    /// Not authorized
    const ENotAuthorized: u64 = 2;

    /// Escrow expired
    const EExpired: u64 = 3;

    /// Not expired yet
    const ENotExpired: u64 = 4;

    // === Structs ===

    /// Conditional escrow with oracle/arbiter
    public struct ConditionalEscrow<phantom T> has key, store {
        id: UID,
        /// Depositor
        depositor: address,
        /// Recipient
        recipient: address,
        /// Arbiter who can approve
        arbiter: address,
        /// Escrowed funds
        balance: Balance<T>,
        /// Is condition met
        condition_met: bool,
        /// Is released
        released: bool,
        /// Expiration timestamp (0 = no expiry)
        expiration: u64,
        /// Description
        description: vector<u8>,
    }

    /// Multi-condition escrow
    public struct MultiConditionEscrow<phantom T> has key, store {
        id: UID,
        /// Depositor
        depositor: address,
        /// Recipient
        recipient: address,
        /// Required approvers
        approvers: vector<address>,
        /// Approvals received
        approvals: vector<address>,
        /// Required approval count
        threshold: u64,
        /// Escrowed funds
        balance: Balance<T>,
        /// Is released
        released: bool,
        /// Expiration
        expiration: u64,
    }

    /// Milestone-based escrow
    public struct MilestoneEscrow<phantom T> has key, store {
        id: UID,
        /// Depositor
        depositor: address,
        /// Recipient
        recipient: address,
        /// Arbiter
        arbiter: address,
        /// Total amount
        total_amount: u64,
        /// Amount released so far
        released_amount: u64,
        /// Milestones
        milestones: vector<Milestone>,
        /// Current milestone index
        current_milestone: u64,
        /// Escrowed funds
        balance: Balance<T>,
    }

    /// Milestone definition
    public struct Milestone has store, copy, drop {
        /// Amount to release
        amount: u64,
        /// Description
        description: vector<u8>,
        /// Is completed
        completed: bool,
    }

    // === Events ===

    public struct EscrowCreated has copy, drop {
        escrow_id: ID,
        depositor: address,
        recipient: address,
        amount: u64,
    }

    public struct ConditionApproved has copy, drop {
        escrow_id: ID,
        approver: address,
    }

    public struct EscrowReleased has copy, drop {
        escrow_id: ID,
        recipient: address,
        amount: u64,
    }

    public struct MilestoneCompleted has copy, drop {
        escrow_id: ID,
        milestone_index: u64,
        amount: u64,
    }

    // === Conditional Escrow Functions ===

    /// Create conditional escrow
    public fun create_conditional<T>(
        coin: Coin<T>,
        recipient: address,
        arbiter: address,
        expiration: u64,
        description: vector<u8>,
        ctx: &mut TxContext,
    ): ConditionalEscrow<T> {
        let amount = coin::value(&coin);
        let depositor = ctx.sender();

        let escrow = ConditionalEscrow<T> {
            id: object::new(ctx),
            depositor,
            recipient,
            arbiter,
            balance: coin::into_balance(coin),
            condition_met: false,
            released: false,
            expiration,
            description,
        };

        event::emit(EscrowCreated {
            escrow_id: object::id(&escrow),
            depositor,
            recipient,
            amount,
        });

        escrow
    }

    /// Arbiter approves condition
    public fun approve_condition<T>(
        escrow: &mut ConditionalEscrow<T>,
        ctx: &TxContext,
    ) {
        assert!(ctx.sender() == escrow.arbiter, ENotAuthorized);
        assert!(!escrow.released, EAlreadyReleased);

        escrow.condition_met = true;

        event::emit(ConditionApproved {
            escrow_id: object::id(escrow),
            approver: ctx.sender(),
        });
    }

    /// Release funds to recipient
    public fun release_conditional<T>(
        escrow: ConditionalEscrow<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(escrow.condition_met, EConditionNotMet);
        assert!(!escrow.released, EAlreadyReleased);

        let ConditionalEscrow {
            id,
            depositor: _,
            recipient,
            arbiter: _,
            balance,
            condition_met: _,
            released: _,
            expiration: _,
            description: _,
        } = escrow;

        let amount = balance::value(&balance);
        let escrow_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(EscrowReleased {
            escrow_id,
            recipient,
            amount,
        });

        coin::from_balance(balance, ctx)
    }

    /// Refund after expiration
    public fun refund_conditional<T>(
        escrow: ConditionalEscrow<T>,
        current_time: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(escrow.expiration > 0 && current_time >= escrow.expiration, ENotExpired);
        assert!(!escrow.released, EAlreadyReleased);

        let ConditionalEscrow {
            id,
            depositor,
            recipient: _,
            arbiter: _,
            balance,
            condition_met: _,
            released: _,
            expiration: _,
            description: _,
        } = escrow;

        let amount = balance::value(&balance);
        let escrow_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(EscrowReleased {
            escrow_id,
            recipient: depositor,
            amount,
        });

        coin::from_balance(balance, ctx)
    }

    // === Multi-Condition Escrow Functions ===

    /// Create multi-condition escrow
    public fun create_multi_condition<T>(
        coin: Coin<T>,
        recipient: address,
        approvers: vector<address>,
        threshold: u64,
        expiration: u64,
        ctx: &mut TxContext,
    ): MultiConditionEscrow<T> {
        let amount = coin::value(&coin);
        let depositor = ctx.sender();

        let escrow = MultiConditionEscrow<T> {
            id: object::new(ctx),
            depositor,
            recipient,
            approvers,
            approvals: vector::empty(),
            threshold,
            balance: coin::into_balance(coin),
            released: false,
            expiration,
        };

        event::emit(EscrowCreated {
            escrow_id: object::id(&escrow),
            depositor,
            recipient,
            amount,
        });

        escrow
    }

    /// Add approval
    public fun add_approval<T>(
        escrow: &mut MultiConditionEscrow<T>,
        ctx: &TxContext,
    ) {
        let sender = ctx.sender();
        assert!(vector::contains(&escrow.approvers, &sender), ENotAuthorized);
        assert!(!vector::contains(&escrow.approvals, &sender), EAlreadyReleased);
        assert!(!escrow.released, EAlreadyReleased);

        vector::push_back(&mut escrow.approvals, sender);

        event::emit(ConditionApproved {
            escrow_id: object::id(escrow),
            approver: sender,
        });
    }

    /// Check if threshold met
    public fun threshold_met<T>(escrow: &MultiConditionEscrow<T>): bool {
        vector::length(&escrow.approvals) >= escrow.threshold
    }

    /// Release multi-condition escrow
    public fun release_multi_condition<T>(
        escrow: MultiConditionEscrow<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(vector::length(&escrow.approvals) >= escrow.threshold, EConditionNotMet);
        assert!(!escrow.released, EAlreadyReleased);

        let MultiConditionEscrow {
            id,
            depositor: _,
            recipient,
            approvers: _,
            approvals: _,
            threshold: _,
            balance,
            released: _,
            expiration: _,
        } = escrow;

        let amount = balance::value(&balance);
        let escrow_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(EscrowReleased {
            escrow_id,
            recipient,
            amount,
        });

        coin::from_balance(balance, ctx)
    }

    // === Milestone Escrow Functions ===

    /// Create milestone escrow
    public fun create_milestone<T>(
        coin: Coin<T>,
        recipient: address,
        arbiter: address,
        milestone_amounts: vector<u64>,
        milestone_descriptions: vector<vector<u8>>,
        ctx: &mut TxContext,
    ): MilestoneEscrow<T> {
        let total_amount = coin::value(&coin);
        let depositor = ctx.sender();

        let mut milestones = vector::empty<Milestone>();
        let len = vector::length(&milestone_amounts);
        let mut i = 0;
        while (i < len) {
            vector::push_back(&mut milestones, Milestone {
                amount: *vector::borrow(&milestone_amounts, i),
                description: *vector::borrow(&milestone_descriptions, i),
                completed: false,
            });
            i = i + 1;
        };

        let escrow = MilestoneEscrow<T> {
            id: object::new(ctx),
            depositor,
            recipient,
            arbiter,
            total_amount,
            released_amount: 0,
            milestones,
            current_milestone: 0,
            balance: coin::into_balance(coin),
        };

        event::emit(EscrowCreated {
            escrow_id: object::id(&escrow),
            depositor,
            recipient,
            amount: total_amount,
        });

        escrow
    }

    /// Complete a milestone
    public fun complete_milestone<T>(
        escrow: &mut MilestoneEscrow<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(ctx.sender() == escrow.arbiter, ENotAuthorized);

        let milestone_idx = escrow.current_milestone;
        assert!(milestone_idx < vector::length(&escrow.milestones), EConditionNotMet);

        let milestone = vector::borrow_mut(&mut escrow.milestones, milestone_idx);
        assert!(!milestone.completed, EAlreadyReleased);

        milestone.completed = true;
        let amount = milestone.amount;

        escrow.released_amount = escrow.released_amount + amount;
        escrow.current_milestone = escrow.current_milestone + 1;

        event::emit(MilestoneCompleted {
            escrow_id: object::id(escrow),
            milestone_index: milestone_idx,
            amount,
        });

        coin::from_balance(balance::split(&mut escrow.balance, amount), ctx)
    }

    // === View Functions ===

    /// Check if condition is met
    public fun is_condition_met<T>(escrow: &ConditionalEscrow<T>): bool {
        escrow.condition_met
    }

    /// Get escrow balance
    public fun escrow_balance<T>(escrow: &ConditionalEscrow<T>): u64 {
        balance::value(&escrow.balance)
    }

    /// Get multi-condition approval count
    public fun approval_count<T>(escrow: &MultiConditionEscrow<T>): u64 {
        vector::length(&escrow.approvals)
    }

    /// Get milestone progress
    public fun milestone_progress<T>(escrow: &MilestoneEscrow<T>): (u64, u64, u64) {
        (
            escrow.current_milestone,
            vector::length(&escrow.milestones),
            escrow.released_amount,
        )
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::sui::SUI;

    #[test]
    fun test_conditional_escrow() {
        let depositor = @0xAA;
        let recipient = @0xBB;
        let arbiter = @0xCC;
        let mut scenario = test_scenario::begin(depositor);

        {
            let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let escrow = create_conditional(
                coin,
                recipient,
                arbiter,
                0,
                b"Test escrow",
                scenario.ctx(),
            );

            assert!(!is_condition_met(&escrow), 0);
            assert!(escrow_balance(&escrow) == 1000, 1);

            transfer::public_share_object(escrow);
        };

        scenario.end();
    }

    #[test]
    fun test_multi_condition_escrow() {
        let depositor = @0xAA;
        let recipient = @0xBB;
        let approver1 = @0xC1;
        let approver2 = @0xC2;
        let mut scenario = test_scenario::begin(depositor);

        {
            let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let approvers = vector[approver1, approver2];
            let escrow = create_multi_condition(
                coin,
                recipient,
                approvers,
                2,
                0,
                scenario.ctx(),
            );

            assert!(approval_count(&escrow) == 0, 0);
            assert!(!threshold_met(&escrow), 1);

            transfer::public_share_object(escrow);
        };

        scenario.end();
    }

    #[test]
    fun test_milestone_escrow() {
        let depositor = @0xAA;
        let recipient = @0xBB;
        let arbiter = @0xCC;
        let mut scenario = test_scenario::begin(depositor);

        {
            let coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let amounts = vector[300, 300, 400];
            let descriptions = vector[b"Phase 1", b"Phase 2", b"Phase 3"];
            let escrow = create_milestone(
                coin,
                recipient,
                arbiter,
                amounts,
                descriptions,
                scenario.ctx(),
            );

            let (current, total, released) = milestone_progress(&escrow);
            assert!(current == 0, 0);
            assert!(total == 3, 1);
            assert!(released == 0, 2);

            transfer::public_share_object(escrow);
        };

        scenario.end();
    }
}
