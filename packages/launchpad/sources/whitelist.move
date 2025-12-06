/// @title Whitelist
/// @notice Whitelist management for token sales
/// @dev Part of @sui-starters/launchpad package
module sui_starters_launchpad::whitelist {
    use sui::event;
    use sui::table::{Self, Table};

    // === Errors ===

    const ENotWhitelisted: u64 = 0;
    const EAlreadyWhitelisted: u64 = 1;
    const EWhitelistFull: u64 = 2;
    const EWhitelistClosed: u64 = 3;

    // === Structs ===

    /// Whitelist configuration
    public struct Whitelist has key, store {
        id: UID,
        /// Whitelisted addresses with their allocation
        entries: Table<address, WhitelistEntry>,
        /// Maximum whitelist spots
        max_spots: u64,
        /// Current whitelist count
        current_count: u64,
        /// Default allocation per user
        default_allocation: u64,
        /// Is whitelist open for registration
        open: bool,
    }

    /// Individual whitelist entry
    public struct WhitelistEntry has store, copy, drop {
        /// Allocation amount
        allocation: u64,
        /// Has claimed allocation
        claimed: bool,
        /// Timestamp added
        added_at: u64,
        /// Tier (for tiered whitelists)
        tier: u8,
    }

    /// Whitelist proof (can be used to verify eligibility)
    public struct WhitelistProof has key, store {
        id: UID,
        whitelist_id: ID,
        owner: address,
        allocation: u64,
        tier: u8,
    }

    /// Admin capability
    public struct WhitelistAdmin has key, store {
        id: UID,
        whitelist_id: ID,
    }

    // === Events ===

    public struct WhitelistCreated has copy, drop {
        whitelist_id: ID,
        max_spots: u64,
        default_allocation: u64,
    }

    public struct AddressAdded has copy, drop {
        whitelist_id: ID,
        address: address,
        allocation: u64,
        tier: u8,
    }

    public struct AddressRemoved has copy, drop {
        whitelist_id: ID,
        address: address,
    }

    public struct AllocationClaimed has copy, drop {
        whitelist_id: ID,
        address: address,
        amount: u64,
    }

    // === Create Functions ===

    /// Create a new whitelist
    public fun new(
        max_spots: u64,
        default_allocation: u64,
        ctx: &mut TxContext,
    ): (Whitelist, WhitelistAdmin) {
        let whitelist = Whitelist {
            id: object::new(ctx),
            entries: table::new(ctx),
            max_spots,
            current_count: 0,
            default_allocation,
            open: true,
        };

        let whitelist_id = object::id(&whitelist);

        let admin = WhitelistAdmin {
            id: object::new(ctx),
            whitelist_id,
        };

        event::emit(WhitelistCreated {
            whitelist_id,
            max_spots,
            default_allocation,
        });

        (whitelist, admin)
    }

    // === Core Functions ===

    /// Add address to whitelist (admin)
    public fun add(
        whitelist: &mut Whitelist,
        _admin: &WhitelistAdmin,
        addr: address,
        allocation: u64,
        tier: u8,
        timestamp: u64,
    ) {
        assert!(whitelist.current_count < whitelist.max_spots, EWhitelistFull);
        assert!(!table::contains(&whitelist.entries, addr), EAlreadyWhitelisted);

        let entry = WhitelistEntry {
            allocation,
            claimed: false,
            added_at: timestamp,
            tier,
        };

        table::add(&mut whitelist.entries, addr, entry);
        whitelist.current_count = whitelist.current_count + 1;

        event::emit(AddressAdded {
            whitelist_id: object::id(whitelist),
            address: addr,
            allocation,
            tier,
        });
    }

    /// Self-register to whitelist (when open)
    public fun register(
        whitelist: &mut Whitelist,
        timestamp: u64,
        ctx: &TxContext,
    ) {
        assert!(whitelist.open, EWhitelistClosed);
        assert!(whitelist.current_count < whitelist.max_spots, EWhitelistFull);

        let sender = ctx.sender();
        assert!(!table::contains(&whitelist.entries, sender), EAlreadyWhitelisted);

        let entry = WhitelistEntry {
            allocation: whitelist.default_allocation,
            claimed: false,
            added_at: timestamp,
            tier: 0, // Default tier
        };

        table::add(&mut whitelist.entries, sender, entry);
        whitelist.current_count = whitelist.current_count + 1;

        event::emit(AddressAdded {
            whitelist_id: object::id(whitelist),
            address: sender,
            allocation: whitelist.default_allocation,
            tier: 0,
        });
    }

    /// Remove address from whitelist
    public fun remove(
        whitelist: &mut Whitelist,
        _admin: &WhitelistAdmin,
        addr: address,
    ) {
        assert!(table::contains(&whitelist.entries, addr), ENotWhitelisted);

        table::remove(&mut whitelist.entries, addr);
        whitelist.current_count = whitelist.current_count - 1;

        event::emit(AddressRemoved {
            whitelist_id: object::id(whitelist),
            address: addr,
        });
    }

    /// Update allocation for address
    public fun update_allocation(
        whitelist: &mut Whitelist,
        _admin: &WhitelistAdmin,
        addr: address,
        new_allocation: u64,
    ) {
        assert!(table::contains(&whitelist.entries, addr), ENotWhitelisted);

        let entry = table::borrow_mut(&mut whitelist.entries, addr);
        entry.allocation = new_allocation;
    }

    /// Update tier for address
    public fun update_tier(
        whitelist: &mut Whitelist,
        _admin: &WhitelistAdmin,
        addr: address,
        new_tier: u8,
    ) {
        assert!(table::contains(&whitelist.entries, addr), ENotWhitelisted);

        let entry = table::borrow_mut(&mut whitelist.entries, addr);
        entry.tier = new_tier;
    }

    /// Generate whitelist proof for user
    public fun generate_proof(
        whitelist: &Whitelist,
        ctx: &mut TxContext,
    ): WhitelistProof {
        let sender = ctx.sender();
        assert!(table::contains(&whitelist.entries, sender), ENotWhitelisted);

        let entry = table::borrow(&whitelist.entries, sender);

        WhitelistProof {
            id: object::new(ctx),
            whitelist_id: object::id(whitelist),
            owner: sender,
            allocation: entry.allocation,
            tier: entry.tier,
        }
    }

    /// Mark allocation as claimed
    public fun mark_claimed(
        whitelist: &mut Whitelist,
        addr: address,
        amount: u64,
    ) {
        assert!(table::contains(&whitelist.entries, addr), ENotWhitelisted);

        let entry = table::borrow_mut(&mut whitelist.entries, addr);
        entry.claimed = true;

        event::emit(AllocationClaimed {
            whitelist_id: object::id(whitelist),
            address: addr,
            amount,
        });
    }

    /// Consume whitelist proof (for sale integration)
    public fun consume_proof(
        proof: WhitelistProof,
    ): (address, u64, u8) {
        let WhitelistProof {
            id,
            whitelist_id: _,
            owner,
            allocation,
            tier,
        } = proof;

        object::delete(id);

        (owner, allocation, tier)
    }

    // === Admin Functions ===

    /// Open whitelist for registration
    public fun open(
        whitelist: &mut Whitelist,
        _admin: &WhitelistAdmin,
    ) {
        whitelist.open = true;
    }

    /// Close whitelist registration
    public fun close(
        whitelist: &mut Whitelist,
        _admin: &WhitelistAdmin,
    ) {
        whitelist.open = false;
    }

    /// Update max spots
    public fun set_max_spots(
        whitelist: &mut Whitelist,
        _admin: &WhitelistAdmin,
        max_spots: u64,
    ) {
        whitelist.max_spots = max_spots;
    }

    /// Update default allocation
    public fun set_default_allocation(
        whitelist: &mut Whitelist,
        _admin: &WhitelistAdmin,
        allocation: u64,
    ) {
        whitelist.default_allocation = allocation;
    }

    // === View Functions ===

    /// Check if address is whitelisted
    public fun is_whitelisted(whitelist: &Whitelist, addr: address): bool {
        table::contains(&whitelist.entries, addr)
    }

    /// Get allocation for address
    public fun get_allocation(whitelist: &Whitelist, addr: address): u64 {
        assert!(table::contains(&whitelist.entries, addr), ENotWhitelisted);
        let entry = table::borrow(&whitelist.entries, addr);
        entry.allocation
    }

    /// Get tier for address
    public fun get_tier(whitelist: &Whitelist, addr: address): u8 {
        assert!(table::contains(&whitelist.entries, addr), ENotWhitelisted);
        let entry = table::borrow(&whitelist.entries, addr);
        entry.tier
    }

    /// Has claimed
    public fun has_claimed(whitelist: &Whitelist, addr: address): bool {
        assert!(table::contains(&whitelist.entries, addr), ENotWhitelisted);
        let entry = table::borrow(&whitelist.entries, addr);
        entry.claimed
    }

    /// Get entry info
    public fun entry_info(whitelist: &Whitelist, addr: address): (u64, bool, u8) {
        assert!(table::contains(&whitelist.entries, addr), ENotWhitelisted);
        let entry = table::borrow(&whitelist.entries, addr);
        (entry.allocation, entry.claimed, entry.tier)
    }

    /// Get whitelist stats
    public fun stats(whitelist: &Whitelist): (u64, u64, bool) {
        (whitelist.current_count, whitelist.max_spots, whitelist.open)
    }

    /// Remaining spots
    public fun remaining_spots(whitelist: &Whitelist): u64 {
        whitelist.max_spots - whitelist.current_count
    }

    /// Get proof info
    public fun proof_info(proof: &WhitelistProof): (address, u64, u8) {
        (proof.owner, proof.allocation, proof.tier)
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_whitelist() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let (whitelist, admin_cap) = new(100, 1000, scenario.ctx());

            let (count, max, open) = stats(&whitelist);
            assert!(count == 0, 0);
            assert!(max == 100, 1);
            assert!(open, 2);
            assert!(remaining_spots(&whitelist) == 100, 3);

            transfer::public_share_object(whitelist);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_add_to_whitelist() {
        let admin = @0xAD;
        let user1 = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create whitelist
        {
            let (whitelist, admin_cap) = new(100, 1000, scenario.ctx());
            transfer::public_share_object(whitelist);
            transfer::public_transfer(admin_cap, admin);
        };

        // Add user
        scenario.next_tx(admin);
        {
            let mut whitelist = scenario.take_shared<Whitelist>();
            let admin_cap = scenario.take_from_sender<WhitelistAdmin>();

            add(&mut whitelist, &admin_cap, user1, 5000, 2, 1000);

            assert!(is_whitelisted(&whitelist, user1), 0);
            assert!(get_allocation(&whitelist, user1) == 5000, 1);
            assert!(get_tier(&whitelist, user1) == 2, 2);

            test_scenario::return_shared(whitelist);
            scenario.return_to_sender(admin_cap);
        };

        scenario.end();
    }

    #[test]
    fun test_self_register() {
        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create whitelist
        {
            let (whitelist, admin_cap) = new(100, 1000, scenario.ctx());
            transfer::public_share_object(whitelist);
            transfer::public_transfer(admin_cap, admin);
        };

        // User registers
        scenario.next_tx(user);
        {
            let mut whitelist = scenario.take_shared<Whitelist>();

            register(&mut whitelist, 1000, scenario.ctx());

            assert!(is_whitelisted(&whitelist, user), 0);
            assert!(get_allocation(&whitelist, user) == 1000, 1); // Default allocation
            assert!(get_tier(&whitelist, user) == 0, 2); // Default tier

            let (count, _, _) = stats(&whitelist);
            assert!(count == 1, 3);

            test_scenario::return_shared(whitelist);
        };

        scenario.end();
    }

    #[test]
    fun test_generate_proof() {
        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create whitelist and add user
        {
            let (mut whitelist, admin_cap) = new(100, 1000, scenario.ctx());
            add(&mut whitelist, &admin_cap, user, 5000, 2, 1000);
            transfer::public_share_object(whitelist);
            transfer::public_transfer(admin_cap, admin);
        };

        // Generate proof
        scenario.next_tx(user);
        {
            let whitelist = scenario.take_shared<Whitelist>();

            let proof = generate_proof(&whitelist, scenario.ctx());

            let (owner, alloc, tier) = proof_info(&proof);
            assert!(owner == user, 0);
            assert!(alloc == 5000, 1);
            assert!(tier == 2, 2);

            transfer::public_transfer(proof, user);
            test_scenario::return_shared(whitelist);
        };

        scenario.end();
    }

    #[test]
    fun test_close_whitelist() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        // Create and close whitelist
        {
            let (mut whitelist, admin_cap) = new(100, 1000, scenario.ctx());

            close(&mut whitelist, &admin_cap);

            let (_, _, open) = stats(&whitelist);
            assert!(!open, 0);

            transfer::public_share_object(whitelist);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }
}
