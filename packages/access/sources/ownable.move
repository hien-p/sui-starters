/// @title Ownable Pattern
/// @notice Single owner pattern with transfer capability
/// @dev Part of @sui-starters/access package
module sui_starters_access::ownable {
    use sui::event;

    // === Errors ===

    /// Caller is not the owner
    const ENotOwner: u64 = 0;

    /// New owner cannot be zero address
    const EZeroAddress: u64 = 1;

    /// Ownership transfer not pending
    const ENoPendingTransfer: u64 = 2;

    /// Caller is not the pending owner
    const ENotPendingOwner: u64 = 3;

    // === Structs ===

    /// Ownership state that can be embedded in other objects
    public struct Ownership has store, drop {
        owner: address,
        pending_owner: Option<address>,
    }

    /// Standalone ownable object
    public struct Ownable<phantom T> has key, store {
        id: UID,
        ownership: Ownership,
    }

    // === Events ===

    /// Emitted when ownership is transferred
    public struct OwnershipTransferred has copy, drop {
        previous_owner: address,
        new_owner: address,
    }

    /// Emitted when ownership transfer is initiated (2-step)
    public struct OwnershipTransferStarted has copy, drop {
        current_owner: address,
        pending_owner: address,
    }

    /// Emitted when ownership transfer is cancelled
    public struct OwnershipTransferCancelled has copy, drop {
        current_owner: address,
        cancelled_pending_owner: address,
    }

    // === Ownership (Embeddable) Functions ===

    /// Create new ownership state
    public fun new_ownership(owner: address): Ownership {
        Ownership {
            owner,
            pending_owner: option::none(),
        }
    }

    /// Get the current owner
    public fun owner(ownership: &Ownership): address {
        ownership.owner
    }

    /// Check if address is the owner
    public fun is_owner(ownership: &Ownership, account: address): bool {
        ownership.owner == account
    }

    /// Assert caller is owner
    public fun require_owner(ownership: &Ownership, ctx: &TxContext) {
        assert!(ownership.owner == ctx.sender(), ENotOwner);
    }

    /// Transfer ownership directly (1-step)
    public fun transfer_ownership(
        ownership: &mut Ownership,
        new_owner: address,
        ctx: &TxContext
    ) {
        require_owner(ownership, ctx);
        assert!(new_owner != @0x0, EZeroAddress);

        let previous_owner = ownership.owner;
        ownership.owner = new_owner;
        ownership.pending_owner = option::none();

        event::emit(OwnershipTransferred {
            previous_owner,
            new_owner,
        });
    }

    /// Start 2-step ownership transfer
    public fun transfer_ownership_2step(
        ownership: &mut Ownership,
        new_owner: address,
        ctx: &TxContext
    ) {
        require_owner(ownership, ctx);
        assert!(new_owner != @0x0, EZeroAddress);

        ownership.pending_owner = option::some(new_owner);

        event::emit(OwnershipTransferStarted {
            current_owner: ownership.owner,
            pending_owner: new_owner,
        });
    }

    /// Accept ownership (called by pending owner)
    public fun accept_ownership(
        ownership: &mut Ownership,
        ctx: &TxContext
    ) {
        assert!(option::is_some(&ownership.pending_owner), ENoPendingTransfer);
        let pending = *option::borrow(&ownership.pending_owner);
        assert!(ctx.sender() == pending, ENotPendingOwner);

        let previous_owner = ownership.owner;
        ownership.owner = pending;
        ownership.pending_owner = option::none();

        event::emit(OwnershipTransferred {
            previous_owner,
            new_owner: pending,
        });
    }

    /// Cancel pending ownership transfer
    public fun cancel_transfer(
        ownership: &mut Ownership,
        ctx: &TxContext
    ) {
        require_owner(ownership, ctx);
        assert!(option::is_some(&ownership.pending_owner), ENoPendingTransfer);

        let cancelled = option::extract(&mut ownership.pending_owner);

        event::emit(OwnershipTransferCancelled {
            current_owner: ownership.owner,
            cancelled_pending_owner: cancelled,
        });
    }

    /// Renounce ownership (no more owner)
    public fun renounce_ownership(
        ownership: &mut Ownership,
        ctx: &TxContext
    ) {
        require_owner(ownership, ctx);

        let previous_owner = ownership.owner;
        ownership.owner = @0x0;
        ownership.pending_owner = option::none();

        event::emit(OwnershipTransferred {
            previous_owner,
            new_owner: @0x0,
        });
    }

    /// Get pending owner
    public fun pending_owner(ownership: &Ownership): Option<address> {
        ownership.pending_owner
    }

    // === Ownable Object Functions ===

    /// Create a new ownable object
    public fun new<T>(owner: address, ctx: &mut TxContext): Ownable<T> {
        Ownable<T> {
            id: object::new(ctx),
            ownership: new_ownership(owner),
        }
    }

    /// Get owner of ownable object
    public fun ownable_owner<T>(ownable: &Ownable<T>): address {
        owner(&ownable.ownership)
    }

    /// Check if address is owner of ownable object
    public fun ownable_is_owner<T>(ownable: &Ownable<T>, account: address): bool {
        is_owner(&ownable.ownership, account)
    }

    /// Assert caller is owner of ownable object
    public fun ownable_require_owner<T>(ownable: &Ownable<T>, ctx: &TxContext) {
        require_owner(&ownable.ownership, ctx);
    }

    /// Transfer ownership of ownable object
    public fun ownable_transfer<T>(
        ownable: &mut Ownable<T>,
        new_owner: address,
        ctx: &TxContext
    ) {
        transfer_ownership(&mut ownable.ownership, new_owner, ctx);
    }

    /// Start 2-step transfer for ownable object
    public fun ownable_transfer_2step<T>(
        ownable: &mut Ownable<T>,
        new_owner: address,
        ctx: &TxContext
    ) {
        transfer_ownership_2step(&mut ownable.ownership, new_owner, ctx);
    }

    /// Accept ownership of ownable object
    public fun ownable_accept<T>(
        ownable: &mut Ownable<T>,
        ctx: &TxContext
    ) {
        accept_ownership(&mut ownable.ownership, ctx);
    }

    /// Destroy ownable object (only owner)
    public fun destroy<T>(ownable: Ownable<T>, ctx: &TxContext) {
        ownable_require_owner(&ownable, ctx);
        let Ownable { id, ownership: _ } = ownable;
        object::delete(id);
    }

    // === Tests ===

    #[test]
    fun test_ownership_basic() {
        let owner = @0x1;
        let ownership = new_ownership(owner);
        assert!(owner(&ownership) == owner, 0);
        assert!(is_owner(&ownership, owner), 1);
        assert!(!is_owner(&ownership, @0x2), 2);
    }

    #[test]
    fun test_transfer_ownership() {
        use sui::test_scenario;

        let owner = @0x1;
        let new_owner = @0x2;
        let mut scenario = test_scenario::begin(owner);

        {
            let mut ownership = new_ownership(owner);
            transfer_ownership(&mut ownership, new_owner, scenario.ctx());
            assert!(owner(&ownership) == new_owner, 0);
        };

        scenario.end();
    }

    #[test]
    fun test_2step_transfer() {
        use sui::test_scenario;

        let owner = @0x1;
        let new_owner = @0x2;
        let mut scenario = test_scenario::begin(owner);

        let mut ownership = new_ownership(owner);

        // Step 1: Owner initiates transfer
        {
            transfer_ownership_2step(&mut ownership, new_owner, scenario.ctx());
            assert!(pending_owner(&ownership) == option::some(new_owner), 0);
            assert!(owner(&ownership) == owner, 1); // Still old owner
        };

        // Step 2: New owner accepts
        scenario.next_tx(new_owner);
        {
            accept_ownership(&mut ownership, scenario.ctx());
            assert!(owner(&ownership) == new_owner, 2);
            assert!(pending_owner(&ownership) == option::none(), 3);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ENotOwner)]
    fun test_transfer_not_owner() {
        use sui::test_scenario;

        let owner = @0x1;
        let attacker = @0x2;
        let mut scenario = test_scenario::begin(attacker);

        {
            let mut ownership = new_ownership(owner);
            // Attacker tries to transfer - should fail
            transfer_ownership(&mut ownership, attacker, scenario.ctx());
        };

        scenario.end();
    }

    #[test]
    fun test_renounce_ownership() {
        use sui::test_scenario;

        let owner = @0x1;
        let mut scenario = test_scenario::begin(owner);

        {
            let mut ownership = new_ownership(owner);
            renounce_ownership(&mut ownership, scenario.ctx());
            assert!(owner(&ownership) == @0x0, 0);
        };

        scenario.end();
    }
}
