/// @title Delegation
/// @notice Vote delegation for governance
/// @dev Part of @sui-starters/governance package
module sui_starters_governance::delegation {
    use sui::event;
    use sui::table::{Self, Table};

    // === Errors ===

    const EAlreadyDelegated: u64 = 0;
    const ENotDelegated: u64 = 1;
    const ESelfDelegation: u64 = 2;
    const EInsufficientPower: u64 = 3;
    const EDelegationLocked: u64 = 4;

    // === Structs ===

    /// Delegation registry
    public struct DelegationRegistry has key, store {
        id: UID,
        /// Delegator -> delegation info
        delegations: Table<address, DelegationInfo>,
        /// Delegate -> total received power
        received_power: Table<address, u64>,
        /// Total delegated power
        total_delegated: u64,
    }

    /// Individual delegation info
    public struct DelegationInfo has store, copy, drop {
        delegate: address,
        power: u64,
        epoch: u64,
        /// Locked until epoch (0 = no lock)
        lock_until: u64,
    }

    /// Delegation receipt
    public struct DelegationReceipt has key, store {
        id: UID,
        delegator: address,
        delegate: address,
        power: u64,
        created_epoch: u64,
    }

    // === Events ===

    public struct PowerDelegated has copy, drop {
        delegator: address,
        delegate: address,
        power: u64,
        lock_until: u64,
    }

    public struct DelegationRevoked has copy, drop {
        delegator: address,
        delegate: address,
        power: u64,
    }

    public struct DelegationTransferred has copy, drop {
        delegator: address,
        old_delegate: address,
        new_delegate: address,
        power: u64,
    }

    // === Create Functions ===

    /// Create delegation registry
    public fun new(ctx: &mut TxContext): DelegationRegistry {
        DelegationRegistry {
            id: object::new(ctx),
            delegations: table::new(ctx),
            received_power: table::new(ctx),
            total_delegated: 0,
        }
    }

    // === Core Functions ===

    /// Delegate voting power
    public fun delegate(
        registry: &mut DelegationRegistry,
        delegator: address,
        delegate_to: address,
        power: u64,
        lock_epochs: u64,
        ctx: &mut TxContext,
    ): DelegationReceipt {
        assert!(delegator != delegate_to, ESelfDelegation);
        assert!(!table::contains(&registry.delegations, delegator), EAlreadyDelegated);

        let current_epoch = ctx.epoch();
        let lock_until = if (lock_epochs > 0) {
            current_epoch + lock_epochs
        } else {
            0
        };

        // Record delegation
        table::add(&mut registry.delegations, delegator, DelegationInfo {
            delegate: delegate_to,
            power,
            epoch: current_epoch,
            lock_until,
        });

        // Update received power
        if (table::contains(&registry.received_power, delegate_to)) {
            let received = table::borrow_mut(&mut registry.received_power, delegate_to);
            *received = *received + power;
        } else {
            table::add(&mut registry.received_power, delegate_to, power);
        };

        registry.total_delegated = registry.total_delegated + power;

        event::emit(PowerDelegated {
            delegator,
            delegate: delegate_to,
            power,
            lock_until,
        });

        DelegationReceipt {
            id: object::new(ctx),
            delegator,
            delegate: delegate_to,
            power,
            created_epoch: current_epoch,
        }
    }

    /// Revoke delegation
    public fun revoke(
        registry: &mut DelegationRegistry,
        delegator: address,
        ctx: &TxContext,
    ) {
        assert!(table::contains(&registry.delegations, delegator), ENotDelegated);

        let info = table::borrow(&registry.delegations, delegator);
        assert!(info.lock_until == 0 || ctx.epoch() >= info.lock_until, EDelegationLocked);

        let DelegationInfo { delegate, power, epoch: _, lock_until: _ } =
            table::remove(&mut registry.delegations, delegator);

        // Update received power
        let received = table::borrow_mut(&mut registry.received_power, delegate);
        *received = *received - power;

        registry.total_delegated = registry.total_delegated - power;

        event::emit(DelegationRevoked {
            delegator,
            delegate,
            power,
        });
    }

    /// Transfer delegation to new delegate
    public fun transfer_delegation(
        registry: &mut DelegationRegistry,
        delegator: address,
        new_delegate: address,
        ctx: &TxContext,
    ) {
        assert!(delegator != new_delegate, ESelfDelegation);
        assert!(table::contains(&registry.delegations, delegator), ENotDelegated);

        let info = table::borrow(&registry.delegations, delegator);
        assert!(info.lock_until == 0 || ctx.epoch() >= info.lock_until, EDelegationLocked);

        let old_delegate = info.delegate;
        let power = info.power;

        // Update old delegate's received power
        let old_received = table::borrow_mut(&mut registry.received_power, old_delegate);
        *old_received = *old_received - power;

        // Update new delegate's received power
        if (table::contains(&registry.received_power, new_delegate)) {
            let new_received = table::borrow_mut(&mut registry.received_power, new_delegate);
            *new_received = *new_received + power;
        } else {
            table::add(&mut registry.received_power, new_delegate, power);
        };

        // Update delegation info
        let delegation = table::borrow_mut(&mut registry.delegations, delegator);
        delegation.delegate = new_delegate;
        delegation.epoch = ctx.epoch();

        event::emit(DelegationTransferred {
            delegator,
            old_delegate,
            new_delegate,
            power,
        });
    }

    // === View Functions ===

    /// Is delegating
    public fun is_delegating(registry: &DelegationRegistry, delegator: address): bool {
        table::contains(&registry.delegations, delegator)
    }

    /// Get delegation info
    public fun get_delegation(
        registry: &DelegationRegistry,
        delegator: address,
    ): (address, u64, u64) {
        let info = table::borrow(&registry.delegations, delegator);
        (info.delegate, info.power, info.lock_until)
    }

    /// Get received power
    public fun get_received_power(
        registry: &DelegationRegistry,
        delegate: address,
    ): u64 {
        if (table::contains(&registry.received_power, delegate)) {
            *table::borrow(&registry.received_power, delegate)
        } else {
            0
        }
    }

    /// Get total delegated
    public fun total_delegated(registry: &DelegationRegistry): u64 {
        registry.total_delegated
    }

    /// Is delegation locked
    public fun is_locked(
        registry: &DelegationRegistry,
        delegator: address,
        current_epoch: u64,
    ): bool {
        if (!table::contains(&registry.delegations, delegator)) {
            return false
        };
        let info = table::borrow(&registry.delegations, delegator);
        info.lock_until > 0 && current_epoch < info.lock_until
    }

    /// Get receipt info
    public fun receipt_info(receipt: &DelegationReceipt): (address, address, u64) {
        (receipt.delegator, receipt.delegate, receipt.power)
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_registry() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let registry = new(scenario.ctx());
            assert!(total_delegated(&registry) == 0, 0);
            transfer::public_share_object(registry);
        };

        scenario.end();
    }

    #[test]
    fun test_delegate() {
        let admin = @0xAD;
        let delegator = @0xD1;
        let delegate_addr = @0xD2;
        let mut scenario = test_scenario::begin(admin);

        // Create registry
        {
            let registry = new(scenario.ctx());
            transfer::public_share_object(registry);
        };

        // Delegate
        scenario.next_tx(delegator);
        {
            let mut registry = scenario.take_shared<DelegationRegistry>();

            let receipt = delegate(
                &mut registry,
                delegator,
                delegate_addr,
                1000,
                0, // no lock
                scenario.ctx(),
            );

            assert!(is_delegating(&registry, delegator), 0);
            assert!(get_received_power(&registry, delegate_addr) == 1000, 1);
            assert!(total_delegated(&registry) == 1000, 2);

            transfer::public_transfer(receipt, delegator);
            test_scenario::return_shared(registry);
        };

        scenario.end();
    }

    #[test]
    fun test_revoke() {
        let admin = @0xAD;
        let delegator = @0xD1;
        let delegate_addr = @0xD2;
        let mut scenario = test_scenario::begin(admin);

        // Create and delegate
        {
            let mut registry = new(scenario.ctx());

            let receipt = delegate(
                &mut registry,
                delegator,
                delegate_addr,
                1000,
                0,
                scenario.ctx(),
            );

            revoke(&mut registry, delegator, scenario.ctx());

            assert!(!is_delegating(&registry, delegator), 0);
            assert!(get_received_power(&registry, delegate_addr) == 0, 1);
            assert!(total_delegated(&registry) == 0, 2);

            transfer::public_transfer(receipt, delegator);
            transfer::public_share_object(registry);
        };

        scenario.end();
    }

    #[test]
    fun test_transfer_delegation() {
        let admin = @0xAD;
        let delegator = @0xD1;
        let delegate1 = @0xD2;
        let delegate2 = @0xD3;
        let mut scenario = test_scenario::begin(admin);

        // Create, delegate, and transfer
        {
            let mut registry = new(scenario.ctx());

            let receipt = delegate(
                &mut registry,
                delegator,
                delegate1,
                1000,
                0,
                scenario.ctx(),
            );

            transfer_delegation(&mut registry, delegator, delegate2, scenario.ctx());

            let (current_delegate, power, _) = get_delegation(&registry, delegator);
            assert!(current_delegate == delegate2, 0);
            assert!(power == 1000, 1);
            assert!(get_received_power(&registry, delegate1) == 0, 2);
            assert!(get_received_power(&registry, delegate2) == 1000, 3);

            transfer::public_transfer(receipt, delegator);
            transfer::public_share_object(registry);
        };

        scenario.end();
    }
}
