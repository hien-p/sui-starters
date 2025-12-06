/// @title Whitelist/Allowlist Pattern
/// @notice Address whitelist for access control
/// @dev Part of @sui-starters/access package
module sui_starters_access::whitelist {
    use sui::event;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};

    // === Errors ===

    /// Address is not whitelisted
    const ENotWhitelisted: u64 = 0;

    /// Address is already whitelisted
    const EAlreadyWhitelisted: u64 = 1;

    /// Whitelist is full
    const EWhitelistFull: u64 = 2;

    /// Address is zero
    const EZeroAddress: u64 = 3;

    // === Structs ===

    /// Table-based whitelist (scalable, O(1) lookup)
    public struct Whitelist has key, store {
        id: UID,
        /// Whitelisted addresses
        addresses: Table<address, bool>,
        /// Count of whitelisted addresses
        count: u64,
        /// Maximum allowed (0 = unlimited)
        max_size: u64,
        /// Is whitelist enabled
        enabled: bool,
    }

    /// VecSet-based whitelist (smaller, for limited lists)
    public struct SmallWhitelist has store, drop {
        addresses: VecSet<address>,
        enabled: bool,
    }

    /// Whitelist entry with metadata
    public struct WhitelistEntry has store, copy, drop {
        added_at: u64,
        added_by: address,
    }

    /// Advanced whitelist with entry metadata
    public struct WhitelistWithMeta has key, store {
        id: UID,
        entries: Table<address, WhitelistEntry>,
        count: u64,
        max_size: u64,
        enabled: bool,
    }

    // === Events ===

    /// Emitted when address is added to whitelist
    public struct AddressWhitelisted has copy, drop {
        address: address,
        by: address,
    }

    /// Emitted when address is removed from whitelist
    public struct AddressRemoved has copy, drop {
        address: address,
        by: address,
    }

    /// Emitted when whitelist is enabled/disabled
    public struct WhitelistToggled has copy, drop {
        enabled: bool,
        by: address,
    }

    // === Whitelist (Table-based) Functions ===

    /// Create a new whitelist
    public fun new(ctx: &mut TxContext): Whitelist {
        Whitelist {
            id: object::new(ctx),
            addresses: table::new(ctx),
            count: 0,
            max_size: 0, // unlimited
            enabled: true,
        }
    }

    /// Create a new whitelist with max size
    public fun new_with_max(max_size: u64, ctx: &mut TxContext): Whitelist {
        Whitelist {
            id: object::new(ctx),
            addresses: table::new(ctx),
            count: 0,
            max_size,
            enabled: true,
        }
    }

    /// Add address to whitelist
    public fun add(
        whitelist: &mut Whitelist,
        addr: address,
        ctx: &TxContext
    ) {
        assert!(addr != @0x0, EZeroAddress);
        assert!(!contains(whitelist, addr), EAlreadyWhitelisted);

        if (whitelist.max_size > 0) {
            assert!(whitelist.count < whitelist.max_size, EWhitelistFull);
        };

        table::add(&mut whitelist.addresses, addr, true);
        whitelist.count = whitelist.count + 1;

        event::emit(AddressWhitelisted {
            address: addr,
            by: ctx.sender(),
        });
    }

    /// Add multiple addresses to whitelist
    public fun add_batch(
        whitelist: &mut Whitelist,
        addrs: vector<address>,
        ctx: &TxContext
    ) {
        let len = vector::length(&addrs);
        let mut i = 0;
        while (i < len) {
            let addr = *vector::borrow(&addrs, i);
            if (!contains(whitelist, addr) && addr != @0x0) {
                add(whitelist, addr, ctx);
            };
            i = i + 1;
        };
    }

    /// Remove address from whitelist
    public fun remove(
        whitelist: &mut Whitelist,
        addr: address,
        ctx: &TxContext
    ) {
        assert!(contains(whitelist, addr), ENotWhitelisted);

        table::remove(&mut whitelist.addresses, addr);
        whitelist.count = whitelist.count - 1;

        event::emit(AddressRemoved {
            address: addr,
            by: ctx.sender(),
        });
    }

    /// Check if address is whitelisted
    public fun contains(whitelist: &Whitelist, addr: address): bool {
        table::contains(&whitelist.addresses, addr)
    }

    /// Check if address is allowed (considers enabled state)
    public fun is_allowed(whitelist: &Whitelist, addr: address): bool {
        if (!whitelist.enabled) {
            return true // Whitelist disabled = everyone allowed
        };
        contains(whitelist, addr)
    }

    /// Require address to be whitelisted
    public fun require_whitelisted(whitelist: &Whitelist, addr: address) {
        if (whitelist.enabled) {
            assert!(contains(whitelist, addr), ENotWhitelisted);
        };
    }

    /// Require sender to be whitelisted
    public fun require_sender_whitelisted(whitelist: &Whitelist, ctx: &TxContext) {
        require_whitelisted(whitelist, ctx.sender());
    }

    /// Enable whitelist
    public fun enable(whitelist: &mut Whitelist, ctx: &TxContext) {
        whitelist.enabled = true;
        event::emit(WhitelistToggled {
            enabled: true,
            by: ctx.sender(),
        });
    }

    /// Disable whitelist (everyone allowed)
    public fun disable(whitelist: &mut Whitelist, ctx: &TxContext) {
        whitelist.enabled = false;
        event::emit(WhitelistToggled {
            enabled: false,
            by: ctx.sender(),
        });
    }

    /// Check if whitelist is enabled
    public fun is_enabled(whitelist: &Whitelist): bool {
        whitelist.enabled
    }

    /// Get whitelist count
    public fun count(whitelist: &Whitelist): u64 {
        whitelist.count
    }

    /// Get max size
    public fun max_size(whitelist: &Whitelist): u64 {
        whitelist.max_size
    }

    /// Check if whitelist is full
    public fun is_full(whitelist: &Whitelist): bool {
        whitelist.max_size > 0 && whitelist.count >= whitelist.max_size
    }

    /// Get remaining spots
    public fun remaining(whitelist: &Whitelist): u64 {
        if (whitelist.max_size == 0) {
            // Unlimited
            18446744073709551615 // MAX_U64
        } else if (whitelist.count >= whitelist.max_size) {
            0
        } else {
            whitelist.max_size - whitelist.count
        }
    }

    // === SmallWhitelist Functions ===

    /// Create a new small whitelist (embeddable)
    public fun new_small(): SmallWhitelist {
        SmallWhitelist {
            addresses: vec_set::empty(),
            enabled: true,
        }
    }

    /// Add to small whitelist
    public fun small_add(whitelist: &mut SmallWhitelist, addr: address) {
        assert!(addr != @0x0, EZeroAddress);
        vec_set::insert(&mut whitelist.addresses, addr);
    }

    /// Remove from small whitelist
    public fun small_remove(whitelist: &mut SmallWhitelist, addr: address) {
        vec_set::remove(&mut whitelist.addresses, &addr);
    }

    /// Check if in small whitelist
    public fun small_contains(whitelist: &SmallWhitelist, addr: address): bool {
        vec_set::contains(&whitelist.addresses, &addr)
    }

    /// Check if allowed in small whitelist
    public fun small_is_allowed(whitelist: &SmallWhitelist, addr: address): bool {
        if (!whitelist.enabled) {
            return true
        };
        small_contains(whitelist, addr)
    }

    /// Require whitelisted in small whitelist
    public fun small_require(whitelist: &SmallWhitelist, addr: address) {
        if (whitelist.enabled) {
            assert!(small_contains(whitelist, addr), ENotWhitelisted);
        };
    }

    /// Enable small whitelist
    public fun small_enable(whitelist: &mut SmallWhitelist) {
        whitelist.enabled = true;
    }

    /// Disable small whitelist
    public fun small_disable(whitelist: &mut SmallWhitelist) {
        whitelist.enabled = false;
    }

    /// Get small whitelist size
    public fun small_size(whitelist: &SmallWhitelist): u64 {
        vec_set::length(&whitelist.addresses)
    }

    // === Tests ===

    #[test]
    fun test_whitelist_basic() {
        use sui::test_scenario;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut whitelist = new(scenario.ctx());
            assert!(count(&whitelist) == 0, 0);
            assert!(!contains(&whitelist, user), 1);

            add(&mut whitelist, user, scenario.ctx());
            assert!(count(&whitelist) == 1, 2);
            assert!(contains(&whitelist, user), 3);

            transfer::public_share_object(whitelist);
        };

        scenario.end();
    }

    #[test]
    fun test_whitelist_remove() {
        use sui::test_scenario;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut whitelist = new(scenario.ctx());
            add(&mut whitelist, user, scenario.ctx());
            assert!(contains(&whitelist, user), 0);

            remove(&mut whitelist, user, scenario.ctx());
            assert!(!contains(&whitelist, user), 1);
            assert!(count(&whitelist) == 0, 2);

            transfer::public_share_object(whitelist);
        };

        scenario.end();
    }

    #[test]
    fun test_whitelist_disabled() {
        use sui::test_scenario;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut whitelist = new(scenario.ctx());
            // User not in whitelist but whitelist is enabled
            assert!(!is_allowed(&whitelist, user), 0);

            // Disable whitelist
            disable(&mut whitelist, scenario.ctx());
            // Now everyone is allowed
            assert!(is_allowed(&whitelist, user), 1);

            transfer::public_share_object(whitelist);
        };

        scenario.end();
    }

    #[test]
    fun test_whitelist_max_size() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut whitelist = new_with_max(2, scenario.ctx());
            assert!(max_size(&whitelist) == 2, 0);
            assert!(remaining(&whitelist) == 2, 1);

            add(&mut whitelist, @0x1, scenario.ctx());
            assert!(remaining(&whitelist) == 1, 2);
            assert!(!is_full(&whitelist), 3);

            add(&mut whitelist, @0x2, scenario.ctx());
            assert!(remaining(&whitelist) == 0, 4);
            assert!(is_full(&whitelist), 5);

            transfer::public_share_object(whitelist);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EWhitelistFull)]
    fun test_whitelist_full_error() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut whitelist = new_with_max(1, scenario.ctx());
            add(&mut whitelist, @0x1, scenario.ctx());
            add(&mut whitelist, @0x2, scenario.ctx()); // Should fail

            transfer::public_share_object(whitelist);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ENotWhitelisted)]
    fun test_require_whitelisted_fails() {
        use sui::test_scenario;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let whitelist = new(scenario.ctx());
            require_whitelisted(&whitelist, user); // Should fail

            transfer::public_share_object(whitelist);
        };

        scenario.end();
    }

    #[test]
    fun test_small_whitelist() {
        let mut whitelist = new_small();
        assert!(small_size(&whitelist) == 0, 0);

        small_add(&mut whitelist, @0x1);
        assert!(small_size(&whitelist) == 1, 1);
        assert!(small_contains(&whitelist, @0x1), 2);

        small_remove(&mut whitelist, @0x1);
        assert!(small_size(&whitelist) == 0, 3);
        assert!(!small_contains(&whitelist, @0x1), 4);
    }

    #[test]
    fun test_batch_add() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut whitelist = new(scenario.ctx());
            let addrs = vector[@0x1, @0x2, @0x3];
            add_batch(&mut whitelist, addrs, scenario.ctx());
            assert!(count(&whitelist) == 3, 0);
            assert!(contains(&whitelist, @0x1), 1);
            assert!(contains(&whitelist, @0x2), 2);
            assert!(contains(&whitelist, @0x3), 3);

            transfer::public_share_object(whitelist);
        };

        scenario.end();
    }
}
