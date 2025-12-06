/// @title Composable NFTs
/// @notice Parent-child NFT relationships and nesting
/// @dev Part of @sui-starters/nft package
module sui_starters_nft::composable {
    use std::string::String;
    use sui::event;
    use sui::dynamic_object_field as dof;
    use sui::dynamic_field as df;

    // === Errors ===

    /// Maximum children reached
    const EMaxChildrenReached: u64 = 0;

    /// Child not found
    const EChildNotFound: u64 = 1;

    /// Cannot nest into self
    const ECannotNestSelf: u64 = 2;

    /// Slot is occupied
    const ESlotOccupied: u64 = 3;

    /// Slot is empty
    const ESlotEmpty: u64 = 4;

    /// Invalid slot
    const EInvalidSlot: u64 = 5;

    /// Not authorized
    const ENotAuthorized: u64 = 6;

    // === Structs ===

    /// Composable NFT that can hold children
    public struct ComposableNFT<phantom T> has key, store {
        id: UID,
        /// NFT name
        name: String,
        /// NFT description
        description: String,
        /// NFT image URL
        image_url: String,
        /// Number of children
        child_count: u64,
        /// Maximum children (0 = unlimited)
        max_children: u64,
    }

    /// Slot-based composable (e.g., equipment slots)
    public struct SlotBasedNFT<phantom T> has key, store {
        id: UID,
        /// NFT name
        name: String,
        /// Slot names
        slot_names: vector<String>,
        /// Number of slots
        slot_count: u64,
    }

    /// Key for child NFT storage
    public struct ChildKey has copy, drop, store {
        index: u64,
    }

    /// Key for slot storage
    public struct SlotKey has copy, drop, store {
        name: String,
    }

    /// Child info for tracking
    public struct ChildInfo has store, copy, drop {
        child_id: ID,
        added_at: u64,
    }

    // === Events ===

    /// Emitted when child is attached
    public struct ChildAttached has copy, drop {
        parent_id: ID,
        child_id: ID,
        index: u64,
    }

    /// Emitted when child is detached
    public struct ChildDetached has copy, drop {
        parent_id: ID,
        child_id: ID,
    }

    /// Emitted when item is equipped to slot
    public struct ItemEquipped has copy, drop {
        nft_id: ID,
        slot: String,
        item_id: ID,
    }

    /// Emitted when item is unequipped from slot
    public struct ItemUnequipped has copy, drop {
        nft_id: ID,
        slot: String,
        item_id: ID,
    }

    // === ComposableNFT Functions ===

    /// Create new composable NFT
    public fun new<T>(
        name: String,
        description: String,
        image_url: String,
        max_children: u64,
        ctx: &mut TxContext,
    ): ComposableNFT<T> {
        ComposableNFT<T> {
            id: object::new(ctx),
            name,
            description,
            image_url,
            child_count: 0,
            max_children,
        }
    }

    /// Attach child NFT
    public fun attach_child<T, C: key + store>(
        parent: &mut ComposableNFT<T>,
        child: C,
        timestamp: u64,
    ) {
        let child_id = object::id(&child);
        assert!(object::id(parent) != object::id_from_address(object::id_to_address(&child_id)), ECannotNestSelf);

        if (parent.max_children > 0) {
            assert!(parent.child_count < parent.max_children, EMaxChildrenReached);
        };

        let index = parent.child_count;
        let key = ChildKey { index };

        dof::add(&mut parent.id, key, child);

        // Store child info for tracking
        let info = ChildInfo { child_id, added_at: timestamp };
        df::add(&mut parent.id, child_id, info);

        parent.child_count = parent.child_count + 1;

        event::emit(ChildAttached {
            parent_id: object::id(parent),
            child_id,
            index,
        });
    }

    /// Detach child NFT by index
    public fun detach_child<T, C: key + store>(
        parent: &mut ComposableNFT<T>,
        index: u64,
    ): C {
        assert!(index < parent.child_count, EChildNotFound);

        let key = ChildKey { index };
        let child: C = dof::remove(&mut parent.id, key);
        let child_id = object::id(&child);

        // Remove child info
        let _info: ChildInfo = df::remove(&mut parent.id, child_id);

        parent.child_count = parent.child_count - 1;

        event::emit(ChildDetached {
            parent_id: object::id(parent),
            child_id,
        });

        child
    }

    /// Get child count
    public fun child_count<T>(parent: &ComposableNFT<T>): u64 {
        parent.child_count
    }

    /// Get max children
    public fun max_children<T>(parent: &ComposableNFT<T>): u64 {
        parent.max_children
    }

    /// Check if has child at index
    public fun has_child<T>(parent: &ComposableNFT<T>, index: u64): bool {
        let key = ChildKey { index };
        dof::exists_(&parent.id, key)
    }

    /// Borrow child immutably
    public fun borrow_child<T, C: key + store>(parent: &ComposableNFT<T>, index: u64): &C {
        let key = ChildKey { index };
        dof::borrow(&parent.id, key)
    }

    /// Borrow child mutably
    public fun borrow_child_mut<T, C: key + store>(parent: &mut ComposableNFT<T>, index: u64): &mut C {
        let key = ChildKey { index };
        dof::borrow_mut(&mut parent.id, key)
    }

    /// Get composable name
    public fun name<T>(nft: &ComposableNFT<T>): String {
        nft.name
    }

    /// Get composable description
    public fun description<T>(nft: &ComposableNFT<T>): String {
        nft.description
    }

    /// Get composable image URL
    public fun image_url<T>(nft: &ComposableNFT<T>): String {
        nft.image_url
    }

    /// Destroy empty composable NFT
    public fun destroy_empty<T>(nft: ComposableNFT<T>) {
        assert!(nft.child_count == 0, EChildNotFound);

        let ComposableNFT { id, name: _, description: _, image_url: _, child_count: _, max_children: _ } = nft;
        object::delete(id);
    }

    // === SlotBasedNFT Functions ===

    /// Create slot-based NFT
    public fun new_slotted<T>(
        name: String,
        slot_names: vector<String>,
        ctx: &mut TxContext,
    ): SlotBasedNFT<T> {
        let slot_count = vector::length(&slot_names);
        SlotBasedNFT<T> {
            id: object::new(ctx),
            name,
            slot_names,
            slot_count,
        }
    }

    /// Equip item to slot
    public fun equip<T, I: key + store>(
        nft: &mut SlotBasedNFT<T>,
        slot: String,
        item: I,
    ) {
        // Verify slot exists
        assert!(is_valid_slot(nft, &slot), EInvalidSlot);

        let key = SlotKey { name: slot };
        assert!(!dof::exists_(&nft.id, key), ESlotOccupied);

        let item_id = object::id(&item);
        dof::add(&mut nft.id, key, item);

        event::emit(ItemEquipped {
            nft_id: object::id(nft),
            slot,
            item_id,
        });
    }

    /// Unequip item from slot
    public fun unequip<T, I: key + store>(
        nft: &mut SlotBasedNFT<T>,
        slot: String,
    ): I {
        let key = SlotKey { name: slot };
        assert!(dof::exists_(&nft.id, key), ESlotEmpty);

        let item: I = dof::remove(&mut nft.id, key);
        let item_id = object::id(&item);

        event::emit(ItemUnequipped {
            nft_id: object::id(nft),
            slot,
            item_id,
        });

        item
    }

    /// Check if slot is equipped
    public fun is_equipped<T>(nft: &SlotBasedNFT<T>, slot: &String): bool {
        let key = SlotKey { name: *slot };
        dof::exists_(&nft.id, key)
    }

    /// Check if slot name is valid
    public fun is_valid_slot<T>(nft: &SlotBasedNFT<T>, slot: &String): bool {
        let mut i = 0;
        let len = vector::length(&nft.slot_names);
        while (i < len) {
            if (vector::borrow(&nft.slot_names, i) == slot) {
                return true
            };
            i = i + 1;
        };
        false
    }

    /// Borrow equipped item
    public fun borrow_equipped<T, I: key + store>(nft: &SlotBasedNFT<T>, slot: String): &I {
        let key = SlotKey { name: slot };
        dof::borrow(&nft.id, key)
    }

    /// Borrow equipped item mutably
    public fun borrow_equipped_mut<T, I: key + store>(nft: &mut SlotBasedNFT<T>, slot: String): &mut I {
        let key = SlotKey { name: slot };
        dof::borrow_mut(&mut nft.id, key)
    }

    /// Get slot count
    public fun slot_count<T>(nft: &SlotBasedNFT<T>): u64 {
        nft.slot_count
    }

    /// Get slot names
    public fun slot_names<T>(nft: &SlotBasedNFT<T>): vector<String> {
        nft.slot_names
    }

    /// Get slotted NFT name
    public fun slotted_name<T>(nft: &SlotBasedNFT<T>): String {
        nft.name
    }

    // === Tests ===

    /// Test witness types
    public struct TEST_PARENT has drop {}
    public struct TEST_CHILD has drop {}

    /// Simple test child NFT
    public struct SimpleChild has key, store {
        id: UID,
        value: u64,
    }

    #[test]
    fun test_composable_basic() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let parent = new<TEST_PARENT>(
                string::utf8(b"Parent NFT"),
                string::utf8(b"A composable NFT"),
                string::utf8(b"https://image.url"),
                10,
                scenario.ctx(),
            );

            assert!(name(&parent) == string::utf8(b"Parent NFT"), 0);
            assert!(child_count(&parent) == 0, 1);
            assert!(max_children(&parent) == 10, 2);

            destroy_empty(parent);
        };

        scenario.end();
    }

    #[test]
    fun test_attach_detach_child() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut parent = new<TEST_PARENT>(
                string::utf8(b"Parent"),
                string::utf8(b""),
                string::utf8(b""),
                10,
                scenario.ctx(),
            );

            let child = SimpleChild {
                id: object::new(scenario.ctx()),
                value: 42,
            };

            attach_child(&mut parent, child, 1000);
            assert!(child_count(&parent) == 1, 0);
            assert!(has_child<TEST_PARENT>(&parent, 0), 1);

            let detached: SimpleChild = detach_child(&mut parent, 0);
            assert!(child_count(&parent) == 0, 2);
            assert!(detached.value == 42, 3);

            let SimpleChild { id, value: _ } = detached;
            object::delete(id);
            destroy_empty(parent);
        };

        scenario.end();
    }

    #[test]
    fun test_multiple_children() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut parent = new<TEST_PARENT>(
                string::utf8(b"Parent"),
                string::utf8(b""),
                string::utf8(b""),
                10,
                scenario.ctx(),
            );

            let child1 = SimpleChild { id: object::new(scenario.ctx()), value: 1 };
            let child2 = SimpleChild { id: object::new(scenario.ctx()), value: 2 };
            let child3 = SimpleChild { id: object::new(scenario.ctx()), value: 3 };

            attach_child(&mut parent, child1, 1000);
            attach_child(&mut parent, child2, 1001);
            attach_child(&mut parent, child3, 1002);

            assert!(child_count(&parent) == 3, 0);

            // Detach in reverse order
            let c3: SimpleChild = detach_child(&mut parent, 2);
            let c2: SimpleChild = detach_child(&mut parent, 1);
            let c1: SimpleChild = detach_child(&mut parent, 0);

            assert!(c1.value == 1, 1);
            assert!(c2.value == 2, 2);
            assert!(c3.value == 3, 3);

            let SimpleChild { id, value: _ } = c1;
            object::delete(id);
            let SimpleChild { id, value: _ } = c2;
            object::delete(id);
            let SimpleChild { id, value: _ } = c3;
            object::delete(id);
            destroy_empty(parent);
        };

        scenario.end();
    }

    #[test]
    fun test_slotted_nft() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let slots = vector[
                string::utf8(b"head"),
                string::utf8(b"body"),
                string::utf8(b"weapon"),
            ];

            let mut character = new_slotted<TEST_PARENT>(
                string::utf8(b"Character"),
                slots,
                scenario.ctx(),
            );

            assert!(slot_count(&character) == 3, 0);
            assert!(is_valid_slot(&character, &string::utf8(b"head")), 1);
            assert!(!is_valid_slot(&character, &string::utf8(b"invalid")), 2);
            assert!(!is_equipped(&character, &string::utf8(b"head")), 3);

            // Equip item
            let helmet = SimpleChild { id: object::new(scenario.ctx()), value: 100 };
            equip(&mut character, string::utf8(b"head"), helmet);

            assert!(is_equipped(&character, &string::utf8(b"head")), 4);

            // Unequip
            let helmet: SimpleChild = unequip(&mut character, string::utf8(b"head"));
            assert!(!is_equipped(&character, &string::utf8(b"head")), 5);

            let SimpleChild { id, value: _ } = helmet;
            object::delete(id);

            let SlotBasedNFT { id, name: _, slot_names: _, slot_count: _ } = character;
            object::delete(id);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ESlotOccupied)]
    fun test_slot_occupied() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let slots = vector[string::utf8(b"weapon")];
            let mut character = new_slotted<TEST_PARENT>(
                string::utf8(b"Character"),
                slots,
                scenario.ctx(),
            );

            let sword1 = SimpleChild { id: object::new(scenario.ctx()), value: 1 };
            let sword2 = SimpleChild { id: object::new(scenario.ctx()), value: 2 };

            equip(&mut character, string::utf8(b"weapon"), sword1);
            equip(&mut character, string::utf8(b"weapon"), sword2); // Should fail

            let SlotBasedNFT { id, name: _, slot_names: _, slot_count: _ } = character;
            object::delete(id);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EMaxChildrenReached)]
    fun test_max_children() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut parent = new<TEST_PARENT>(
                string::utf8(b"Parent"),
                string::utf8(b""),
                string::utf8(b""),
                2, // Max 2 children
                scenario.ctx(),
            );

            let child1 = SimpleChild { id: object::new(scenario.ctx()), value: 1 };
            let child2 = SimpleChild { id: object::new(scenario.ctx()), value: 2 };
            let child3 = SimpleChild { id: object::new(scenario.ctx()), value: 3 };

            attach_child(&mut parent, child1, 1000);
            attach_child(&mut parent, child2, 1001);
            attach_child(&mut parent, child3, 1002); // Should fail

            destroy_empty(parent);
        };

        scenario.end();
    }

    #[test]
    fun test_borrow_child() {
        use sui::test_scenario;
        use std::string;

        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut parent = new<TEST_PARENT>(
                string::utf8(b"Parent"),
                string::utf8(b""),
                string::utf8(b""),
                10,
                scenario.ctx(),
            );

            let child = SimpleChild { id: object::new(scenario.ctx()), value: 42 };
            attach_child(&mut parent, child, 1000);

            // Borrow and check value
            let borrowed: &SimpleChild = borrow_child(&parent, 0);
            assert!(borrowed.value == 42, 0);

            // Borrow mutably and modify
            let borrowed_mut: &mut SimpleChild = borrow_child_mut(&mut parent, 0);
            borrowed_mut.value = 100;

            let borrowed2: &SimpleChild = borrow_child(&parent, 0);
            assert!(borrowed2.value == 100, 1);

            let detached: SimpleChild = detach_child(&mut parent, 0);
            let SimpleChild { id, value: _ } = detached;
            object::delete(id);
            destroy_empty(parent);
        };

        scenario.end();
    }
}
