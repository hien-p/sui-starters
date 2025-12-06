/// @title Leaderboard
/// @notice On-chain leaderboard with top scores
/// @dev Demonstrates sorted data structures and score management
module leaderboard::leaderboard {
    use std::string::String;
    use sui::event;
    use sui::table::{Self, Table};

    // === Errors ===

    const ELeaderboardFull: u64 = 0;
    const EScoreTooLow: u64 = 1;
    const ENotAdmin: u64 = 2;

    // === Structs ===

    /// Leaderboard entry
    public struct Entry has store, copy, drop {
        player: address,
        name: String,
        score: u64,
        timestamp: u64,
    }

    /// Leaderboard
    public struct Leaderboard has key {
        id: UID,
        /// Game name
        game_name: String,
        /// Max entries to keep
        max_entries: u64,
        /// Current entries (sorted by score desc)
        entries: vector<Entry>,
        /// All-time player scores
        player_scores: Table<address, u64>,
        /// Admin address
        admin: address,
    }

    // === Events ===

    public struct LeaderboardCreated has copy, drop {
        leaderboard_id: ID,
        game_name: String,
        max_entries: u64,
    }

    public struct ScoreSubmitted has copy, drop {
        leaderboard_id: ID,
        player: address,
        score: u64,
        rank: u64,
    }

    public struct ScoreImproved has copy, drop {
        leaderboard_id: ID,
        player: address,
        old_score: u64,
        new_score: u64,
        new_rank: u64,
    }

    // === Entry Functions ===

    /// Create a new leaderboard
    public entry fun create(
        game_name: String,
        max_entries: u64,
        ctx: &mut TxContext,
    ) {
        let leaderboard = Leaderboard {
            id: object::new(ctx),
            game_name,
            max_entries,
            entries: vector::empty(),
            player_scores: table::new(ctx),
            admin: ctx.sender(),
        };

        event::emit(LeaderboardCreated {
            leaderboard_id: object::id(&leaderboard),
            game_name: leaderboard.game_name,
            max_entries,
        });

        transfer::share_object(leaderboard);
    }

    /// Submit a score
    public entry fun submit_score(
        leaderboard: &mut Leaderboard,
        name: String,
        score: u64,
        ctx: &mut TxContext,
    ) {
        let player = ctx.sender();
        let timestamp = ctx.epoch();

        // Check if player already has a score
        let existing_score = if (table::contains(&leaderboard.player_scores, player)) {
            *table::borrow(&leaderboard.player_scores, player)
        } else {
            0
        };

        // Only update if new score is better
        if (score <= existing_score) {
            return
        };

        // Update player's best score
        if (table::contains(&leaderboard.player_scores, player)) {
            *table::borrow_mut(&mut leaderboard.player_scores, player) = score;
        } else {
            table::add(&mut leaderboard.player_scores, player, score);
        };

        // Remove old entry if exists
        let mut i = 0;
        let len = vector::length(&leaderboard.entries);
        while (i < len) {
            let entry = vector::borrow(&leaderboard.entries, i);
            if (entry.player == player) {
                vector::remove(&mut leaderboard.entries, i);
                break
            };
            i = i + 1;
        };

        // Create new entry
        let new_entry = Entry {
            player,
            name,
            score,
            timestamp,
        };

        // Find insert position (sorted desc)
        let mut insert_pos = 0;
        let len = vector::length(&leaderboard.entries);
        while (insert_pos < len) {
            let entry = vector::borrow(&leaderboard.entries, insert_pos);
            if (score > entry.score) {
                break
            };
            insert_pos = insert_pos + 1;
        };

        // Insert if within max entries
        if (insert_pos < leaderboard.max_entries) {
            vector::insert(&mut leaderboard.entries, new_entry, insert_pos);

            // Trim if over max
            while (vector::length(&leaderboard.entries) > leaderboard.max_entries) {
                vector::pop_back(&mut leaderboard.entries);
            };

            if (existing_score > 0) {
                event::emit(ScoreImproved {
                    leaderboard_id: object::id(leaderboard),
                    player,
                    old_score: existing_score,
                    new_score: score,
                    new_rank: insert_pos + 1,
                });
            } else {
                event::emit(ScoreSubmitted {
                    leaderboard_id: object::id(leaderboard),
                    player,
                    score,
                    rank: insert_pos + 1,
                });
            };
        };
    }

    /// Clear leaderboard (admin only)
    public entry fun clear(
        leaderboard: &mut Leaderboard,
        ctx: &TxContext,
    ) {
        assert!(leaderboard.admin == ctx.sender(), ENotAdmin);
        leaderboard.entries = vector::empty();
    }

    /// Update max entries (admin only)
    public entry fun set_max_entries(
        leaderboard: &mut Leaderboard,
        max_entries: u64,
        ctx: &TxContext,
    ) {
        assert!(leaderboard.admin == ctx.sender(), ENotAdmin);
        leaderboard.max_entries = max_entries;

        // Trim if needed
        while (vector::length(&leaderboard.entries) > max_entries) {
            vector::pop_back(&mut leaderboard.entries);
        };
    }

    // === View Functions ===

    /// Get top N entries
    public fun top_entries(leaderboard: &Leaderboard, n: u64): vector<Entry> {
        let len = vector::length(&leaderboard.entries);
        let count = if (n < len) n else len;

        let mut result = vector::empty();
        let mut i = 0;
        while (i < count) {
            vector::push_back(&mut result, *vector::borrow(&leaderboard.entries, i));
            i = i + 1;
        };

        result
    }

    /// Get player's rank (0 if not on leaderboard)
    public fun player_rank(leaderboard: &Leaderboard, player: address): u64 {
        let mut i = 0;
        let len = vector::length(&leaderboard.entries);
        while (i < len) {
            let entry = vector::borrow(&leaderboard.entries, i);
            if (entry.player == player) {
                return i + 1
            };
            i = i + 1;
        };
        0
    }

    /// Get player's best score
    public fun player_score(leaderboard: &Leaderboard, player: address): u64 {
        if (table::contains(&leaderboard.player_scores, player)) {
            *table::borrow(&leaderboard.player_scores, player)
        } else {
            0
        }
    }

    /// Get entry at rank
    public fun entry_at_rank(leaderboard: &Leaderboard, rank: u64): (address, String, u64) {
        let entry = vector::borrow(&leaderboard.entries, rank - 1);
        (entry.player, entry.name, entry.score)
    }

    /// Get leaderboard size
    public fun size(leaderboard: &Leaderboard): u64 {
        vector::length(&leaderboard.entries)
    }

    /// Get minimum score to be on leaderboard
    public fun min_score(leaderboard: &Leaderboard): u64 {
        let len = vector::length(&leaderboard.entries);
        if (len < leaderboard.max_entries) {
            0
        } else if (len > 0) {
            let last = vector::borrow(&leaderboard.entries, len - 1);
            last.score
        } else {
            0
        }
    }

    /// Get game name
    public fun game_name(leaderboard: &Leaderboard): String {
        leaderboard.game_name
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use std::string;

    #[test]
    fun test_create_leaderboard() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            create(
                string::utf8(b"Space Game"),
                10,
                scenario.ctx(),
            );
        };

        scenario.next_tx(admin);
        {
            let leaderboard = scenario.take_shared<Leaderboard>();
            assert!(size(&leaderboard) == 0, 0);
            assert!(game_name(&leaderboard) == string::utf8(b"Space Game"), 1);
            test_scenario::return_shared(leaderboard);
        };

        scenario.end();
    }

    #[test]
    fun test_submit_score() {
        let admin = @0x1;
        let player1 = @0x2;
        let player2 = @0x3;
        let mut scenario = test_scenario::begin(admin);

        {
            create(string::utf8(b"Game"), 10, scenario.ctx());
        };

        // Player 1 submits
        scenario.next_tx(player1);
        {
            let mut leaderboard = scenario.take_shared<Leaderboard>();
            submit_score(&mut leaderboard, string::utf8(b"Alice"), 100, scenario.ctx());
            assert!(size(&leaderboard) == 1, 0);
            assert!(player_rank(&leaderboard, player1) == 1, 1);
            test_scenario::return_shared(leaderboard);
        };

        // Player 2 submits higher score
        scenario.next_tx(player2);
        {
            let mut leaderboard = scenario.take_shared<Leaderboard>();
            submit_score(&mut leaderboard, string::utf8(b"Bob"), 200, scenario.ctx());
            assert!(size(&leaderboard) == 2, 2);
            assert!(player_rank(&leaderboard, player2) == 1, 3); // Bob is #1
            assert!(player_rank(&leaderboard, player1) == 2, 4); // Alice is #2
            test_scenario::return_shared(leaderboard);
        };

        scenario.end();
    }

    #[test]
    fun test_score_improvement() {
        let admin = @0x1;
        let player = @0x2;
        let mut scenario = test_scenario::begin(admin);

        {
            create(string::utf8(b"Game"), 10, scenario.ctx());
        };

        // Submit initial score
        scenario.next_tx(player);
        {
            let mut leaderboard = scenario.take_shared<Leaderboard>();
            submit_score(&mut leaderboard, string::utf8(b"Player"), 100, scenario.ctx());
            assert!(player_score(&leaderboard, player) == 100, 0);
            test_scenario::return_shared(leaderboard);
        };

        // Improve score
        scenario.next_tx(player);
        {
            let mut leaderboard = scenario.take_shared<Leaderboard>();
            submit_score(&mut leaderboard, string::utf8(b"Player"), 200, scenario.ctx());
            assert!(player_score(&leaderboard, player) == 200, 1);
            assert!(size(&leaderboard) == 1, 2); // Still only 1 entry
            test_scenario::return_shared(leaderboard);
        };

        scenario.end();
    }
}
