/// @title Equipment System
/// @notice Equippable items with stat bonuses for games
/// @dev Part of @sui-starters/gaming package
module sui_starters_gaming::equipment {
    use std::string::String;
    use sui::event;
    use sui::vec_map::{Self, VecMap};

    // === Errors ===

    const ESlotOccupied: u64 = 0;
    const ESlotEmpty: u64 = 1;
    const EInvalidSlot: u64 = 2;
    const EEquipmentLocked: u64 = 3;
    const ELevelTooLow: u64 = 4;
    const EWrongEquipmentType: u64 = 5;

    // === Constants ===

    /// Equipment slots
    const SLOT_HEAD: u8 = 0;
    const SLOT_BODY: u8 = 1;
    const SLOT_LEGS: u8 = 2;
    const SLOT_FEET: u8 = 3;
    const SLOT_HANDS: u8 = 4;
    const SLOT_MAIN_HAND: u8 = 5;
    const SLOT_OFF_HAND: u8 = 6;
    const SLOT_ACCESSORY_1: u8 = 7;
    const SLOT_ACCESSORY_2: u8 = 8;
    const MAX_SLOTS: u8 = 9;

    // === Structs ===

    /// Equipment piece
    public struct Equipment has key, store {
        id: UID,
        name: String,
        /// Slot this equipment goes in
        slot: u8,
        /// Rarity (0=common, 1=uncommon, 2=rare, 3=epic, 4=legendary)
        rarity: u8,
        /// Required level to equip
        required_level: u64,
        /// Stat type -> bonus value
        stats: VecMap<String, u64>,
        /// Is equipment locked (soulbound)
        locked: bool,
    }

    /// Character's equipment loadout
    public struct EquipmentLoadout has key, store {
        id: UID,
        owner: address,
        /// Slot -> Equipment ID
        equipped: VecMap<u8, ID>,
        /// Cached total stats
        total_stats: VecMap<String, u64>,
    }

    // === Events ===

    public struct EquipmentCreated has copy, drop {
        equipment_id: ID,
        name: String,
        slot: u8,
        rarity: u8,
    }

    public struct ItemEquipped has copy, drop {
        loadout_id: ID,
        equipment_id: ID,
        slot: u8,
    }

    public struct ItemUnequipped has copy, drop {
        loadout_id: ID,
        equipment_id: ID,
        slot: u8,
    }

    // === Create Functions ===

    /// Create new equipment piece
    public fun new_equipment(
        name: String,
        slot: u8,
        rarity: u8,
        required_level: u64,
        stats: VecMap<String, u64>,
        locked: bool,
        ctx: &mut TxContext,
    ): Equipment {
        assert!(slot < MAX_SLOTS, EInvalidSlot);

        let equipment = Equipment {
            id: object::new(ctx),
            name,
            slot,
            rarity,
            required_level,
            stats,
            locked,
        };

        event::emit(EquipmentCreated {
            equipment_id: object::id(&equipment),
            name: equipment.name,
            slot,
            rarity,
        });

        equipment
    }

    /// Create new equipment loadout
    public fun new_loadout(ctx: &mut TxContext): EquipmentLoadout {
        EquipmentLoadout {
            id: object::new(ctx),
            owner: ctx.sender(),
            equipped: vec_map::empty(),
            total_stats: vec_map::empty(),
        }
    }

    // === Core Functions ===

    /// Equip an item
    public fun equip(
        loadout: &mut EquipmentLoadout,
        equipment: Equipment,
        character_level: u64,
    ) {
        assert!(character_level >= equipment.required_level, ELevelTooLow);
        assert!(!vec_map::contains(&loadout.equipped, &equipment.slot), ESlotOccupied);

        let slot = equipment.slot;
        let equipment_id = object::id(&equipment);

        // Add stats to total
        add_stats_to_total(&mut loadout.total_stats, &equipment.stats);

        // Store equipment ID
        vec_map::insert(&mut loadout.equipped, slot, equipment_id);

        event::emit(ItemEquipped {
            loadout_id: object::id(loadout),
            equipment_id,
            slot,
        });

        // Transfer equipment to loadout (using dynamic field would be better in practice)
        transfer::public_transfer(equipment, @0x0); // Placeholder - in real impl use dynamic fields
    }

    /// Unequip an item (returns the slot it was in)
    public fun unequip(
        loadout: &mut EquipmentLoadout,
        slot: u8,
        equipment: &Equipment,
    ): u8 {
        assert!(vec_map::contains(&loadout.equipped, &slot), ESlotEmpty);
        assert!(!equipment.locked, EEquipmentLocked);

        // Remove stats from total
        remove_stats_from_total(&mut loadout.total_stats, &equipment.stats);

        // Remove from equipped
        let (_slot, equipment_id) = vec_map::remove(&mut loadout.equipped, &slot);

        event::emit(ItemUnequipped {
            loadout_id: object::id(loadout),
            equipment_id,
            slot,
        });

        slot
    }

    /// Add stats to total
    fun add_stats_to_total(
        total: &mut VecMap<String, u64>,
        stats: &VecMap<String, u64>,
    ) {
        let mut i = 0;
        let len = vec_map::length(stats);
        while (i < len) {
            let (stat_type, value) = vec_map::get_entry_by_idx(stats, i);
            if (vec_map::contains(total, stat_type)) {
                let current = vec_map::get_mut(total, stat_type);
                *current = *current + *value;
            } else {
                vec_map::insert(total, *stat_type, *value);
            };
            i = i + 1;
        };
    }

    /// Remove stats from total
    fun remove_stats_from_total(
        total: &mut VecMap<String, u64>,
        stats: &VecMap<String, u64>,
    ) {
        let mut i = 0;
        let len = vec_map::length(stats);
        while (i < len) {
            let (stat_type, value) = vec_map::get_entry_by_idx(stats, i);
            if (vec_map::contains(total, stat_type)) {
                let current = vec_map::get_mut(total, stat_type);
                *current = *current - *value;
            };
            i = i + 1;
        };
    }

    // === View Functions ===

    /// Get equipment name
    public fun name(equipment: &Equipment): String {
        equipment.name
    }

    /// Get equipment slot
    public fun slot(equipment: &Equipment): u8 {
        equipment.slot
    }

    /// Get equipment rarity
    public fun rarity(equipment: &Equipment): u8 {
        equipment.rarity
    }

    /// Get required level
    public fun required_level(equipment: &Equipment): u64 {
        equipment.required_level
    }

    /// Check if equipment is locked
    public fun is_locked(equipment: &Equipment): bool {
        equipment.locked
    }

    /// Get equipment stat
    public fun get_stat(equipment: &Equipment, stat_type: &String): u64 {
        if (vec_map::contains(&equipment.stats, stat_type)) {
            *vec_map::get(&equipment.stats, stat_type)
        } else {
            0
        }
    }

    /// Get total stat from loadout
    public fun get_total_stat(loadout: &EquipmentLoadout, stat_type: &String): u64 {
        if (vec_map::contains(&loadout.total_stats, stat_type)) {
            *vec_map::get(&loadout.total_stats, stat_type)
        } else {
            0
        }
    }

    /// Check if slot is equipped
    public fun is_slot_equipped(loadout: &EquipmentLoadout, slot: u8): bool {
        vec_map::contains(&loadout.equipped, &slot)
    }

    /// Get equipped count
    public fun equipped_count(loadout: &EquipmentLoadout): u64 {
        vec_map::length(&loadout.equipped)
    }

    /// Get slot constants
    public fun slot_head(): u8 { SLOT_HEAD }
    public fun slot_body(): u8 { SLOT_BODY }
    public fun slot_legs(): u8 { SLOT_LEGS }
    public fun slot_feet(): u8 { SLOT_FEET }
    public fun slot_hands(): u8 { SLOT_HANDS }
    public fun slot_main_hand(): u8 { SLOT_MAIN_HAND }
    public fun slot_off_hand(): u8 { SLOT_OFF_HAND }
    public fun slot_accessory_1(): u8 { SLOT_ACCESSORY_1 }
    public fun slot_accessory_2(): u8 { SLOT_ACCESSORY_2 }
    public fun max_slots(): u8 { MAX_SLOTS }

    // === Tests ===

    #[test_only]
    use std::string;

    #[test]
    fun test_create_equipment() {
        let ctx = &mut tx_context::dummy();

        let mut stats = vec_map::empty();
        vec_map::insert(&mut stats, string::utf8(b"attack"), 50u64);
        vec_map::insert(&mut stats, string::utf8(b"defense"), 10u64);

        let equipment = new_equipment(
            string::utf8(b"Iron Sword"),
            SLOT_MAIN_HAND,
            2, // rare
            10,
            stats,
            false,
            ctx,
        );

        assert!(name(&equipment) == string::utf8(b"Iron Sword"), 0);
        assert!(slot(&equipment) == SLOT_MAIN_HAND, 1);
        assert!(rarity(&equipment) == 2, 2);
        assert!(required_level(&equipment) == 10, 3);

        let attack_stat = string::utf8(b"attack");
        assert!(get_stat(&equipment, &attack_stat) == 50, 4);

        let Equipment { id, name: _, slot: _, rarity: _, required_level: _, stats: _, locked: _ } = equipment;
        object::delete(id);
    }

    #[test]
    fun test_create_loadout() {
        let ctx = &mut tx_context::dummy();
        let loadout = new_loadout(ctx);

        assert!(equipped_count(&loadout) == 0, 0);
        assert!(!is_slot_equipped(&loadout, SLOT_HEAD), 1);

        let EquipmentLoadout { id, owner: _, equipped, total_stats } = loadout;
        vec_map::destroy_empty(equipped);
        vec_map::destroy_empty(total_stats);
        object::delete(id);
    }

    #[test]
    fun test_slot_constants() {
        assert!(slot_head() == 0, 0);
        assert!(slot_body() == 1, 1);
        assert!(slot_main_hand() == 5, 2);
        assert!(max_slots() == 9, 3);
    }
}
