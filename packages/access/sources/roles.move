/// @title Role-Based Access Control
/// @notice Bitfield-based role system for flexible access control
/// @dev Part of @sui-starters/access package
module sui_starters_access::roles {
    use sui::event;
    use sui::table::{Self, Table};

    // === Role Constants (Bitfield) ===

    /// Admin role - full access
    const ROLE_ADMIN: u8 = 1;      // 0b00000001

    /// Minter role - can mint tokens/NFTs
    const ROLE_MINTER: u8 = 2;     // 0b00000010

    /// Pauser role - can pause/unpause
    const ROLE_PAUSER: u8 = 4;     // 0b00000100

    /// Operator role - can perform operations
    const ROLE_OPERATOR: u8 = 8;   // 0b00001000

    /// Burner role - can burn tokens
    const ROLE_BURNER: u8 = 16;    // 0b00010000

    /// Upgrader role - can upgrade contracts
    const ROLE_UPGRADER: u8 = 32;  // 0b00100000

    /// Manager role - can manage settings
    const ROLE_MANAGER: u8 = 64;   // 0b01000000

    /// Treasurer role - can manage treasury
    const ROLE_TREASURER: u8 = 128; // 0b10000000

    // === Errors ===

    /// Account doesn't have required role
    const EMissingRole: u64 = 0;

    /// Cannot grant role to zero address
    const EZeroAddress: u64 = 1;

    /// Cannot revoke role from admin if it's the last admin
    const ELastAdmin: u64 = 2;

    /// Invalid role value
    const EInvalidRole: u64 = 3;

    // === Structs ===

    /// Role store - tracks roles for all accounts
    public struct RoleStore has key, store {
        id: UID,
        /// Admin who can manage roles
        admin: address,
        /// Address -> role bitfield
        roles: Table<address, u8>,
        /// Count of admins (to prevent removing last admin)
        admin_count: u64,
    }

    /// Role configuration for a single account (embeddable)
    public struct Roles has store {
        flags: u8,
    }

    // === Events ===

    /// Emitted when role is granted
    public struct RoleGranted has copy, drop {
        account: address,
        role: u8,
        granter: address,
    }

    /// Emitted when role is revoked
    public struct RoleRevoked has copy, drop {
        account: address,
        role: u8,
        revoker: address,
    }

    /// Emitted when admin is changed
    public struct AdminChanged has copy, drop {
        previous_admin: address,
        new_admin: address,
    }

    // === Constructor ===

    /// Create a new role store with the creator as admin
    public fun new(ctx: &mut TxContext): RoleStore {
        let admin = ctx.sender();
        let mut store = RoleStore {
            id: object::new(ctx),
            admin,
            roles: table::new(ctx),
            admin_count: 1,
        };

        // Grant admin role to creator
        table::add(&mut store.roles, admin, ROLE_ADMIN);

        store
    }

    /// Create a new role store with specified admin
    public fun new_with_admin(admin: address, ctx: &mut TxContext): RoleStore {
        assert!(admin != @0x0, EZeroAddress);

        let mut store = RoleStore {
            id: object::new(ctx),
            admin,
            roles: table::new(ctx),
            admin_count: 1,
        };

        table::add(&mut store.roles, admin, ROLE_ADMIN);

        store
    }

    // === Role Management ===

    /// Grant a role to an account
    public fun grant_role(
        store: &mut RoleStore,
        account: address,
        role: u8,
        ctx: &TxContext
    ) {
        require_admin_role(store, ctx);
        assert!(account != @0x0, EZeroAddress);

        let current_roles = get_roles(store, account);
        let new_roles = current_roles | role;

        // Track admin count
        if (role == ROLE_ADMIN && !has_role_internal(current_roles, ROLE_ADMIN)) {
            store.admin_count = store.admin_count + 1;
        };

        if (table::contains(&store.roles, account)) {
            *table::borrow_mut(&mut store.roles, account) = new_roles;
        } else {
            table::add(&mut store.roles, account, new_roles);
        };

        event::emit(RoleGranted {
            account,
            role,
            granter: ctx.sender(),
        });
    }

    /// Revoke a role from an account
    public fun revoke_role(
        store: &mut RoleStore,
        account: address,
        role: u8,
        ctx: &TxContext
    ) {
        require_admin_role(store, ctx);

        let current_roles = get_roles(store, account);

        // Prevent removing last admin
        if (role == ROLE_ADMIN && has_role_internal(current_roles, ROLE_ADMIN)) {
            assert!(store.admin_count > 1, ELastAdmin);
            store.admin_count = store.admin_count - 1;
        };

        let new_roles = current_roles & (0xFF ^ role);

        if (table::contains(&store.roles, account)) {
            *table::borrow_mut(&mut store.roles, account) = new_roles;
        };

        event::emit(RoleRevoked {
            account,
            role,
            revoker: ctx.sender(),
        });
    }

    /// Renounce a role (self-revoke)
    public fun renounce_role(
        store: &mut RoleStore,
        role: u8,
        ctx: &TxContext
    ) {
        let account = ctx.sender();
        let current_roles = get_roles(store, account);

        // Prevent removing last admin
        if (role == ROLE_ADMIN && has_role_internal(current_roles, ROLE_ADMIN)) {
            assert!(store.admin_count > 1, ELastAdmin);
            store.admin_count = store.admin_count - 1;
        };

        let new_roles = current_roles & (0xFF ^ role);

        if (table::contains(&store.roles, account)) {
            *table::borrow_mut(&mut store.roles, account) = new_roles;
        };

        event::emit(RoleRevoked {
            account,
            role,
            revoker: account,
        });
    }

    /// Grant multiple roles at once
    public fun grant_roles(
        store: &mut RoleStore,
        account: address,
        roles: u8,
        ctx: &TxContext
    ) {
        require_admin_role(store, ctx);
        assert!(account != @0x0, EZeroAddress);

        let current_roles = get_roles(store, account);
        let new_roles = current_roles | roles;

        // Track admin count
        if ((roles & ROLE_ADMIN) != 0 && !has_role_internal(current_roles, ROLE_ADMIN)) {
            store.admin_count = store.admin_count + 1;
        };

        if (table::contains(&store.roles, account)) {
            *table::borrow_mut(&mut store.roles, account) = new_roles;
        } else {
            table::add(&mut store.roles, account, new_roles);
        };
    }

    /// Set admin (transfer admin rights)
    public fun set_admin(
        store: &mut RoleStore,
        new_admin: address,
        ctx: &TxContext
    ) {
        assert!(ctx.sender() == store.admin, EMissingRole);
        assert!(new_admin != @0x0, EZeroAddress);

        let previous_admin = store.admin;
        store.admin = new_admin;

        // Ensure new admin has admin role
        let new_admin_roles = get_roles(store, new_admin);
        if (!has_role_internal(new_admin_roles, ROLE_ADMIN)) {
            if (table::contains(&store.roles, new_admin)) {
                *table::borrow_mut(&mut store.roles, new_admin) = new_admin_roles | ROLE_ADMIN;
            } else {
                table::add(&mut store.roles, new_admin, ROLE_ADMIN);
            };
            store.admin_count = store.admin_count + 1;
        };

        event::emit(AdminChanged {
            previous_admin,
            new_admin,
        });
    }

    // === Role Checking ===

    /// Get roles for an account
    public fun get_roles(store: &RoleStore, account: address): u8 {
        if (table::contains(&store.roles, account)) {
            *table::borrow(&store.roles, account)
        } else {
            0
        }
    }

    /// Check if account has a specific role
    public fun has_role(store: &RoleStore, account: address, role: u8): bool {
        let roles = get_roles(store, account);
        has_role_internal(roles, role)
    }

    /// Internal role check
    fun has_role_internal(roles: u8, role: u8): bool {
        (roles & role) == role
    }

    /// Check if account has admin role
    public fun is_admin(store: &RoleStore, account: address): bool {
        has_role(store, account, ROLE_ADMIN)
    }

    /// Get the primary admin
    public fun admin(store: &RoleStore): address {
        store.admin
    }

    /// Get admin count
    public fun admin_count(store: &RoleStore): u64 {
        store.admin_count
    }

    // === Require Functions (Assertions) ===

    /// Require account has admin role
    public fun require_admin_role(store: &RoleStore, ctx: &TxContext) {
        assert!(has_role(store, ctx.sender(), ROLE_ADMIN), EMissingRole);
    }

    /// Require account has minter role
    public fun require_minter_role(store: &RoleStore, ctx: &TxContext) {
        assert!(has_role(store, ctx.sender(), ROLE_MINTER), EMissingRole);
    }

    /// Require account has pauser role
    public fun require_pauser_role(store: &RoleStore, ctx: &TxContext) {
        assert!(has_role(store, ctx.sender(), ROLE_PAUSER), EMissingRole);
    }

    /// Require account has operator role
    public fun require_operator_role(store: &RoleStore, ctx: &TxContext) {
        assert!(has_role(store, ctx.sender(), ROLE_OPERATOR), EMissingRole);
    }

    /// Require account has any of the specified roles
    public fun require_any_role(store: &RoleStore, roles: u8, ctx: &TxContext) {
        let account_roles = get_roles(store, ctx.sender());
        assert!((account_roles & roles) != 0, EMissingRole);
    }

    /// Require account has all specified roles
    public fun require_all_roles(store: &RoleStore, roles: u8, ctx: &TxContext) {
        let account_roles = get_roles(store, ctx.sender());
        assert!((account_roles & roles) == roles, EMissingRole);
    }

    // === Role Constants Getters ===

    public fun role_admin(): u8 { ROLE_ADMIN }
    public fun role_minter(): u8 { ROLE_MINTER }
    public fun role_pauser(): u8 { ROLE_PAUSER }
    public fun role_operator(): u8 { ROLE_OPERATOR }
    public fun role_burner(): u8 { ROLE_BURNER }
    public fun role_upgrader(): u8 { ROLE_UPGRADER }
    public fun role_manager(): u8 { ROLE_MANAGER }
    public fun role_treasurer(): u8 { ROLE_TREASURER }

    // === Embeddable Roles Functions ===

    /// Create new roles with no flags
    public fun new_roles(): Roles {
        Roles { flags: 0 }
    }

    /// Create new roles with initial flags
    public fun new_roles_with(flags: u8): Roles {
        Roles { flags }
    }

    /// Get role flags
    public fun flags(roles: &Roles): u8 {
        roles.flags
    }

    /// Check if roles has a specific role
    public fun roles_has(roles: &Roles, role: u8): bool {
        (roles.flags & role) == role
    }

    /// Add role to roles
    public fun roles_add(roles: &mut Roles, role: u8) {
        roles.flags = roles.flags | role;
    }

    /// Remove role from roles
    public fun roles_remove(roles: &mut Roles, role: u8) {
        roles.flags = roles.flags & (0xFF ^ role);
    }

    // === Tests ===

    #[test]
    fun test_create_role_store() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let store = new(scenario.ctx());
            assert!(has_role(&store, admin, ROLE_ADMIN), 0);
            assert!(admin(&store) == admin, 1);
            assert!(admin_count(&store) == 1, 2);
            transfer::public_share_object(store);
        };

        scenario.end();
    }

    #[test]
    fun test_grant_revoke_role() {
        use sui::test_scenario;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create store
        {
            let store = new(scenario.ctx());
            transfer::public_share_object(store);
        };

        // Grant minter role
        scenario.next_tx(admin);
        {
            let mut store = scenario.take_shared<RoleStore>();
            grant_role(&mut store, user, ROLE_MINTER, scenario.ctx());
            assert!(has_role(&store, user, ROLE_MINTER), 0);
            test_scenario::return_shared(store);
        };

        // Revoke minter role
        scenario.next_tx(admin);
        {
            let mut store = scenario.take_shared<RoleStore>();
            revoke_role(&mut store, user, ROLE_MINTER, scenario.ctx());
            assert!(!has_role(&store, user, ROLE_MINTER), 1);
            test_scenario::return_shared(store);
        };

        scenario.end();
    }

    #[test]
    fun test_multiple_roles() {
        use sui::test_scenario;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut store = new(scenario.ctx());
            // Grant minter + operator
            grant_roles(&mut store, user, ROLE_MINTER | ROLE_OPERATOR, scenario.ctx());
            assert!(has_role(&store, user, ROLE_MINTER), 0);
            assert!(has_role(&store, user, ROLE_OPERATOR), 1);
            assert!(!has_role(&store, user, ROLE_PAUSER), 2);
            transfer::public_share_object(store);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EMissingRole)]
    fun test_unauthorized_grant() {
        use sui::test_scenario;

        let admin = @0xAD;
        let attacker = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create store
        {
            let store = new(scenario.ctx());
            transfer::public_share_object(store);
        };

        // Attacker tries to grant role
        scenario.next_tx(attacker);
        {
            let mut store = scenario.take_shared<RoleStore>();
            grant_role(&mut store, attacker, ROLE_ADMIN, scenario.ctx());
            test_scenario::return_shared(store);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ELastAdmin)]
    fun test_cannot_remove_last_admin() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut store = new(scenario.ctx());
            // Try to revoke own admin role - should fail
            revoke_role(&mut store, admin, ROLE_ADMIN, scenario.ctx());
            transfer::public_share_object(store);
        };

        scenario.end();
    }
}
