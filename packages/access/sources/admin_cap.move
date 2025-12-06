/// @title Admin Capability Pattern
/// @notice Simple admin capability for access control
/// @dev Part of @sui-starters/access package
module sui_starters_access::admin_cap {
    use sui::event;

    // === Errors ===

    /// Not authorized (caller doesn't have admin cap)
    const ENotAuthorized: u64 = 0;

    // === Structs ===

    /// Generic admin capability - phantom type T ties it to a specific module/contract
    /// Usage: AdminCap<MY_MODULE> for module-specific admin rights
    public struct AdminCap<phantom T> has key, store {
        id: UID,
    }

    /// Super admin capability - can create other admin caps
    public struct SuperAdminCap<phantom T> has key, store {
        id: UID,
    }

    // === Events ===

    /// Emitted when admin cap is created
    public struct AdminCapCreated has copy, drop {
        admin_cap_id: ID,
        recipient: address,
    }

    /// Emitted when admin cap is destroyed
    public struct AdminCapDestroyed has copy, drop {
        admin_cap_id: ID,
        destroyer: address,
    }

    /// Emitted when super admin creates a new admin cap
    public struct AdminCapGranted has copy, drop {
        super_admin_id: ID,
        new_admin_cap_id: ID,
        recipient: address,
    }

    // === Public Functions ===

    /// Create a new admin capability
    /// Typically called in module init function
    public fun new<T>(ctx: &mut TxContext): AdminCap<T> {
        let admin_cap = AdminCap<T> {
            id: object::new(ctx),
        };

        event::emit(AdminCapCreated {
            admin_cap_id: object::id(&admin_cap),
            recipient: ctx.sender(),
        });

        admin_cap
    }

    /// Create a new super admin capability
    /// Super admin can create additional admin caps
    public fun new_super<T>(ctx: &mut TxContext): SuperAdminCap<T> {
        SuperAdminCap<T> {
            id: object::new(ctx),
        }
    }

    /// Create both admin and super admin caps (convenience function for init)
    public fun new_with_super<T>(ctx: &mut TxContext): (AdminCap<T>, SuperAdminCap<T>) {
        (new<T>(ctx), new_super<T>(ctx))
    }

    /// Super admin creates a new admin cap for someone
    public fun grant_admin<T>(
        _super_cap: &SuperAdminCap<T>,
        recipient: address,
        ctx: &mut TxContext
    ): AdminCap<T> {
        let admin_cap = AdminCap<T> {
            id: object::new(ctx),
        };

        event::emit(AdminCapGranted {
            super_admin_id: object::id(_super_cap),
            new_admin_cap_id: object::id(&admin_cap),
            recipient,
        });

        admin_cap
    }

    /// Destroy an admin capability
    public fun destroy<T>(cap: AdminCap<T>, ctx: &TxContext) {
        let AdminCap { id } = cap;

        event::emit(AdminCapDestroyed {
            admin_cap_id: id.to_inner(),
            destroyer: ctx.sender(),
        });

        object::delete(id);
    }

    /// Destroy a super admin capability
    public fun destroy_super<T>(cap: SuperAdminCap<T>) {
        let SuperAdminCap { id } = cap;
        object::delete(id);
    }

    // === Assertion Functions ===

    /// Assert caller has admin capability (does nothing, just for type checking)
    /// Use: admin_cap::require_admin(&admin_cap);
    public fun require_admin<T>(_cap: &AdminCap<T>) {
        // Type system ensures caller has the cap
    }

    /// Assert caller has super admin capability
    public fun require_super_admin<T>(_cap: &SuperAdminCap<T>) {
        // Type system ensures caller has the cap
    }

    // === View Functions ===

    /// Get the ID of an admin cap
    public fun id<T>(cap: &AdminCap<T>): ID {
        object::id(cap)
    }

    /// Get the ID of a super admin cap
    public fun super_id<T>(cap: &SuperAdminCap<T>): ID {
        object::id(cap)
    }

    // === Tests ===

    #[test]
    fun test_create_admin_cap() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        // Create admin cap
        {
            let cap = new<AdminCapTest>(scenario.ctx());
            assert!(object::id(&cap) != object::id_from_address(@0x0), 0);
            transfer::public_transfer(cap, admin);
        };

        // Use admin cap
        scenario.next_tx(admin);
        {
            let cap = scenario.take_from_sender<AdminCap<AdminCapTest>>();
            require_admin(&cap);
            scenario.return_to_sender(cap);
        };

        scenario.end();
    }

    #[test]
    fun test_super_admin_grant() {
        use sui::test_scenario;

        let super_admin = @0x5A;
        let new_admin = @0xAA;
        let mut scenario = test_scenario::begin(super_admin);

        // Create super admin cap
        {
            let super_cap = new_super<AdminCapTest>(scenario.ctx());
            transfer::public_transfer(super_cap, super_admin);
        };

        // Super admin grants admin to new_admin
        scenario.next_tx(super_admin);
        {
            let super_cap = scenario.take_from_sender<SuperAdminCap<AdminCapTest>>();
            let admin_cap = grant_admin(&super_cap, new_admin, scenario.ctx());
            transfer::public_transfer(admin_cap, new_admin);
            scenario.return_to_sender(super_cap);
        };

        // New admin can use their cap
        scenario.next_tx(new_admin);
        {
            let cap = scenario.take_from_sender<AdminCap<AdminCapTest>>();
            require_admin(&cap);
            scenario.return_to_sender(cap);
        };

        scenario.end();
    }

    #[test]
    fun test_destroy_admin_cap() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        // Create and destroy admin cap
        {
            let cap = new<AdminCapTest>(scenario.ctx());
            destroy(cap, scenario.ctx());
        };

        scenario.end();
    }

    // Test witness type
    public struct AdminCapTest has drop {}
}
