/// @title Leaderboard
/// @notice On-chain ranking system for games
/// @dev Part of @sui-starters/gaming package
module sui_starters_gaming::leaderboard {
    use std::string::String;
    use sui::event;
    use sui::table::{Self, Table};

    // === Errors ===

    const ELeaderboardFull: u64 = 0;
    const EPlayerNotFound: u64 = 1;
    const EInvalidScore: u64 = 2;

    // === Structs ===

    /// Leaderboard for a game
    public struct Leaderboard has key, store {
        id: UID,
        name: String,
        max_entries: u64,
        /// Player scores
        scores: Table<address, u64>,
        /// Top players (sorted)
        top_players: vector<address>,
        /// Lowest score in top list
        min_top_score: u64,
    }

    /// Player entry
    public struct LeaderboardEntry has copy, drop, store {
        player: address,
        score: u64,
        rank: u64,
    }

    // === Events ===

    public struct ScoreSubmitted has copy, drop {
        leaderboard_id: ID,
        player: address,
        score: u64,
        rank: u64,
    }

    public struct NewHighScore has copy, drop {
        leaderboard_id: ID,
        player: address,
        old_score: u64,
        new_score: u64,
    }

    // === Create Functions ===

    /// Create new leaderboard
    public fun new(
        name: String,
        max_entries: u64,
        ctx: &mut TxContext,
    ): Leaderboard {
        Leaderboard {
            id: object::new(ctx),
            name,
            max_entries,
            scores: table::new(ctx),
            top_players: vector::empty(),
            min_top_score: 0,
        }
    }

    // === Core Functions ===

    /// Submit score
    public fun submit_score(
        leaderboard: &mut Leaderboard,
        player: address,
        score: u64,
    ) {
        // Get old score if exists
        let old_score = if (table::contains(&leaderboard.scores, player)) {
            *table::borrow(&leaderboard.scores, player)
        } else {
            0
        };

        // Only update if new score is higher
        if (score <= old_score) {
            return
        };

        // Update score
        if (table::contains(&leaderboard.scores, player)) {
            *table::borrow_mut(&mut leaderboard.scores, player) = score;
        } else {
            table::add(&mut leaderboard.scores, player, score);
        };

        // Emit high score event
        if (old_score > 0) {
            event::emit(NewHighScore {
                leaderboard_id: object::id(leaderboard),
                player,
                old_score,
                new_score: score,
            });
        };

        // Update top players list
        update_top_players(leaderboard, player, score);
    }

    /// Update top players list
    fun update_top_players(
        leaderboard: &mut Leaderboard,
        player: address,
        score: u64,
    ) {
        let len = vector::length(&leaderboard.top_players);

        // Remove player if already in list
        let mut i = 0;
        while (i < len) {
            if (*vector::borrow(&leaderboard.top_players, i) == player) {
                vector::remove(&mut leaderboard.top_players, i);
                break
            };
            i = i + 1;
        };

        // Find insertion position (sorted descending)
        let new_len = vector::length(&leaderboard.top_players);
        let mut insert_pos = new_len;
        i = 0;
        while (i < new_len) {
            let top_player = *vector::borrow(&leaderboard.top_players, i);
            let top_score = *table::borrow(&leaderboard.scores, top_player);
            if (score > top_score) {
                insert_pos = i;
                break
            };
            i = i + 1;
        };

        // Insert if within max_entries or score qualifies
        if (insert_pos < leaderboard.max_entries) {
            vector::insert(&mut leaderboard.top_players, player, insert_pos);

            // Trim if over max
            while (vector::length(&leaderboard.top_players) > leaderboard.max_entries) {
                vector::pop_back(&mut leaderboard.top_players);
            };

            // Update min score
            if (vector::length(&leaderboard.top_players) > 0) {
                let last = *vector::borrow(
                    &leaderboard.top_players,
                    vector::length(&leaderboard.top_players) - 1,
                );
                leaderboard.min_top_score = *table::borrow(&leaderboard.scores, last);
            };
        };

        // Calculate rank for event
        let rank = insert_pos + 1;
        event::emit(ScoreSubmitted {
            leaderboard_id: object::id(leaderboard),
            player,
            score,
            rank,
        });
    }

    /// Get player rank (0 if not ranked)
    public fun get_rank(leaderboard: &Leaderboard, player: address): u64 {
        let len = vector::length(&leaderboard.top_players);
        let mut i = 0;
        while (i < len) {
            if (*vector::borrow(&leaderboard.top_players, i) == player) {
                return i + 1
            };
            i = i + 1;
        };
        0
    }

    /// Get player score
    public fun get_score(leaderboard: &Leaderboard, player: address): u64 {
        if (table::contains(&leaderboard.scores, player)) {
            *table::borrow(&leaderboard.scores, player)
        } else {
            0
        }
    }

    /// Get top N players
    public fun get_top(leaderboard: &Leaderboard, count: u64): vector<LeaderboardEntry> {
        let mut entries = vector::empty<LeaderboardEntry>();
        let len = vector::length(&leaderboard.top_players);
        let n = if (count < len) { count } else { len };

        let mut i = 0;
        while (i < n) {
            let player = *vector::borrow(&leaderboard.top_players, i);
            let score = *table::borrow(&leaderboard.scores, player);
            vector::push_back(&mut entries, LeaderboardEntry {
                player,
                score,
                rank: i + 1,
            });
            i = i + 1;
        };

        entries
    }

    /// Get entry at rank
    public fun get_entry_at_rank(
        leaderboard: &Leaderboard,
        rank: u64,
    ): LeaderboardEntry {
        let idx = rank - 1;
        assert!(idx < vector::length(&leaderboard.top_players), EPlayerNotFound);

        let player = *vector::borrow(&leaderboard.top_players, idx);
        let score = *table::borrow(&leaderboard.scores, player);

        LeaderboardEntry { player, score, rank }
    }

    // === View Functions ===

    /// Get leaderboard size
    public fun size(leaderboard: &Leaderboard): u64 {
        vector::length(&leaderboard.top_players)
    }

    /// Get min score to enter top
    public fun min_score_for_top(leaderboard: &Leaderboard): u64 {
        if (vector::length(&leaderboard.top_players) < leaderboard.max_entries) {
            0
        } else {
            leaderboard.min_top_score
        }
    }

    /// Has player
    public fun has_player(leaderboard: &Leaderboard, player: address): bool {
        table::contains(&leaderboard.scores, player)
    }

    /// Entry info
    public fun entry_info(entry: &LeaderboardEntry): (address, u64, u64) {
        (entry.player, entry.score, entry.rank)
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use std::string;

    #[test]
    fun test_create_leaderboard() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let lb = new(string::utf8(b"High Scores"), 10, scenario.ctx());
            assert!(size(&lb) == 0, 0);

            transfer::public_share_object(lb);
        };

        scenario.end();
    }

    #[test]
    fun test_submit_score() {
        let admin = @0xAD;
        let player1 = @0x1;
        let player2 = @0x2;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut lb = new(string::utf8(b"High Scores"), 10, scenario.ctx());

            submit_score(&mut lb, player1, 100);
            assert!(get_score(&lb, player1) == 100, 0);
            assert!(get_rank(&lb, player1) == 1, 1);

            submit_score(&mut lb, player2, 200);
            assert!(get_rank(&lb, player2) == 1, 2);
            assert!(get_rank(&lb, player1) == 2, 3);

            transfer::public_share_object(lb);
        };

        scenario.end();
    }

    #[test]
    fun test_get_top() {
        let admin = @0xAD;
        let player1 = @0x1;
        let player2 = @0x2;
        let player3 = @0x3;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut lb = new(string::utf8(b"High Scores"), 10, scenario.ctx());

            submit_score(&mut lb, player1, 100);
            submit_score(&mut lb, player2, 200);
            submit_score(&mut lb, player3, 150);

            let top = get_top(&lb, 3);
            assert!(vector::length(&top) == 3, 0);

            let (p, s, r) = entry_info(vector::borrow(&top, 0));
            assert!(p == player2, 1);
            assert!(s == 200, 2);
            assert!(r == 1, 3);

            transfer::public_share_object(lb);
        };

        scenario.end();
    }
}
