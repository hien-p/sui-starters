/// @title NFT Collection
/// @notice Collection management with supply tracking and metadata
/// @dev Part of @sui-starters/nft package
module sui_starters_nft::collection {
    use std::string::String;
    use sui::event;
    use sui::package::{Self, Publisher};
    use sui::display::{Self, Display};

    // === Errors ===

    /// Supply limit reached
    const ESupplyLimitReached: u64 = 0;

    /// Invalid supply limit
    const EInvalidSupplyLimit: u64 = 1;

    /// Collection is frozen
    const ECollectionFrozen: u64 = 2;

    /// Not authorized
    const ENotAuthorized: u64 = 3;

    // === Structs ===

    /// Collection metadata and state
    public struct Collection<phantom T> has key, store {
        id: UID,
        /// Collection name
        name: String,
        /// Collection description
        description: String,
        /// Collection image URL
        image_url: String,
        /// External URL
        external_url: String,
        /// Creator address
        creator: address,
        /// Current supply
        supply: u64,
        /// Maximum supply (0 = unlimited)
        max_supply: u64,
        /// Royalty in basis points (e.g., 500 = 5%)
        royalty_bps: u16,
        /// Royalty recipient
        royalty_recipient: address,
        /// Is collection frozen (no more minting)
        frozen: bool,
    }

    /// Collection info (read-only view)
    public struct CollectionInfo has copy, drop, store {
        name: String,
        description: String,
        image_url: String,
        external_url: String,
        creator: address,
        supply: u64,
        max_supply: u64,
        royalty_bps: u16,
        royalty_recipient: address,
        frozen: bool,
    }

    // === Events ===

    /// Emitted when a collection is created
    public struct CollectionCreated has copy, drop {
        collection_id: ID,
        name: String,
        creator: address,
        max_supply: u64,
    }

    /// Emitted when collection metadata is updated
    public struct CollectionUpdated has copy, drop {
        collection_id: ID,
        field: String,
    }

    /// Emitted when supply changes
    public struct SupplyChanged has copy, drop {
        collection_id: ID,
        previous_supply: u64,
        new_supply: u64,
    }

    /// Emitted when collection is frozen
    public struct CollectionFrozen has copy, drop {
        collection_id: ID,
        by: address,
    }

    // === Create Functions ===

    /// Create a new collection
    public fun new<T>(
        name: String,
        description: String,
        image_url: String,
        external_url: String,
        max_supply: u64,
        royalty_bps: u16,
        ctx: &mut TxContext,
    ): Collection<T> {
        let creator = ctx.sender();
        let collection = Collection<T> {
            id: object::new(ctx),
            name,
            description,
            image_url,
            external_url,
            creator,
            supply: 0,
            max_supply,
            royalty_bps,
            royalty_recipient: creator,
            frozen: false,
        };

        event::emit(CollectionCreated {
            collection_id: object::id(&collection),
            name: collection.name,
            creator,
            max_supply,
        });

        collection
    }

    /// Create a new collection with custom royalty recipient
    public fun new_with_royalty_recipient<T>(
        name: String,
        description: String,
        image_url: String,
        external_url: String,
        max_supply: u64,
        royalty_bps: u16,
        royalty_recipient: address,
        ctx: &mut TxContext,
    ): Collection<T> {
        let creator = ctx.sender();
        let collection = Collection<T> {
            id: object::new(ctx),
            name,
            description,
            image_url,
            external_url,
            creator,
            supply: 0,
            max_supply,
            royalty_bps,
            royalty_recipient,
            frozen: false,
        };

        event::emit(CollectionCreated {
            collection_id: object::id(&collection),
            name: collection.name,
            creator,
            max_supply,
        });

        collection
    }

    // === Supply Management ===

    /// Increment supply (called when minting)
    public fun increment_supply<T>(collection: &mut Collection<T>) {
        assert!(!collection.frozen, ECollectionFrozen);
        if (collection.max_supply > 0) {
            assert!(collection.supply < collection.max_supply, ESupplyLimitReached);
        };

        let previous_supply = collection.supply;
        collection.supply = collection.supply + 1;

        event::emit(SupplyChanged {
            collection_id: object::id(collection),
            previous_supply,
            new_supply: collection.supply,
        });
    }

    /// Decrement supply (called when burning)
    public fun decrement_supply<T>(collection: &mut Collection<T>) {
        let previous_supply = collection.supply;
        collection.supply = collection.supply - 1;

        event::emit(SupplyChanged {
            collection_id: object::id(collection),
            previous_supply,
            new_supply: collection.supply,
        });
    }

    /// Check if can mint
    public fun can_mint<T>(collection: &Collection<T>): bool {
        if (collection.frozen) {
            return false
        };
        if (collection.max_supply == 0) {
            return true // Unlimited
        };
        collection.supply < collection.max_supply
    }

    /// Get remaining mintable
    public fun remaining<T>(collection: &Collection<T>): u64 {
        if (collection.max_supply == 0) {
            18446744073709551615 // MAX_U64
        } else if (collection.supply >= collection.max_supply) {
            0
        } else {
            collection.max_supply - collection.supply
        }
    }

    // === Freeze Functions ===

    /// Freeze collection (no more minting)
    public fun freeze_collection<T>(collection: &mut Collection<T>, ctx: &TxContext) {
        assert!(!collection.frozen, ECollectionFrozen);
        collection.frozen = true;

        event::emit(CollectionFrozen {
            collection_id: object::id(collection),
            by: ctx.sender(),
        });
    }

    /// Check if frozen
    public fun is_frozen<T>(collection: &Collection<T>): bool {
        collection.frozen
    }

    // === Update Functions ===

    /// Update collection name
    public fun set_name<T>(collection: &mut Collection<T>, name: String) {
        collection.name = name;
        event::emit(CollectionUpdated {
            collection_id: object::id(collection),
            field: std::string::utf8(b"name"),
        });
    }

    /// Update collection description
    public fun set_description<T>(collection: &mut Collection<T>, description: String) {
        collection.description = description;
        event::emit(CollectionUpdated {
            collection_id: object::id(collection),
            field: std::string::utf8(b"description"),
        });
    }

    /// Update collection image URL
    public fun set_image_url<T>(collection: &mut Collection<T>, image_url: String) {
        collection.image_url = image_url;
        event::emit(CollectionUpdated {
            collection_id: object::id(collection),
            field: std::string::utf8(b"image_url"),
        });
    }

    /// Update external URL
    public fun set_external_url<T>(collection: &mut Collection<T>, external_url: String) {
        collection.external_url = external_url;
        event::emit(CollectionUpdated {
            collection_id: object::id(collection),
            field: std::string::utf8(b"external_url"),
        });
    }

    /// Update royalty
    public fun set_royalty<T>(
        collection: &mut Collection<T>,
        royalty_bps: u16,
        royalty_recipient: address
    ) {
        collection.royalty_bps = royalty_bps;
        collection.royalty_recipient = royalty_recipient;
        event::emit(CollectionUpdated {
            collection_id: object::id(collection),
            field: std::string::utf8(b"royalty"),
        });
    }

    // === View Functions ===

    /// Get collection name
    public fun name<T>(collection: &Collection<T>): String {
        collection.name
    }

    /// Get collection description
    public fun description<T>(collection: &Collection<T>): String {
        collection.description
    }

    /// Get collection image URL
    public fun image_url<T>(collection: &Collection<T>): String {
        collection.image_url
    }

    /// Get external URL
    public fun external_url<T>(collection: &Collection<T>): String {
        collection.external_url
    }

    /// Get creator
    public fun creator<T>(collection: &Collection<T>): address {
        collection.creator
    }

    /// Get current supply
    public fun supply<T>(collection: &Collection<T>): u64 {
        collection.supply
    }

    /// Get max supply
    public fun max_supply<T>(collection: &Collection<T>): u64 {
        collection.max_supply
    }

    /// Get royalty in basis points
    public fun royalty_bps<T>(collection: &Collection<T>): u16 {
        collection.royalty_bps
    }

    /// Get royalty recipient
    public fun royalty_recipient<T>(collection: &Collection<T>): address {
        collection.royalty_recipient
    }

    /// Get collection ID
    public fun id<T>(collection: &Collection<T>): ID {
        object::id(collection)
    }

    /// Get collection info
    public fun info<T>(collection: &Collection<T>): CollectionInfo {
        CollectionInfo {
            name: collection.name,
            description: collection.description,
            image_url: collection.image_url,
            external_url: collection.external_url,
            creator: collection.creator,
            supply: collection.supply,
            max_supply: collection.max_supply,
            royalty_bps: collection.royalty_bps,
            royalty_recipient: collection.royalty_recipient,
            frozen: collection.frozen,
        }
    }

    /// Calculate royalty amount
    public fun calculate_royalty<T>(collection: &Collection<T>, price: u64): u64 {
        ((price as u128) * (collection.royalty_bps as u128) / 10000) as u64
    }

    // === Display Setup ===

    /// Create display for NFT type using Publisher
    public fun create_display<T: key + store>(
        publisher: &Publisher,
        ctx: &mut TxContext,
    ): Display<T> {
        display::new<T>(publisher, ctx)
    }

    /// Setup standard display fields
    public fun setup_display<T: key + store>(
        display: &mut Display<T>,
        name_template: String,
        description_template: String,
        image_url_template: String,
    ) {
        display::add(display, std::string::utf8(b"name"), name_template);
        display::add(display, std::string::utf8(b"description"), description_template);
        display::add(display, std::string::utf8(b"image_url"), image_url_template);
    }

    // === Tests ===

    /// Test witness type
    public struct TEST_NFT has drop {}

    #[test]
    fun test_create_collection() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let collection = new<TEST_NFT>(
                string::utf8(b"Test Collection"),
                string::utf8(b"A test NFT collection"),
                string::utf8(b"https://example.com/image.png"),
                string::utf8(b"https://example.com"),
                1000,
                500, // 5%
                scenario.ctx(),
            );

            assert!(name(&collection) == string::utf8(b"Test Collection"), 0);
            assert!(supply(&collection) == 0, 1);
            assert!(max_supply(&collection) == 1000, 2);
            assert!(royalty_bps(&collection) == 500, 3);
            assert!(creator(&collection) == creator, 4);
            assert!(!is_frozen(&collection), 5);

            transfer::public_share_object(collection);
        };

        scenario.end();
    }

    #[test]
    fun test_increment_supply() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut collection = new<TEST_NFT>(
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                string::utf8(b""),
                string::utf8(b""),
                100,
                0,
                scenario.ctx(),
            );

            assert!(supply(&collection) == 0, 0);
            assert!(can_mint(&collection), 1);

            increment_supply(&mut collection);
            assert!(supply(&collection) == 1, 2);

            increment_supply(&mut collection);
            assert!(supply(&collection) == 2, 3);

            transfer::public_share_object(collection);
        };

        scenario.end();
    }

    #[test]
    fun test_decrement_supply() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut collection = new<TEST_NFT>(
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                string::utf8(b""),
                string::utf8(b""),
                100,
                0,
                scenario.ctx(),
            );

            increment_supply(&mut collection);
            increment_supply(&mut collection);
            assert!(supply(&collection) == 2, 0);

            decrement_supply(&mut collection);
            assert!(supply(&collection) == 1, 1);

            transfer::public_share_object(collection);
        };

        scenario.end();
    }

    #[test]
    fun test_unlimited_supply() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let collection = new<TEST_NFT>(
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                string::utf8(b""),
                string::utf8(b""),
                0, // Unlimited
                0,
                scenario.ctx(),
            );

            assert!(max_supply(&collection) == 0, 0);
            assert!(can_mint(&collection), 1);
            assert!(remaining(&collection) == 18446744073709551615, 2);

            transfer::public_share_object(collection);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ESupplyLimitReached)]
    fun test_supply_limit() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut collection = new<TEST_NFT>(
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                string::utf8(b""),
                string::utf8(b""),
                2, // Max 2
                0,
                scenario.ctx(),
            );

            increment_supply(&mut collection);
            increment_supply(&mut collection);
            increment_supply(&mut collection); // Should fail

            transfer::public_share_object(collection);
        };

        scenario.end();
    }

    #[test]
    fun test_freeze_collection() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut collection = new<TEST_NFT>(
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                string::utf8(b""),
                string::utf8(b""),
                100,
                0,
                scenario.ctx(),
            );

            assert!(!is_frozen(&collection), 0);
            assert!(can_mint(&collection), 1);

            freeze_collection(&mut collection, scenario.ctx());

            assert!(is_frozen(&collection), 2);
            assert!(!can_mint(&collection), 3);

            transfer::public_share_object(collection);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ECollectionFrozen)]
    fun test_cannot_mint_frozen() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut collection = new<TEST_NFT>(
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                string::utf8(b""),
                string::utf8(b""),
                100,
                0,
                scenario.ctx(),
            );

            freeze_collection(&mut collection, scenario.ctx());
            increment_supply(&mut collection); // Should fail

            transfer::public_share_object(collection);
        };

        scenario.end();
    }

    #[test]
    fun test_calculate_royalty() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let collection = new<TEST_NFT>(
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                string::utf8(b""),
                string::utf8(b""),
                100,
                500, // 5%
                scenario.ctx(),
            );

            // 5% of 1000 = 50
            assert!(calculate_royalty(&collection, 1000) == 50, 0);
            // 5% of 10000 = 500
            assert!(calculate_royalty(&collection, 10000) == 500, 1);
            // 5% of 100 = 5
            assert!(calculate_royalty(&collection, 100) == 5, 2);

            transfer::public_share_object(collection);
        };

        scenario.end();
    }

    #[test]
    fun test_update_metadata() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut collection = new<TEST_NFT>(
                string::utf8(b"Test"),
                string::utf8(b"Test"),
                string::utf8(b""),
                string::utf8(b""),
                100,
                500,
                scenario.ctx(),
            );

            set_name(&mut collection, string::utf8(b"New Name"));
            assert!(name(&collection) == string::utf8(b"New Name"), 0);

            set_description(&mut collection, string::utf8(b"New Description"));
            assert!(description(&collection) == string::utf8(b"New Description"), 1);

            set_royalty(&mut collection, 1000, @0x2);
            assert!(royalty_bps(&collection) == 1000, 2);
            assert!(royalty_recipient(&collection) == @0x2, 3);

            transfer::public_share_object(collection);
        };

        scenario.end();
    }

    #[test]
    fun test_collection_info() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let collection = new<TEST_NFT>(
                string::utf8(b"Test Collection"),
                string::utf8(b"Description"),
                string::utf8(b"https://image.url"),
                string::utf8(b"https://external.url"),
                1000,
                500,
                scenario.ctx(),
            );

            let collection_info = info(&collection);
            assert!(collection_info.name == string::utf8(b"Test Collection"), 0);
            assert!(collection_info.description == string::utf8(b"Description"), 1);
            assert!(collection_info.max_supply == 1000, 2);
            assert!(collection_info.royalty_bps == 500, 3);

            transfer::public_share_object(collection);
        };

        scenario.end();
    }
}
