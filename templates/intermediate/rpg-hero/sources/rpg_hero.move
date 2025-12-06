/// @title RPG Hero
/// @notice Character NFT with stats, leveling, and equipment
/// @dev Demonstrates dynamic fields, complex state, and game mechanics
module rpg_hero::rpg_hero {
    use std::string::String;
    use sui::event;
    use sui::dynamic_object_field as dof;

    // === Errors ===

    const ENotEnoughXP: u64 = 0;
    const EMaxLevelReached: u64 = 1;
    const ESlotOccupied: u64 = 2;
    const ENoItemEquipped: u64 = 3;
    const EHeroIsDead: u64 = 4;

    // === Constants ===

    const MAX_LEVEL: u64 = 100;
    const XP_PER_LEVEL: u64 = 100;

    // === Structs ===

    /// RPG Hero character
    public struct Hero has key, store {
        id: UID,
        name: String,
        class: String,
        /// Current level
        level: u64,
        /// Experience points
        xp: u64,
        /// Base stats
        strength: u64,
        agility: u64,
        intelligence: u64,
        vitality: u64,
        /// Current HP
        hp: u64,
        /// Max HP
        max_hp: u64,
        /// Stat points available
        stat_points: u64,
        /// Is hero alive
        alive: bool,
    }

    /// Equipment item
    public struct Equipment has key, store {
        id: UID,
        name: String,
        slot: String,
        /// Stat bonuses
        strength_bonus: u64,
        agility_bonus: u64,
        intelligence_bonus: u64,
        vitality_bonus: u64,
    }

    /// Equipment slot key
    public struct EquipmentSlot has copy, drop, store {
        slot: String,
    }

    // === Events ===

    public struct HeroCreated has copy, drop {
        hero_id: ID,
        name: String,
        class: String,
    }

    public struct LevelUp has copy, drop {
        hero_id: ID,
        new_level: u64,
        stat_points_gained: u64,
    }

    public struct XPGained has copy, drop {
        hero_id: ID,
        amount: u64,
        total_xp: u64,
    }

    public struct ItemEquipped has copy, drop {
        hero_id: ID,
        item_name: String,
        slot: String,
    }

    public struct ItemUnequipped has copy, drop {
        hero_id: ID,
        item_name: String,
        slot: String,
    }

    // === Entry Functions ===

    /// Create a new hero
    public entry fun create_hero(
        name: String,
        class: String,
        ctx: &mut TxContext,
    ) {
        // Base stats by class
        let (str, agi, int, vit) = if (class == std::string::utf8(b"Warrior")) {
            (12, 8, 5, 10)
        } else if (class == std::string::utf8(b"Rogue")) {
            (8, 12, 6, 8)
        } else if (class == std::string::utf8(b"Mage")) {
            (5, 6, 14, 7)
        } else {
            (8, 8, 8, 8) // Balanced
        };

        let max_hp = vit * 10;

        let hero = Hero {
            id: object::new(ctx),
            name,
            class,
            level: 1,
            xp: 0,
            strength: str,
            agility: agi,
            intelligence: int,
            vitality: vit,
            hp: max_hp,
            max_hp,
            stat_points: 0,
            alive: true,
        };

        event::emit(HeroCreated {
            hero_id: object::id(&hero),
            name: hero.name,
            class: hero.class,
        });

        transfer::transfer(hero, ctx.sender());
    }

    /// Gain XP and potentially level up
    public entry fun gain_xp(hero: &mut Hero, amount: u64) {
        assert!(hero.alive, EHeroIsDead);

        hero.xp = hero.xp + amount;

        event::emit(XPGained {
            hero_id: object::id(hero),
            amount,
            total_xp: hero.xp,
        });

        // Check for level ups
        while (hero.xp >= xp_for_next_level(hero.level) && hero.level < MAX_LEVEL) {
            hero.level = hero.level + 1;
            hero.stat_points = hero.stat_points + 5;
            hero.max_hp = hero.vitality * 10 + (hero.level * 5);
            hero.hp = hero.max_hp; // Full heal on level up

            event::emit(LevelUp {
                hero_id: object::id(hero),
                new_level: hero.level,
                stat_points_gained: 5,
            });
        }
    }

    /// Allocate stat points
    public entry fun allocate_stats(
        hero: &mut Hero,
        strength: u64,
        agility: u64,
        intelligence: u64,
        vitality: u64,
    ) {
        let total = strength + agility + intelligence + vitality;
        assert!(total <= hero.stat_points, ENotEnoughXP);

        hero.strength = hero.strength + strength;
        hero.agility = hero.agility + agility;
        hero.intelligence = hero.intelligence + intelligence;
        hero.vitality = hero.vitality + vitality;
        hero.stat_points = hero.stat_points - total;

        // Update max HP based on new vitality
        hero.max_hp = hero.vitality * 10 + (hero.level * 5);
    }

    /// Create equipment
    public entry fun create_equipment(
        name: String,
        slot: String,
        strength_bonus: u64,
        agility_bonus: u64,
        intelligence_bonus: u64,
        vitality_bonus: u64,
        ctx: &mut TxContext,
    ) {
        let equipment = Equipment {
            id: object::new(ctx),
            name,
            slot,
            strength_bonus,
            agility_bonus,
            intelligence_bonus,
            vitality_bonus,
        };

        transfer::transfer(equipment, ctx.sender());
    }

    /// Equip an item
    public entry fun equip(hero: &mut Hero, item: Equipment) {
        let slot_key = EquipmentSlot { slot: item.slot };

        assert!(!dof::exists_<EquipmentSlot>(&hero.id, slot_key), ESlotOccupied);

        event::emit(ItemEquipped {
            hero_id: object::id(hero),
            item_name: item.name,
            slot: item.slot,
        });

        dof::add(&mut hero.id, slot_key, item);
    }

    /// Unequip an item
    public entry fun unequip(hero: &mut Hero, slot: String, ctx: &mut TxContext) {
        let slot_key = EquipmentSlot { slot };

        assert!(dof::exists_<EquipmentSlot>(&hero.id, slot_key), ENoItemEquipped);

        let item: Equipment = dof::remove(&mut hero.id, slot_key);

        event::emit(ItemUnequipped {
            hero_id: object::id(hero),
            item_name: item.name,
            slot: item.slot,
        });

        transfer::transfer(item, ctx.sender());
    }

    /// Take damage
    public entry fun take_damage(hero: &mut Hero, damage: u64) {
        assert!(hero.alive, EHeroIsDead);

        if (damage >= hero.hp) {
            hero.hp = 0;
            hero.alive = false;
        } else {
            hero.hp = hero.hp - damage;
        }
    }

    /// Heal hero
    public entry fun heal(hero: &mut Hero, amount: u64) {
        assert!(hero.alive, EHeroIsDead);

        hero.hp = if (hero.hp + amount > hero.max_hp) {
            hero.max_hp
        } else {
            hero.hp + amount
        };
    }

    /// Revive hero (costs stat points)
    public entry fun revive(hero: &mut Hero) {
        assert!(!hero.alive, 0);
        assert!(hero.stat_points >= 10, ENotEnoughXP);

        hero.stat_points = hero.stat_points - 10;
        hero.alive = true;
        hero.hp = hero.max_hp / 2;
    }

    // === View Functions ===

    /// Calculate XP needed for next level
    public fun xp_for_next_level(level: u64): u64 {
        level * XP_PER_LEVEL
    }

    /// Get hero stats
    public fun get_stats(hero: &Hero): (u64, u64, u64, u64) {
        (hero.strength, hero.agility, hero.intelligence, hero.vitality)
    }

    /// Get effective stats (base + equipment)
    public fun get_effective_stats(hero: &Hero): (u64, u64, u64, u64) {
        let (str, agi, int, vit) = get_stats(hero);

        // Check each slot for equipment bonuses
        let slots = vector[
            std::string::utf8(b"weapon"),
            std::string::utf8(b"armor"),
            std::string::utf8(b"helmet"),
            std::string::utf8(b"boots"),
        ];

        let mut i = 0;
        while (i < 4) {
            let slot_key = EquipmentSlot { slot: *std::vector::borrow(&slots, i) };
            if (dof::exists_<EquipmentSlot>(&hero.id, slot_key)) {
                let item: &Equipment = dof::borrow(&hero.id, slot_key);
                str = str + item.strength_bonus;
                agi = agi + item.agility_bonus;
                int = int + item.intelligence_bonus;
                vit = vit + item.vitality_bonus;
            };
            i = i + 1;
        };

        (str, agi, int, vit)
    }

    /// Get hero level
    public fun level(hero: &Hero): u64 {
        hero.level
    }

    /// Get hero XP
    public fun xp(hero: &Hero): u64 {
        hero.xp
    }

    /// Get hero HP
    public fun hp(hero: &Hero): (u64, u64) {
        (hero.hp, hero.max_hp)
    }

    /// Is hero alive
    public fun is_alive(hero: &Hero): bool {
        hero.alive
    }

    /// Get stat points
    public fun stat_points(hero: &Hero): u64 {
        hero.stat_points
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use std::string;

    #[test]
    fun test_create_hero() {
        let player = @0x1;
        let mut scenario = test_scenario::begin(player);

        {
            create_hero(
                string::utf8(b"Aragorn"),
                string::utf8(b"Warrior"),
                scenario.ctx(),
            );
        };

        scenario.next_tx(player);
        {
            let hero = scenario.take_from_sender<Hero>();

            assert!(level(&hero) == 1, 0);
            assert!(xp(&hero) == 0, 1);

            let (str, _, _, _) = get_stats(&hero);
            assert!(str == 12, 2); // Warrior has 12 strength

            scenario.return_to_sender(hero);
        };

        scenario.end();
    }

    #[test]
    fun test_gain_xp_and_level() {
        let player = @0x1;
        let mut scenario = test_scenario::begin(player);

        {
            create_hero(
                string::utf8(b"Test Hero"),
                string::utf8(b"Mage"),
                scenario.ctx(),
            );
        };

        scenario.next_tx(player);
        {
            let mut hero = scenario.take_from_sender<Hero>();

            // Gain enough XP to level up
            gain_xp(&mut hero, 100);

            assert!(level(&hero) == 2, 0);
            assert!(stat_points(&hero) == 5, 1);

            scenario.return_to_sender(hero);
        };

        scenario.end();
    }

    #[test]
    fun test_equip_item() {
        let player = @0x1;
        let mut scenario = test_scenario::begin(player);

        // Create hero
        {
            create_hero(
                string::utf8(b"Test Hero"),
                string::utf8(b"Warrior"),
                scenario.ctx(),
            );
        };

        // Create and equip weapon
        scenario.next_tx(player);
        {
            create_equipment(
                string::utf8(b"Iron Sword"),
                string::utf8(b"weapon"),
                5, 0, 0, 0, // +5 strength
                scenario.ctx(),
            );
        };

        scenario.next_tx(player);
        {
            let mut hero = scenario.take_from_sender<Hero>();
            let weapon = scenario.take_from_sender<Equipment>();

            let (str_before, _, _, _) = get_effective_stats(&hero);
            equip(&mut hero, weapon);
            let (str_after, _, _, _) = get_effective_stats(&hero);

            assert!(str_after == str_before + 5, 0);

            scenario.return_to_sender(hero);
        };

        scenario.end();
    }

    #[test]
    fun test_damage_and_heal() {
        let player = @0x1;
        let mut scenario = test_scenario::begin(player);

        {
            create_hero(
                string::utf8(b"Test Hero"),
                string::utf8(b"Warrior"),
                scenario.ctx(),
            );
        };

        scenario.next_tx(player);
        {
            let mut hero = scenario.take_from_sender<Hero>();
            let (initial_hp, max_hp) = hp(&hero);

            take_damage(&mut hero, 50);
            let (current_hp, _) = hp(&hero);
            assert!(current_hp == initial_hp - 50, 0);

            heal(&mut hero, 100);
            let (healed_hp, _) = hp(&hero);
            assert!(healed_hp == max_hp, 1); // Can't exceed max

            scenario.return_to_sender(hero);
        };

        scenario.end();
    }
}
