/// @title Leveling System
/// @notice XP and level progression for games
/// @dev Part of @sui-starters/gaming package
module sui_starters_gaming::leveling {
    use sui::event;

    // === Errors ===

    const EInsufficientXP: u64 = 0;
    const EMaxLevelReached: u64 = 1;
    const EInvalidLevel: u64 = 2;

    // === Constants ===

    const MAX_LEVEL: u64 = 100;
    const BASE_XP: u64 = 100;
    const XP_MULTIPLIER: u64 = 150; // 1.5x per level (scaled by 100)

    // === Structs ===

    /// Level progression state
    public struct LevelState has key, store {
        id: UID,
        owner: address,
        level: u64,
        current_xp: u64,
        total_xp: u64,
    }

    /// Level config
    public struct LevelConfig has key, store {
        id: UID,
        max_level: u64,
        base_xp: u64,
        xp_multiplier: u64,
    }

    // === Events ===

    public struct XPGained has copy, drop {
        state_id: ID,
        amount: u64,
        new_total: u64,
    }

    public struct LevelUp has copy, drop {
        state_id: ID,
        old_level: u64,
        new_level: u64,
    }

    // === Create Functions ===

    /// Create level state for a player
    public fun new(ctx: &mut TxContext): LevelState {
        LevelState {
            id: object::new(ctx),
            owner: ctx.sender(),
            level: 1,
            current_xp: 0,
            total_xp: 0,
        }
    }

    /// Create custom level config
    public fun new_config(
        max_level: u64,
        base_xp: u64,
        xp_multiplier: u64,
        ctx: &mut TxContext,
    ): LevelConfig {
        LevelConfig {
            id: object::new(ctx),
            max_level,
            base_xp,
            xp_multiplier,
        }
    }

    // === Core Functions ===

    /// Add XP and check for level up
    public fun add_xp(state: &mut LevelState, amount: u64) {
        state.current_xp = state.current_xp + amount;
        state.total_xp = state.total_xp + amount;

        event::emit(XPGained {
            state_id: object::id(state),
            amount,
            new_total: state.total_xp,
        });

        // Check for level ups
        while (state.level < MAX_LEVEL) {
            let xp_needed = xp_for_level(state.level);
            if (state.current_xp >= xp_needed) {
                state.current_xp = state.current_xp - xp_needed;
                let old_level = state.level;
                state.level = state.level + 1;

                event::emit(LevelUp {
                    state_id: object::id(state),
                    old_level,
                    new_level: state.level,
                });
            } else {
                break
            }
        };
    }

    /// Add XP with custom config
    public fun add_xp_with_config(
        state: &mut LevelState,
        config: &LevelConfig,
        amount: u64,
    ) {
        state.current_xp = state.current_xp + amount;
        state.total_xp = state.total_xp + amount;

        event::emit(XPGained {
            state_id: object::id(state),
            amount,
            new_total: state.total_xp,
        });

        while (state.level < config.max_level) {
            let xp_needed = xp_for_level_with_config(state.level, config);
            if (state.current_xp >= xp_needed) {
                state.current_xp = state.current_xp - xp_needed;
                let old_level = state.level;
                state.level = state.level + 1;

                event::emit(LevelUp {
                    state_id: object::id(state),
                    old_level,
                    new_level: state.level,
                });
            } else {
                break
            }
        };
    }

    // === Calculation Functions ===

    /// Calculate XP needed for a level
    public fun xp_for_level(level: u64): u64 {
        // XP = BASE_XP * (MULTIPLIER/100)^(level-1)
        // Simplified: BASE_XP * level^1.5 approximation
        let mut xp = BASE_XP;
        let mut i = 1;
        while (i < level) {
            xp = (xp * XP_MULTIPLIER) / 100;
            i = i + 1;
        };
        xp
    }

    /// Calculate XP with custom config
    public fun xp_for_level_with_config(level: u64, config: &LevelConfig): u64 {
        let mut xp = config.base_xp;
        let mut i = 1;
        while (i < level) {
            xp = (xp * config.xp_multiplier) / 100;
            i = i + 1;
        };
        xp
    }

    /// Calculate total XP needed to reach a level
    public fun total_xp_for_level(target_level: u64): u64 {
        let mut total: u64 = 0;
        let mut level = 1;
        while (level < target_level) {
            total = total + xp_for_level(level);
            level = level + 1;
        };
        total
    }

    /// Calculate progress to next level (in basis points)
    public fun level_progress(state: &LevelState): u64 {
        if (state.level >= MAX_LEVEL) {
            return 10000
        };
        let xp_needed = xp_for_level(state.level);
        if (xp_needed == 0) {
            return 0
        };
        (state.current_xp * 10000) / xp_needed
    }

    // === View Functions ===

    /// Get level
    public fun level(state: &LevelState): u64 {
        state.level
    }

    /// Get current XP
    public fun current_xp(state: &LevelState): u64 {
        state.current_xp
    }

    /// Get total XP
    public fun total_xp(state: &LevelState): u64 {
        state.total_xp
    }

    /// Get XP to next level
    public fun xp_to_next_level(state: &LevelState): u64 {
        if (state.level >= MAX_LEVEL) {
            return 0
        };
        let xp_needed = xp_for_level(state.level);
        if (state.current_xp >= xp_needed) {
            0
        } else {
            xp_needed - state.current_xp
        }
    }

    /// Get state info
    public fun state_info(state: &LevelState): (u64, u64, u64) {
        (state.level, state.current_xp, state.total_xp)
    }

    /// Is max level
    public fun is_max_level(state: &LevelState): bool {
        state.level >= MAX_LEVEL
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_level_state() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let state = new(scenario.ctx());
            assert!(level(&state) == 1, 0);
            assert!(current_xp(&state) == 0, 1);
            assert!(total_xp(&state) == 0, 2);

            transfer::public_transfer(state, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_add_xp() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut state = new(scenario.ctx());

            add_xp(&mut state, 50);
            assert!(current_xp(&state) == 50, 0);
            assert!(total_xp(&state) == 50, 1);
            assert!(level(&state) == 1, 2);

            transfer::public_transfer(state, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_level_up() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut state = new(scenario.ctx());

            // Add enough XP to level up
            add_xp(&mut state, 150); // More than BASE_XP (100)
            assert!(level(&state) == 2, 0);

            transfer::public_transfer(state, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_xp_for_level() {
        assert!(xp_for_level(1) == BASE_XP, 0);
        assert!(xp_for_level(2) == (BASE_XP * XP_MULTIPLIER) / 100, 1);
    }

    #[test]
    fun test_level_progress() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut state = new(scenario.ctx());

            // 50% progress
            add_xp(&mut state, 50);
            let progress = level_progress(&state);
            assert!(progress == 5000, 0); // 50%

            transfer::public_transfer(state, admin);
        };

        scenario.end();
    }
}
