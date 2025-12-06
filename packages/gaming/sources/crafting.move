/// @title Crafting System
/// @notice Recipe-based item crafting for games
/// @dev Part of @sui-starters/gaming package
module sui_starters_gaming::crafting {
    use std::string::String;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::vec_map::{Self, VecMap};

    // === Errors ===

    const ERecipeNotFound: u64 = 0;
    const EInsufficientMaterials: u64 = 1;
    const ERecipeDisabled: u64 = 2;
    const ECraftingInProgress: u64 = 3;
    const ECraftingNotReady: u64 = 4;
    const EInvalidRecipe: u64 = 5;

    // === Structs ===

    /// Crafting system manager
    public struct CraftingSystem has key, store {
        id: UID,
        /// Recipe ID -> Recipe
        recipes: Table<u64, Recipe>,
        /// Next recipe ID
        next_recipe_id: u64,
    }

    /// Recipe definition
    public struct Recipe has store {
        id: u64,
        name: String,
        /// Material type -> quantity required
        materials: VecMap<String, u64>,
        /// Result item type
        output_type: String,
        /// Output quantity
        output_amount: u64,
        /// Crafting time in epochs
        craft_time: u64,
        /// Success rate in basis points (10000 = 100%)
        success_rate: u64,
        /// Is recipe enabled
        enabled: bool,
    }

    /// Active crafting session
    public struct CraftingSession has key, store {
        id: UID,
        crafter: address,
        recipe_id: u64,
        /// Epoch when started
        start_epoch: u64,
        /// Epoch when ready
        ready_epoch: u64,
    }

    /// Player's crafting state
    public struct CrafterState has key, store {
        id: UID,
        owner: address,
        /// Material type -> quantity owned
        materials: VecMap<String, u64>,
        /// Active crafting sessions
        active_sessions: vector<ID>,
        /// Total items crafted
        total_crafted: u64,
    }

    // === Events ===

    public struct RecipeCreated has copy, drop {
        recipe_id: u64,
        name: String,
        output_type: String,
    }

    public struct CraftingStarted has copy, drop {
        session_id: ID,
        crafter: address,
        recipe_id: u64,
        ready_epoch: u64,
    }

    public struct CraftingCompleted has copy, drop {
        session_id: ID,
        crafter: address,
        recipe_id: u64,
        success: bool,
        output_type: String,
        output_amount: u64,
    }

    public struct MaterialDeposited has copy, drop {
        crafter: address,
        material_type: String,
        amount: u64,
    }

    // === Create Functions ===

    /// Create new crafting system
    public fun new_system(ctx: &mut TxContext): CraftingSystem {
        CraftingSystem {
            id: object::new(ctx),
            recipes: table::new(ctx),
            next_recipe_id: 0,
        }
    }

    /// Create new crafter state
    public fun new_crafter(ctx: &mut TxContext): CrafterState {
        CrafterState {
            id: object::new(ctx),
            owner: ctx.sender(),
            materials: vec_map::empty(),
            active_sessions: vector::empty(),
            total_crafted: 0,
        }
    }

    // === Admin Functions ===

    /// Add new recipe
    public fun add_recipe(
        system: &mut CraftingSystem,
        name: String,
        materials: VecMap<String, u64>,
        output_type: String,
        output_amount: u64,
        craft_time: u64,
        success_rate: u64,
    ): u64 {
        assert!(success_rate <= 10000, EInvalidRecipe);
        assert!(output_amount > 0, EInvalidRecipe);

        let recipe_id = system.next_recipe_id;
        system.next_recipe_id = recipe_id + 1;

        let recipe = Recipe {
            id: recipe_id,
            name,
            materials,
            output_type,
            output_amount,
            craft_time,
            success_rate,
            enabled: true,
        };

        event::emit(RecipeCreated {
            recipe_id,
            name: recipe.name,
            output_type: recipe.output_type,
        });

        table::add(&mut system.recipes, recipe_id, recipe);
        recipe_id
    }

    /// Enable/disable recipe
    public fun set_recipe_enabled(
        system: &mut CraftingSystem,
        recipe_id: u64,
        enabled: bool,
    ) {
        assert!(table::contains(&system.recipes, recipe_id), ERecipeNotFound);
        let recipe = table::borrow_mut(&mut system.recipes, recipe_id);
        recipe.enabled = enabled;
    }

    // === Core Functions ===

    /// Deposit materials
    public fun deposit_material(
        state: &mut CrafterState,
        material_type: String,
        amount: u64,
    ) {
        if (vec_map::contains(&state.materials, &material_type)) {
            let current = vec_map::get_mut(&mut state.materials, &material_type);
            *current = *current + amount;
        } else {
            vec_map::insert(&mut state.materials, material_type, amount);
        };

        event::emit(MaterialDeposited {
            crafter: state.owner,
            material_type,
            amount,
        });
    }

    /// Start crafting
    public fun start_crafting(
        system: &CraftingSystem,
        state: &mut CrafterState,
        recipe_id: u64,
        ctx: &mut TxContext,
    ): CraftingSession {
        assert!(table::contains(&system.recipes, recipe_id), ERecipeNotFound);
        let recipe = table::borrow(&system.recipes, recipe_id);
        assert!(recipe.enabled, ERecipeDisabled);

        // Check and consume materials
        let mut i = 0;
        let len = vec_map::length(&recipe.materials);
        while (i < len) {
            let (material_type, required) = vec_map::get_entry_by_idx(&recipe.materials, i);
            assert!(
                vec_map::contains(&state.materials, material_type),
                EInsufficientMaterials,
            );
            let available = vec_map::get_mut(&mut state.materials, material_type);
            assert!(*available >= *required, EInsufficientMaterials);
            *available = *available - *required;
            i = i + 1;
        };

        let current_epoch = ctx.epoch();
        let ready_epoch = current_epoch + recipe.craft_time;

        let session = CraftingSession {
            id: object::new(ctx),
            crafter: ctx.sender(),
            recipe_id,
            start_epoch: current_epoch,
            ready_epoch,
        };

        let session_id = object::id(&session);
        vector::push_back(&mut state.active_sessions, session_id);

        event::emit(CraftingStarted {
            session_id,
            crafter: ctx.sender(),
            recipe_id,
            ready_epoch,
        });

        session
    }

    /// Complete crafting (returns success status and output info)
    public fun complete_crafting(
        system: &CraftingSystem,
        state: &mut CrafterState,
        session: CraftingSession,
        random_value: u64,
        ctx: &TxContext,
    ): (bool, String, u64) {
        let CraftingSession { id, crafter: _, recipe_id, start_epoch: _, ready_epoch } = session;
        assert!(ctx.epoch() >= ready_epoch, ECraftingNotReady);

        let recipe = table::borrow(&system.recipes, recipe_id);

        // Calculate success using random value
        let success = (random_value % 10000) < recipe.success_rate;

        let output_amount = if (success) { recipe.output_amount } else { 0 };

        // Remove from active sessions
        let session_id = object::uid_to_inner(&id);
        let (found, idx) = vector::index_of(&state.active_sessions, &session_id);
        if (found) {
            vector::remove(&mut state.active_sessions, idx);
        };

        if (success) {
            state.total_crafted = state.total_crafted + 1;
        };

        event::emit(CraftingCompleted {
            session_id,
            crafter: state.owner,
            recipe_id,
            success,
            output_type: recipe.output_type,
            output_amount,
        });

        object::delete(id);

        (success, recipe.output_type, output_amount)
    }

    // === View Functions ===

    /// Get material balance
    public fun material_balance(state: &CrafterState, material_type: &String): u64 {
        if (vec_map::contains(&state.materials, material_type)) {
            *vec_map::get(&state.materials, material_type)
        } else {
            0
        }
    }

    /// Check if can craft recipe
    public fun can_craft(
        system: &CraftingSystem,
        state: &CrafterState,
        recipe_id: u64,
    ): bool {
        if (!table::contains(&system.recipes, recipe_id)) {
            return false
        };

        let recipe = table::borrow(&system.recipes, recipe_id);
        if (!recipe.enabled) {
            return false
        };

        let mut i = 0;
        let len = vec_map::length(&recipe.materials);
        while (i < len) {
            let (material_type, required) = vec_map::get_entry_by_idx(&recipe.materials, i);
            if (!vec_map::contains(&state.materials, material_type)) {
                return false
            };
            let available = vec_map::get(&state.materials, material_type);
            if (*available < *required) {
                return false
            };
            i = i + 1;
        };

        true
    }

    /// Get recipe info
    public fun recipe_info(system: &CraftingSystem, recipe_id: u64): (String, String, u64, u64, u64, bool) {
        let recipe = table::borrow(&system.recipes, recipe_id);
        (
            recipe.name,
            recipe.output_type,
            recipe.output_amount,
            recipe.craft_time,
            recipe.success_rate,
            recipe.enabled,
        )
    }

    /// Get active session count
    public fun active_sessions(state: &CrafterState): u64 {
        vector::length(&state.active_sessions)
    }

    /// Get total crafted count
    public fun total_crafted(state: &CrafterState): u64 {
        state.total_crafted
    }

    /// Check if crafting is ready
    public fun is_ready(session: &CraftingSession, current_epoch: u64): bool {
        current_epoch >= session.ready_epoch
    }

    /// Get time remaining
    public fun time_remaining(session: &CraftingSession, current_epoch: u64): u64 {
        if (current_epoch >= session.ready_epoch) {
            0
        } else {
            session.ready_epoch - current_epoch
        }
    }

    // === Tests ===

    #[test_only]
    use std::string;
    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_system() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let system = new_system(scenario.ctx());
            assert!(system.next_recipe_id == 0, 0);
            transfer::public_share_object(system);
        };

        scenario.end();
    }

    #[test]
    fun test_add_recipe() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut system = new_system(scenario.ctx());

            let mut materials = vec_map::empty();
            vec_map::insert(&mut materials, string::utf8(b"wood"), 10u64);
            vec_map::insert(&mut materials, string::utf8(b"iron"), 5u64);

            let recipe_id = add_recipe(
                &mut system,
                string::utf8(b"Iron Sword"),
                materials,
                string::utf8(b"weapon_sword"),
                1,
                2,
                8000,
            );

            assert!(recipe_id == 0, 0);
            assert!(system.next_recipe_id == 1, 1);

            transfer::public_share_object(system);
        };

        scenario.end();
    }

    #[test]
    fun test_deposit_material() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut state = new_crafter(scenario.ctx());

            let wood = string::utf8(b"wood");
            deposit_material(&mut state, wood, 100);
            assert!(material_balance(&state, &wood) == 100, 0);

            deposit_material(&mut state, wood, 50);
            assert!(material_balance(&state, &wood) == 150, 1);

            transfer::public_transfer(state, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_can_craft() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut system = new_system(scenario.ctx());
            let mut state = new_crafter(scenario.ctx());

            let wood = string::utf8(b"wood");
            let mut materials = vec_map::empty();
            vec_map::insert(&mut materials, wood, 10u64);

            let recipe_id = add_recipe(
                &mut system,
                string::utf8(b"Wooden Shield"),
                materials,
                string::utf8(b"armor_shield"),
                1,
                1,
                10000,
            );

            assert!(!can_craft(&system, &state, recipe_id), 0);

            deposit_material(&mut state, wood, 5);
            assert!(!can_craft(&system, &state, recipe_id), 1);

            deposit_material(&mut state, wood, 5);
            assert!(can_craft(&system, &state, recipe_id), 2);

            transfer::public_share_object(system);
            transfer::public_transfer(state, admin);
        };

        scenario.end();
    }
}
