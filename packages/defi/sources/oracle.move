/// @title Price Oracle
/// @notice TWAP and spot price oracle for DeFi applications
/// @dev Part of @sui-starters/defi package
module sui_starters_defi::oracle {
    use sui::event;
    use sui::clock::Clock;

    // === Errors ===

    /// Price not initialized
    const EPriceNotInitialized: u64 = 0;

    /// Observation too old
    const EObservationTooOld: u64 = 1;

    /// Invalid window
    const EInvalidWindow: u64 = 2;

    /// Price is stale
    const EPriceStale: u64 = 3;

    // === Constants ===

    /// Maximum observations to store
    const MAX_OBSERVATIONS: u64 = 100;

    /// Price precision (10^18)
    const PRICE_PRECISION: u128 = 1000000000000000000;

    // === Structs ===

    /// Price observation at a point in time
    public struct Observation has store, copy, drop {
        /// Timestamp in milliseconds
        timestamp: u64,
        /// Cumulative price (scaled by precision)
        cumulative_price: u128,
        /// Spot price at observation
        spot_price: u64,
    }

    /// Oracle state for a price pair
    public struct PriceOracle has key, store {
        id: UID,
        /// Circular buffer of observations
        observations: vector<Observation>,
        /// Current write index
        write_index: u64,
        /// Number of observations stored
        observation_count: u64,
        /// Last update timestamp
        last_update: u64,
        /// Last spot price
        last_price: u64,
        /// Update interval (minimum ms between updates)
        update_interval: u64,
        /// Maximum staleness before price is considered stale
        max_staleness: u64,
    }

    /// TWAP result
    public struct TWAPResult has copy, drop {
        /// Average price over window
        twap: u64,
        /// Start timestamp
        start_time: u64,
        /// End timestamp
        end_time: u64,
        /// Number of observations used
        observations_used: u64,
    }

    // === Events ===

    /// Emitted when price is updated
    public struct PriceUpdated has copy, drop {
        oracle_id: ID,
        price: u64,
        timestamp: u64,
    }

    /// Emitted when TWAP is calculated
    public struct TWAPCalculated has copy, drop {
        oracle_id: ID,
        twap: u64,
        window: u64,
    }

    // === Create Functions ===

    /// Create new price oracle
    public fun new(
        update_interval: u64,
        max_staleness: u64,
        ctx: &mut TxContext,
    ): PriceOracle {
        PriceOracle {
            id: object::new(ctx),
            observations: vector[],
            write_index: 0,
            observation_count: 0,
            last_update: 0,
            last_price: 0,
            update_interval,
            max_staleness,
        }
    }

    /// Create with default settings
    public fun new_default(ctx: &mut TxContext): PriceOracle {
        new(
            60000, // 1 minute update interval
            3600000, // 1 hour max staleness
            ctx,
        )
    }

    // === Update Functions ===

    /// Update oracle with new price
    public fun update(
        oracle: &mut PriceOracle,
        price: u64,
        clock: &Clock,
    ) {
        let now = sui::clock::timestamp_ms(clock);

        // Check if enough time has passed since last update
        if (oracle.last_update > 0 && now - oracle.last_update < oracle.update_interval) {
            return // Skip update, too soon
        };

        // Calculate cumulative price
        let time_elapsed = if (oracle.last_update == 0) { 0 } else { now - oracle.last_update };
        let price_contribution = (oracle.last_price as u128) * (time_elapsed as u128);

        let last_cumulative = if (oracle.observation_count == 0) {
            0
        } else {
            let last_idx = if (oracle.write_index == 0) {
                oracle.observation_count - 1
            } else {
                oracle.write_index - 1
            };
            vector::borrow(&oracle.observations, last_idx).cumulative_price
        };

        let observation = Observation {
            timestamp: now,
            cumulative_price: last_cumulative + price_contribution,
            spot_price: price,
        };

        // Add or replace observation
        if (oracle.observation_count < MAX_OBSERVATIONS) {
            vector::push_back(&mut oracle.observations, observation);
            oracle.observation_count = oracle.observation_count + 1;
        } else {
            *vector::borrow_mut(&mut oracle.observations, oracle.write_index) = observation;
        };

        // Update write index
        oracle.write_index = (oracle.write_index + 1) % MAX_OBSERVATIONS;

        // Update last values
        oracle.last_update = now;
        oracle.last_price = price;

        event::emit(PriceUpdated {
            oracle_id: object::id(oracle),
            price,
            timestamp: now,
        });
    }

    /// Update from reserves (for AMM integration)
    public fun update_from_reserves(
        oracle: &mut PriceOracle,
        reserve_a: u64,
        reserve_b: u64,
        clock: &Clock,
    ) {
        if (reserve_a == 0) {
            return
        };

        // Calculate price with precision
        let price = ((reserve_b as u128) * (PRICE_PRECISION as u128) / (reserve_a as u128)) as u64;
        update(oracle, price, clock);
    }

    // === Query Functions ===

    /// Get current spot price
    public fun get_price(oracle: &PriceOracle): u64 {
        assert!(oracle.observation_count > 0, EPriceNotInitialized);
        oracle.last_price
    }

    /// Get price with staleness check
    public fun get_price_safe(oracle: &PriceOracle, clock: &Clock): u64 {
        assert!(oracle.observation_count > 0, EPriceNotInitialized);

        let now = sui::clock::timestamp_ms(clock);
        assert!(now - oracle.last_update <= oracle.max_staleness, EPriceStale);

        oracle.last_price
    }

    /// Check if price is stale
    public fun is_stale(oracle: &PriceOracle, clock: &Clock): bool {
        if (oracle.observation_count == 0) {
            return true
        };

        let now = sui::clock::timestamp_ms(clock);
        now - oracle.last_update > oracle.max_staleness
    }

    /// Calculate TWAP over time window
    public fun get_twap(oracle: &PriceOracle, window: u64, clock: &Clock): TWAPResult {
        assert!(oracle.observation_count >= 2, EPriceNotInitialized);
        assert!(window > 0, EInvalidWindow);

        let now = sui::clock::timestamp_ms(clock);
        let target_time = if (now > window) { now - window } else { 0 };

        // Find observations at start and end of window
        let (start_obs, end_obs, obs_count) = find_observations_for_window(oracle, target_time, now);

        // Calculate TWAP
        let time_elapsed = end_obs.timestamp - start_obs.timestamp;
        let twap = if (time_elapsed == 0) {
            end_obs.spot_price
        } else {
            let price_diff = end_obs.cumulative_price - start_obs.cumulative_price;
            (price_diff / (time_elapsed as u128)) as u64
        };

        event::emit(TWAPCalculated {
            oracle_id: object::id(oracle),
            twap,
            window,
        });

        TWAPResult {
            twap,
            start_time: start_obs.timestamp,
            end_time: end_obs.timestamp,
            observations_used: obs_count,
        }
    }

    /// Get simple moving average of recent prices
    public fun get_sma(oracle: &PriceOracle, num_observations: u64): u64 {
        assert!(oracle.observation_count > 0, EPriceNotInitialized);

        let count = if (num_observations > oracle.observation_count) {
            oracle.observation_count
        } else {
            num_observations
        };

        let mut sum: u128 = 0;
        let mut i = 0;

        while (i < count) {
            let idx = if (oracle.write_index > i) {
                oracle.write_index - i - 1
            } else {
                oracle.observation_count - (i - oracle.write_index) - 1
            };

            let obs = vector::borrow(&oracle.observations, idx);
            sum = sum + (obs.spot_price as u128);
            i = i + 1;
        };

        ((sum / (count as u128)) as u64)
    }

    // === Internal Functions ===

    /// Find observations for TWAP calculation
    fun find_observations_for_window(
        oracle: &PriceOracle,
        target_start: u64,
        target_end: u64,
    ): (Observation, Observation, u64) {
        let mut start_obs = *vector::borrow(&oracle.observations, 0);
        let mut end_obs = start_obs;
        let mut count: u64 = 0;

        // Find closest observations to target times
        let len = oracle.observation_count;
        let mut i = 0;

        while (i < len) {
            let obs = *vector::borrow(&oracle.observations, i);

            if (obs.timestamp <= target_start) {
                start_obs = obs;
            };

            if (obs.timestamp <= target_end) {
                end_obs = obs;
                count = count + 1;
            };

            i = i + 1;
        };

        (start_obs, end_obs, count)
    }

    // === View Functions ===

    /// Get observation count
    public fun observation_count(oracle: &PriceOracle): u64 {
        oracle.observation_count
    }

    /// Get last update timestamp
    public fun last_update(oracle: &PriceOracle): u64 {
        oracle.last_update
    }

    /// Get update interval
    public fun update_interval(oracle: &PriceOracle): u64 {
        oracle.update_interval
    }

    /// Get max staleness
    public fun max_staleness(oracle: &PriceOracle): u64 {
        oracle.max_staleness
    }

    /// Get observation at index
    public fun get_observation(oracle: &PriceOracle, index: u64): Observation {
        assert!(index < oracle.observation_count, EPriceNotInitialized);
        *vector::borrow(&oracle.observations, index)
    }

    /// Get price precision
    public fun price_precision(): u128 {
        PRICE_PRECISION
    }

    // === TWAPResult Accessors ===

    /// Get TWAP value
    public fun twap_value(result: &TWAPResult): u64 {
        result.twap
    }

    /// Get TWAP start time
    public fun twap_start_time(result: &TWAPResult): u64 {
        result.start_time
    }

    /// Get TWAP end time
    public fun twap_end_time(result: &TWAPResult): u64 {
        result.end_time
    }

    // === Observation Accessors ===

    /// Get observation timestamp
    public fun obs_timestamp(obs: &Observation): u64 {
        obs.timestamp
    }

    /// Get observation spot price
    public fun obs_spot_price(obs: &Observation): u64 {
        obs.spot_price
    }

    // === Tests ===

    #[test]
    fun test_oracle_create() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let oracle = new_default(scenario.ctx());

            assert!(observation_count(&oracle) == 0, 0);
            assert!(update_interval(&oracle) == 60000, 1);
            assert!(max_staleness(&oracle) == 3600000, 2);

            transfer::public_share_object(oracle);
        };

        scenario.end();
    }

    #[test]
    fun test_oracle_update() {
        use sui::test_scenario;
        use sui::clock;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut oracle = new(0, 3600000, scenario.ctx()); // No min interval
            let mut test_clock = clock::create_for_testing(scenario.ctx());

            // First update
            clock::set_for_testing(&mut test_clock, 1000);
            update(&mut oracle, 100, &test_clock);

            assert!(observation_count(&oracle) == 1, 0);
            assert!(get_price(&oracle) == 100, 1);

            // Second update
            clock::set_for_testing(&mut test_clock, 2000);
            update(&mut oracle, 110, &test_clock);

            assert!(observation_count(&oracle) == 2, 2);
            assert!(get_price(&oracle) == 110, 3);

            clock::destroy_for_testing(test_clock);
            transfer::public_share_object(oracle);
        };

        scenario.end();
    }

    #[test]
    fun test_sma() {
        use sui::test_scenario;
        use sui::clock;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut oracle = new(0, 3600000, scenario.ctx());
            let mut test_clock = clock::create_for_testing(scenario.ctx());

            // Add prices: 100, 110, 120, 130, 140
            let mut i = 0;
            while (i < 5) {
                clock::set_for_testing(&mut test_clock, (i + 1) * 1000);
                update(&mut oracle, 100 + i * 10, &test_clock);
                i = i + 1;
            };

            // SMA of last 5 = (100+110+120+130+140)/5 = 120
            let sma = get_sma(&oracle, 5);
            assert!(sma == 120, 0);

            // SMA of last 3 = (120+130+140)/3 = 130
            let sma3 = get_sma(&oracle, 3);
            assert!(sma3 == 130, 1);

            clock::destroy_for_testing(test_clock);
            transfer::public_share_object(oracle);
        };

        scenario.end();
    }

    #[test]
    fun test_staleness() {
        use sui::test_scenario;
        use sui::clock;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut oracle = new(0, 1000, scenario.ctx()); // 1 second max staleness
            let mut test_clock = clock::create_for_testing(scenario.ctx());

            clock::set_for_testing(&mut test_clock, 1000);
            update(&mut oracle, 100, &test_clock);

            // Not stale yet
            clock::set_for_testing(&mut test_clock, 1500);
            assert!(!is_stale(&oracle, &test_clock), 0);

            // Now stale
            clock::set_for_testing(&mut test_clock, 3000);
            assert!(is_stale(&oracle, &test_clock), 1);

            clock::destroy_for_testing(test_clock);
            transfer::public_share_object(oracle);
        };

        scenario.end();
    }

    #[test]
    fun test_update_from_reserves() {
        use sui::test_scenario;
        use sui::clock;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut oracle = new(0, 3600000, scenario.ctx());
            let mut test_clock = clock::create_for_testing(scenario.ctx());

            clock::set_for_testing(&mut test_clock, 1000);

            // 1:2 ratio
            update_from_reserves(&mut oracle, 1000, 2000, &test_clock);

            let price = get_price(&oracle);
            // Expected: 2 * 10^18 = 2000000000000000000
            assert!(price == 2000000000000000000, 0);

            clock::destroy_for_testing(test_clock);
            transfer::public_share_object(oracle);
        };

        scenario.end();
    }
}
