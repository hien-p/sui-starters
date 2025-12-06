/// @title Randomness Utilities
/// @notice On-chain randomness helpers for games
/// @dev Part of @sui-starters/gaming package
module sui_starters_gaming::randomness {
    use sui::hash;
    use sui::bcs;

    // === Errors ===

    const EInvalidRange: u64 = 0;
    const EEmptyWeights: u64 = 1;

    // === Structs ===

    /// Simple PRNG state using seed
    public struct RandomState has store, copy, drop {
        seed: vector<u8>,
        counter: u64,
    }

    // === Create Functions ===

    /// Create new random state from seed
    public fun new_state(seed: vector<u8>): RandomState {
        RandomState {
            seed,
            counter: 0,
        }
    }

    /// Create state from transaction context
    public fun from_ctx(ctx: &TxContext): RandomState {
        let sender = tx_context::sender(ctx);
        let epoch = tx_context::epoch(ctx);

        let mut seed_data = bcs::to_bytes(&sender);
        vector::append(&mut seed_data, bcs::to_bytes(&epoch));

        RandomState {
            seed: hash::keccak256(&seed_data),
            counter: 0,
        }
    }

    // === Core Functions ===

    /// Generate next random u64
    public fun next_u64(state: &mut RandomState): u64 {
        state.counter = state.counter + 1;

        let mut data = state.seed;
        vector::append(&mut data, bcs::to_bytes(&state.counter));

        let hash_result = hash::keccak256(&data);

        // Convert first 8 bytes to u64
        bytes_to_u64(&hash_result)
    }

    /// Generate random u64 in range [min, max]
    public fun range(state: &mut RandomState, min: u64, max: u64): u64 {
        assert!(max >= min, EInvalidRange);

        if (max == min) {
            return min
        };

        let range_size = max - min + 1;
        let random = next_u64(state);

        min + (random % range_size)
    }

    /// Generate random bool with given probability (in basis points, 5000 = 50%)
    public fun chance(state: &mut RandomState, probability_bps: u64): bool {
        let roll = range(state, 0, 9999);
        roll < probability_bps
    }

    /// Pick random index from weighted array
    public fun weighted_pick(state: &mut RandomState, weights: &vector<u64>): u64 {
        let len = vector::length(weights);
        assert!(len > 0, EEmptyWeights);

        // Calculate total weight
        let mut total = 0u64;
        let mut i = 0;
        while (i < len) {
            total = total + *vector::borrow(weights, i);
            i = i + 1;
        };

        if (total == 0) {
            // All weights zero, pick random index
            return range(state, 0, len - 1)
        };

        // Roll
        let roll = range(state, 0, total - 1);

        // Find index
        let mut cumulative = 0u64;
        i = 0;
        while (i < len) {
            cumulative = cumulative + *vector::borrow(weights, i);
            if (roll < cumulative) {
                return i
            };
            i = i + 1;
        };

        // Fallback
        len - 1
    }

    /// Shuffle a vector in place (Fisher-Yates)
    public fun shuffle<T: drop>(state: &mut RandomState, vec: &mut vector<T>) {
        let len = vector::length(vec);
        if (len <= 1) {
            return
        };

        let mut i = len - 1;
        while (i > 0) {
            let j = range(state, 0, i);
            vector::swap(vec, i, j);
            i = i - 1;
        };
    }

    /// Pick N unique random indices from range [0, max)
    public fun pick_unique(
        state: &mut RandomState,
        count: u64,
        max: u64,
    ): vector<u64> {
        assert!(count <= max, EInvalidRange);

        let mut result = vector::empty<u64>();
        let mut available = vector::empty<u64>();

        // Initialize available indices
        let mut i = 0;
        while (i < max) {
            vector::push_back(&mut available, i);
            i = i + 1;
        };

        // Pick random indices
        i = 0;
        while (i < count) {
            let remaining = vector::length(&available);
            let idx = range(state, 0, remaining - 1);
            let picked = vector::remove(&mut available, idx);
            vector::push_back(&mut result, picked);
            i = i + 1;
        };

        result
    }

    /// Roll dice (NdS - N dice with S sides)
    public fun roll_dice(state: &mut RandomState, num_dice: u64, sides: u64): u64 {
        assert!(sides > 0, EInvalidRange);
        assert!(num_dice > 0, EInvalidRange);

        let mut total = 0u64;
        let mut i = 0;
        while (i < num_dice) {
            total = total + range(state, 1, sides);
            i = i + 1;
        };

        total
    }

    // === Helper Functions ===

    /// Convert first 8 bytes to u64
    fun bytes_to_u64(bytes: &vector<u8>): u64 {
        let mut result = 0u64;
        let mut i = 0;
        while (i < 8 && i < vector::length(bytes)) {
            result = (result << 8) | (*vector::borrow(bytes, i) as u64);
            i = i + 1;
        };
        result
    }

    // === Pure Functions (no state) ===

    /// Generate deterministic random from seed and nonce
    public fun hash_random(seed: &vector<u8>, nonce: u64): u64 {
        let mut data = *seed;
        vector::append(&mut data, bcs::to_bytes(&nonce));
        let hash_result = hash::keccak256(&data);
        bytes_to_u64(&hash_result)
    }

    /// Generate random in range from seed
    public fun hash_range(seed: &vector<u8>, nonce: u64, min: u64, max: u64): u64 {
        assert!(max >= min, EInvalidRange);
        if (max == min) {
            return min
        };

        let range_size = max - min + 1;
        let random = hash_random(seed, nonce);
        min + (random % range_size)
    }

    // === View Functions ===

    /// Get current counter
    public fun counter(state: &RandomState): u64 {
        state.counter
    }

    /// Get seed
    public fun seed(state: &RandomState): vector<u8> {
        state.seed
    }

    // === Tests ===

    #[test]
    fun test_new_state() {
        let state = new_state(vector[116, 101, 115, 116, 95, 115, 101, 101, 100]);
        assert!(counter(&state) == 0, 0);
    }

    #[test]
    fun test_next_u64() {
        let mut state = new_state(vector[116, 101, 115, 116, 95, 115, 101, 101, 100]);

        let r1 = next_u64(&mut state);
        let r2 = next_u64(&mut state);

        // Different results
        assert!(r1 != r2, 0);
        assert!(counter(&state) == 2, 1);
    }

    #[test]
    fun test_range() {
        let mut state = new_state(vector[116, 101, 115, 116, 95, 115, 101, 101, 100]);

        let mut i = 0;
        while (i < 100) {
            let r = range(&mut state, 10, 20);
            assert!(r >= 10 && r <= 20, 0);
            i = i + 1;
        };
    }

    #[test]
    fun test_chance() {
        let mut state = new_state(vector[116, 101, 115, 116, 95, 115, 101, 101, 100]);

        // 100% should always be true
        let mut i = 0;
        while (i < 10) {
            assert!(chance(&mut state, 10000), 0);
            i = i + 1;
        };

        // 0% should always be false
        i = 0;
        while (i < 10) {
            assert!(!chance(&mut state, 0), 1);
            i = i + 1;
        };
    }

    #[test]
    fun test_weighted_pick() {
        let mut state = new_state(vector[116, 101, 115, 116, 95, 115, 101, 101, 100]);

        // Single element
        let weights = vector[100u64];
        assert!(weighted_pick(&mut state, &weights) == 0, 0);

        // Heavy weight on last element
        let weights2 = vector[1u64, 1, 1, 1000];
        let mut last_count = 0u64;
        let mut i = 0;
        while (i < 100) {
            if (weighted_pick(&mut state, &weights2) == 3) {
                last_count = last_count + 1;
            };
            i = i + 1;
        };
        // Should pick last element most of the time
        assert!(last_count > 80, 1);
    }

    #[test]
    fun test_roll_dice() {
        let mut state = new_state(vector[116, 101, 115, 116, 95, 115, 101, 101, 100]);

        // 2d6 should be between 2 and 12
        let mut i = 0;
        while (i < 100) {
            let result = roll_dice(&mut state, 2, 6);
            assert!(result >= 2 && result <= 12, 0);
            i = i + 1;
        };
    }

    #[test]
    fun test_pick_unique() {
        let mut state = new_state(vector[116, 101, 115, 116, 95, 115, 101, 101, 100]);

        let picked = pick_unique(&mut state, 5, 10);
        assert!(vector::length(&picked) == 5, 0);

        // Check uniqueness
        let mut i = 0;
        while (i < 5) {
            let mut j = i + 1;
            while (j < 5) {
                assert!(
                    *vector::borrow(&picked, i) != *vector::borrow(&picked, j),
                    1,
                );
                j = j + 1;
            };
            i = i + 1;
        };
    }

    #[test]
    fun test_hash_random() {
        let seed = vector[116, 101, 115, 116, 95, 115, 101, 101, 100];

        let r1 = hash_random(&seed, 0);
        let r2 = hash_random(&seed, 1);
        let r3 = hash_random(&seed, 0);

        assert!(r1 != r2, 0);
        assert!(r1 == r3, 1); // Same seed + nonce = same result
    }
}
