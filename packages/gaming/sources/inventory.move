/// @title Inventory System
/// @notice Player inventory management for games
/// @dev Part of @sui-starters/gaming package
module sui_starters_gaming::inventory {
    use std::string::String;
    use sui::event;
    use sui::dynamic_object_field as dof;

    // === Errors ===

    const EInventoryFull: u64 = 0;
    const EItemNotFound: u64 = 1;
    const ESlotOccupied: u64 = 2;
    const EInvalidSlot: u64 = 3;

    // === Structs ===

    /// Player inventory
    public struct Inventory has key, store {
        id: UID,
        owner: address,
        max_slots: u64,
        used_slots: u64,
    }

    /// Generic game item
    public struct GameItem has key, store {
        id: UID,
        name: String,
        item_type: String,
        rarity: u8,
        attributes: vector<Attribute>,
    }

    /// Item attribute
    public struct Attribute has store, copy, drop {
        name: String,
        value: u64,
    }

    // === Events ===

    public struct ItemAdded has copy, drop {
        inventory_id: ID,
        item_id: ID,
        slot: u64,
    }

    public struct ItemRemoved has copy, drop {
        inventory_id: ID,
        item_id: ID,
    }

    // === Create Functions ===

    /// Create new inventory
    public fun new(max_slots: u64, ctx: &mut TxContext): Inventory {
        Inventory {
            id: object::new(ctx),
            owner: ctx.sender(),
            max_slots,
            used_slots: 0,
        }
    }

    /// Create game item
    public fun create_item(
        name: String,
        item_type: String,
        rarity: u8,
        ctx: &mut TxContext,
    ): GameItem {
        GameItem {
            id: object::new(ctx),
            name,
            item_type,
            rarity,
            attributes: vector::empty(),
        }
    }

    // === Inventory Functions ===

    /// Add item to inventory
    public fun add_item(
        inventory: &mut Inventory,
        item: GameItem,
        slot: u64,
    ) {
        assert!(slot < inventory.max_slots, EInvalidSlot);
        assert!(inventory.used_slots < inventory.max_slots, EInventoryFull);
        assert!(!dof::exists_(&inventory.id, slot), ESlotOccupied);

        let item_id = object::id(&item);

        event::emit(ItemAdded {
            inventory_id: object::id(inventory),
            item_id,
            slot,
        });

        dof::add(&mut inventory.id, slot, item);
        inventory.used_slots = inventory.used_slots + 1;
    }

    /// Remove item from inventory
    public fun remove_item(
        inventory: &mut Inventory,
        slot: u64,
    ): GameItem {
        assert!(dof::exists_<u64>(&inventory.id, slot), EItemNotFound);

        let item: GameItem = dof::remove(&mut inventory.id, slot);
        inventory.used_slots = inventory.used_slots - 1;

        event::emit(ItemRemoved {
            inventory_id: object::id(inventory),
            item_id: object::id(&item),
        });

        item
    }

    /// Check if slot has item
    public fun has_item(inventory: &Inventory, slot: u64): bool {
        dof::exists_<u64>(&inventory.id, slot)
    }

    /// Borrow item from slot
    public fun borrow_item(inventory: &Inventory, slot: u64): &GameItem {
        assert!(dof::exists_<u64>(&inventory.id, slot), EItemNotFound);
        dof::borrow(&inventory.id, slot)
    }

    /// Borrow mutable item
    public fun borrow_item_mut(inventory: &mut Inventory, slot: u64): &mut GameItem {
        assert!(dof::exists_<u64>(&inventory.id, slot), EItemNotFound);
        dof::borrow_mut(&mut inventory.id, slot)
    }

    // === Item Functions ===

    /// Add attribute to item
    public fun add_attribute(
        item: &mut GameItem,
        name: String,
        value: u64,
    ) {
        vector::push_back(&mut item.attributes, Attribute { name, value });
    }

    /// Get item info
    public fun item_info(item: &GameItem): (String, String, u8) {
        (item.name, item.item_type, item.rarity)
    }

    // === View Functions ===

    /// Get inventory capacity
    public fun capacity(inventory: &Inventory): (u64, u64) {
        (inventory.used_slots, inventory.max_slots)
    }

    /// Is inventory full
    public fun is_full(inventory: &Inventory): bool {
        inventory.used_slots >= inventory.max_slots
    }

    /// Get free slots
    public fun free_slots(inventory: &Inventory): u64 {
        inventory.max_slots - inventory.used_slots
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use std::string;

    #[test]
    fun test_create_inventory() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let inventory = new(10, scenario.ctx());
            let (used, max) = capacity(&inventory);
            assert!(used == 0, 0);
            assert!(max == 10, 1);
            assert!(!is_full(&inventory), 2);

            transfer::public_transfer(inventory, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_add_remove_item() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut inventory = new(10, scenario.ctx());
            let item = create_item(
                string::utf8(b"Sword"),
                string::utf8(b"weapon"),
                3,
                scenario.ctx(),
            );

            add_item(&mut inventory, item, 0);
            assert!(has_item(&inventory, 0), 0);

            let (used, _) = capacity(&inventory);
            assert!(used == 1, 1);

            let removed_item = remove_item(&mut inventory, 0);
            assert!(!has_item(&inventory, 0), 2);

            transfer::public_transfer(removed_item, admin);
            transfer::public_transfer(inventory, admin);
        };

        scenario.end();
    }
}
