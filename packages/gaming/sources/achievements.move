/// @title Achievements System
/// @notice Track and unlock player achievements
/// @dev Part of @sui-starters/gaming package
module sui_starters_gaming::achievements {
    use std::string::String;
    use sui::event;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};

    // === Errors ===

    const EAchievementNotFound: u64 = 0;
    const EAlreadyUnlocked: u64 = 1;
    const ERequirementsNotMet: u64 = 2;
    const EInvalidThreshold: u64 = 3;

    // === Constants ===

    /// Achievement types
    const TYPE_COUNTER: u8 = 0;     // Reach X count
    const TYPE_MILESTONE: u8 = 1;   // One-time unlock
    const TYPE_TIERED: u8 = 2;      // Multiple tiers

    // === Structs ===

    /// Achievement definition
    public struct Achievement has store, copy, drop {
        id: u64,
        name: String,
        description: String,
        /// Achievement type
        achievement_type: u8,
        /// Required value to unlock
        threshold: u64,
        /// Points awarded
        points: u64,
        /// Is achievement hidden until unlocked
        hidden: bool,
    }

    /// Achievement system manager
    public struct AchievementSystem has key, store {
        id: UID,
        /// Achievement ID -> Achievement
        achievements: Table<u64, Achievement>,
        /// Next achievement ID
        next_id: u64,
        /// Total possible points
        total_points: u64,
    }

    /// Player's achievement progress
    public struct PlayerAchievements has key, store {
        id: UID,
        player: address,
        /// Unlocked achievement IDs
        unlocked: VecSet<u64>,
        /// Achievement ID -> current progress
        progress: Table<u64, u64>,
        /// Total points earned
        total_points: u64,
        /// Unlock timestamps
        unlock_times: Table<u64, u64>,
    }

    // === Events ===

    public struct AchievementCreated has copy, drop {
        achievement_id: u64,
        name: String,
        points: u64,
    }

    public struct AchievementUnlocked has copy, drop {
        player: address,
        achievement_id: u64,
        name: String,
        points: u64,
    }

    public struct ProgressUpdated has copy, drop {
        player: address,
        achievement_id: u64,
        progress: u64,
        threshold: u64,
    }

    // === Create Functions ===

    /// Create new achievement system
    public fun new_system(ctx: &mut TxContext): AchievementSystem {
        AchievementSystem {
            id: object::new(ctx),
            achievements: table::new(ctx),
            next_id: 0,
            total_points: 0,
        }
    }

    /// Create player achievements tracker
    public fun new_player_achievements(ctx: &mut TxContext): PlayerAchievements {
        PlayerAchievements {
            id: object::new(ctx),
            player: ctx.sender(),
            unlocked: vec_set::empty(),
            progress: table::new(ctx),
            total_points: 0,
            unlock_times: table::new(ctx),
        }
    }

    // === Admin Functions ===

    /// Add new achievement
    public fun add_achievement(
        system: &mut AchievementSystem,
        name: String,
        description: String,
        achievement_type: u8,
        threshold: u64,
        points: u64,
        hidden: bool,
    ): u64 {
        assert!(threshold > 0, EInvalidThreshold);

        let achievement_id = system.next_id;
        system.next_id = achievement_id + 1;

        let achievement = Achievement {
            id: achievement_id,
            name,
            description,
            achievement_type,
            threshold,
            points,
            hidden,
        };

        system.total_points = system.total_points + points;

        event::emit(AchievementCreated {
            achievement_id,
            name: achievement.name,
            points,
        });

        table::add(&mut system.achievements, achievement_id, achievement);
        achievement_id
    }

    // === Core Functions ===

    /// Update progress for a counter achievement
    public fun update_progress(
        system: &AchievementSystem,
        player_achievements: &mut PlayerAchievements,
        achievement_id: u64,
        amount: u64,
        current_epoch: u64,
    ) {
        assert!(table::contains(&system.achievements, achievement_id), EAchievementNotFound);

        // Skip if already unlocked
        if (vec_set::contains(&player_achievements.unlocked, &achievement_id)) {
            return
        };

        let achievement = table::borrow(&system.achievements, achievement_id);

        // Update progress
        let current_progress = if (table::contains(&player_achievements.progress, achievement_id)) {
            *table::borrow(&player_achievements.progress, achievement_id)
        } else {
            0
        };

        let new_progress = current_progress + amount;

        if (table::contains(&player_achievements.progress, achievement_id)) {
            *table::borrow_mut(&mut player_achievements.progress, achievement_id) = new_progress;
        } else {
            table::add(&mut player_achievements.progress, achievement_id, new_progress);
        };

        event::emit(ProgressUpdated {
            player: player_achievements.player,
            achievement_id,
            progress: new_progress,
            threshold: achievement.threshold,
        });

        // Check if threshold reached
        if (new_progress >= achievement.threshold) {
            unlock_achievement_internal(player_achievements, achievement, current_epoch);
        };
    }

    /// Directly unlock a milestone achievement
    public fun unlock_milestone(
        system: &AchievementSystem,
        player_achievements: &mut PlayerAchievements,
        achievement_id: u64,
        current_epoch: u64,
    ) {
        assert!(table::contains(&system.achievements, achievement_id), EAchievementNotFound);
        assert!(
            !vec_set::contains(&player_achievements.unlocked, &achievement_id),
            EAlreadyUnlocked,
        );

        let achievement = table::borrow(&system.achievements, achievement_id);
        unlock_achievement_internal(player_achievements, achievement, current_epoch);
    }

    /// Internal unlock logic
    fun unlock_achievement_internal(
        player_achievements: &mut PlayerAchievements,
        achievement: &Achievement,
        current_epoch: u64,
    ) {
        vec_set::insert(&mut player_achievements.unlocked, achievement.id);
        player_achievements.total_points = player_achievements.total_points + achievement.points;
        table::add(&mut player_achievements.unlock_times, achievement.id, current_epoch);

        event::emit(AchievementUnlocked {
            player: player_achievements.player,
            achievement_id: achievement.id,
            name: achievement.name,
            points: achievement.points,
        });
    }

    /// Set progress to specific value
    public fun set_progress(
        system: &AchievementSystem,
        player_achievements: &mut PlayerAchievements,
        achievement_id: u64,
        value: u64,
        current_epoch: u64,
    ) {
        assert!(table::contains(&system.achievements, achievement_id), EAchievementNotFound);

        if (vec_set::contains(&player_achievements.unlocked, &achievement_id)) {
            return
        };

        let achievement = table::borrow(&system.achievements, achievement_id);

        if (table::contains(&player_achievements.progress, achievement_id)) {
            *table::borrow_mut(&mut player_achievements.progress, achievement_id) = value;
        } else {
            table::add(&mut player_achievements.progress, achievement_id, value);
        };

        if (value >= achievement.threshold) {
            unlock_achievement_internal(player_achievements, achievement, current_epoch);
        };
    }

    // === View Functions ===

    /// Check if achievement is unlocked
    public fun is_unlocked(
        player_achievements: &PlayerAchievements,
        achievement_id: u64,
    ): bool {
        vec_set::contains(&player_achievements.unlocked, &achievement_id)
    }

    /// Get current progress
    public fun get_progress(
        player_achievements: &PlayerAchievements,
        achievement_id: u64,
    ): u64 {
        if (table::contains(&player_achievements.progress, achievement_id)) {
            *table::borrow(&player_achievements.progress, achievement_id)
        } else {
            0
        }
    }

    /// Get player total points
    public fun player_points(player_achievements: &PlayerAchievements): u64 {
        player_achievements.total_points
    }

    /// Get unlocked count
    public fun unlocked_count(player_achievements: &PlayerAchievements): u64 {
        vec_set::length(&player_achievements.unlocked)
    }

    /// Get total achievements
    public fun total_achievements(system: &AchievementSystem): u64 {
        system.next_id
    }

    /// Get total possible points
    public fun total_possible_points(system: &AchievementSystem): u64 {
        system.total_points
    }

    /// Get achievement info
    public fun achievement_info(
        system: &AchievementSystem,
        achievement_id: u64,
    ): (String, String, u8, u64, u64, bool) {
        let achievement = table::borrow(&system.achievements, achievement_id);
        (
            achievement.name,
            achievement.description,
            achievement.achievement_type,
            achievement.threshold,
            achievement.points,
            achievement.hidden,
        )
    }

    /// Calculate completion percentage (in basis points)
    public fun completion_percentage(
        system: &AchievementSystem,
        player_achievements: &PlayerAchievements,
    ): u64 {
        if (system.next_id == 0) {
            return 0
        };
        (unlocked_count(player_achievements) * 10000) / system.next_id
    }

    /// Type constants
    public fun type_counter(): u8 { TYPE_COUNTER }
    public fun type_milestone(): u8 { TYPE_MILESTONE }
    public fun type_tiered(): u8 { TYPE_TIERED }

    // === Tests ===

    #[test_only]
    use std::string;

    #[test]
    fun test_create_system() {
        let ctx = &mut tx_context::dummy();
        let system = new_system(ctx);

        assert!(total_achievements(&system) == 0, 0);
        assert!(total_possible_points(&system) == 0, 1);

        let AchievementSystem { id, achievements, next_id: _, total_points: _ } = system;
        table::destroy_empty(achievements);
        object::delete(id);
    }

    #[test]
    fun test_add_achievement() {
        let ctx = &mut tx_context::dummy();
        let mut system = new_system(ctx);

        let achievement_id = add_achievement(
            &mut system,
            string::utf8(b"First Steps"),
            string::utf8(b"Complete the tutorial"),
            TYPE_MILESTONE,
            1,
            10,
            false,
        );

        assert!(achievement_id == 0, 0);
        assert!(total_achievements(&system) == 1, 1);
        assert!(total_possible_points(&system) == 10, 2);

        let AchievementSystem { id, achievements, next_id: _, total_points: _ } = system;
        table::drop(achievements);
        object::delete(id);
    }

    #[test]
    fun test_unlock_milestone() {
        let ctx = &mut tx_context::dummy();
        let mut system = new_system(ctx);
        let mut player = new_player_achievements(ctx);

        let achievement_id = add_achievement(
            &mut system,
            string::utf8(b"First Kill"),
            string::utf8(b"Defeat an enemy"),
            TYPE_MILESTONE,
            1,
            25,
            false,
        );

        assert!(!is_unlocked(&player, achievement_id), 0);

        unlock_milestone(&system, &mut player, achievement_id, 100);

        assert!(is_unlocked(&player, achievement_id), 1);
        assert!(player_points(&player) == 25, 2);
        assert!(unlocked_count(&player) == 1, 3);

        let AchievementSystem { id: sys_id, achievements, next_id: _, total_points: _ } = system;
        table::drop(achievements);
        object::delete(sys_id);

        let PlayerAchievements {
            id,
            player: _,
            unlocked: _,
            progress,
            total_points: _,
            unlock_times,
        } = player;
        table::drop(progress);
        table::drop(unlock_times);
        object::delete(id);
    }

    #[test]
    fun test_update_progress() {
        let ctx = &mut tx_context::dummy();
        let mut system = new_system(ctx);
        let mut player = new_player_achievements(ctx);

        let achievement_id = add_achievement(
            &mut system,
            string::utf8(b"Monster Hunter"),
            string::utf8(b"Defeat 100 monsters"),
            TYPE_COUNTER,
            100,
            50,
            false,
        );

        update_progress(&system, &mut player, achievement_id, 50, 100);
        assert!(get_progress(&player, achievement_id) == 50, 0);
        assert!(!is_unlocked(&player, achievement_id), 1);

        update_progress(&system, &mut player, achievement_id, 50, 101);
        assert!(is_unlocked(&player, achievement_id), 2);
        assert!(player_points(&player) == 50, 3);

        let AchievementSystem { id: sys_id, achievements, next_id: _, total_points: _ } = system;
        table::drop(achievements);
        object::delete(sys_id);

        let PlayerAchievements {
            id,
            player: _,
            unlocked: _,
            progress,
            total_points: _,
            unlock_times,
        } = player;
        table::drop(progress);
        table::drop(unlock_times);
        object::delete(id);
    }

    #[test]
    fun test_completion_percentage() {
        let ctx = &mut tx_context::dummy();
        let mut system = new_system(ctx);
        let mut player = new_player_achievements(ctx);

        add_achievement(&mut system, string::utf8(b"A1"), string::utf8(b"D1"), TYPE_MILESTONE, 1, 10, false);
        add_achievement(&mut system, string::utf8(b"A2"), string::utf8(b"D2"), TYPE_MILESTONE, 1, 10, false);
        add_achievement(&mut system, string::utf8(b"A3"), string::utf8(b"D3"), TYPE_MILESTONE, 1, 10, false);
        add_achievement(&mut system, string::utf8(b"A4"), string::utf8(b"D4"), TYPE_MILESTONE, 1, 10, false);

        assert!(completion_percentage(&system, &player) == 0, 0);

        unlock_milestone(&system, &mut player, 0, 100);
        assert!(completion_percentage(&system, &player) == 2500, 1); // 25%

        unlock_milestone(&system, &mut player, 1, 101);
        assert!(completion_percentage(&system, &player) == 5000, 2); // 50%

        let AchievementSystem { id: sys_id, achievements, next_id: _, total_points: _ } = system;
        table::drop(achievements);
        object::delete(sys_id);

        let PlayerAchievements {
            id,
            player: _,
            unlocked: _,
            progress,
            total_points: _,
            unlock_times,
        } = player;
        table::drop(progress);
        table::drop(unlock_times);
        object::delete(id);
    }
}
