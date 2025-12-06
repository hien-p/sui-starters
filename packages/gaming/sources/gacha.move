/// @title Gacha System
/// @notice Randomized reward distribution with rarity tiers
/// @dev Part of @sui-starters/gaming package
module sui_starters_gaming::gacha {
    use std::string::String;
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};

    // === Errors ===

    const EBannerNotActive: u64 = 0;
    const EInsufficientPayment: u64 = 1;
    const ENoItemsInPool: u64 = 2;
    const EPityNotReached: u64 = 3;
    const EInvalidRates: u64 = 4;
    const EBannerExpired: u64 = 5;

    // === Constants ===

    /// Rarity tiers
    const RARITY_COMMON: u8 = 0;
    const RARITY_UNCOMMON: u8 = 1;
    const RARITY_RARE: u8 = 2;
    const RARITY_EPIC: u8 = 3;
    const RARITY_LEGENDARY: u8 = 4;

    /// Basis points (10000 = 100%)
    const BPS_MAX: u64 = 10000;

    // === Structs ===

    /// Gacha banner configuration
    public struct GachaBanner<phantom T> has key, store {
        id: UID,
        name: String,
        /// Cost per pull
        pull_cost: u64,
        /// Accumulated payments
        treasury: Balance<T>,
        /// Rate in bps for each rarity tier [common, uncommon, rare, epic, legendary]
        rates: vector<u64>,
        /// Items in each rarity pool
        pools: vector<vector<String>>,
        /// Pity counter threshold for guaranteed high rarity
        pity_threshold: u64,
        /// Is banner active
        active: bool,
        /// End epoch (0 = no expiry)
        end_epoch: u64,
        /// Total pulls made
        total_pulls: u64,
    }

    /// Player's gacha state for a banner
    public struct PlayerGachaState has key, store {
        id: UID,
        player: address,
        banner_id: ID,
        /// Current pity counter
        pity_counter: u64,
        /// Total pulls on this banner
        total_pulls: u64,
        /// Legendary items obtained
        legendary_count: u64,
    }

    /// Pull result
    public struct PullResult has copy, drop, store {
        item: String,
        rarity: u8,
        was_pity: bool,
    }

    // === Events ===

    public struct BannerCreated has copy, drop {
        banner_id: ID,
        name: String,
        pull_cost: u64,
    }

    public struct GachaPull has copy, drop {
        banner_id: ID,
        player: address,
        item: String,
        rarity: u8,
        was_pity: bool,
    }

    public struct PityTriggered has copy, drop {
        banner_id: ID,
        player: address,
        pity_count: u64,
    }

    // === Create Functions ===

    /// Create new gacha banner
    public fun new_banner<T>(
        name: String,
        pull_cost: u64,
        rates: vector<u64>,
        pools: vector<vector<String>>,
        pity_threshold: u64,
        end_epoch: u64,
        ctx: &mut TxContext,
    ): GachaBanner<T> {
        // Validate rates sum to 100%
        let mut total_rate = 0u64;
        let mut i = 0;
        while (i < vector::length(&rates)) {
            total_rate = total_rate + *vector::borrow(&rates, i);
            i = i + 1;
        };
        assert!(total_rate == BPS_MAX, EInvalidRates);
        assert!(vector::length(&rates) == vector::length(&pools), EInvalidRates);

        let banner = GachaBanner {
            id: object::new(ctx),
            name,
            pull_cost,
            treasury: balance::zero(),
            rates,
            pools,
            pity_threshold,
            active: true,
            end_epoch,
            total_pulls: 0,
        };

        event::emit(BannerCreated {
            banner_id: object::id(&banner),
            name: banner.name,
            pull_cost,
        });

        banner
    }

    /// Create player gacha state
    public fun new_player_state(
        banner_id: ID,
        ctx: &mut TxContext,
    ): PlayerGachaState {
        PlayerGachaState {
            id: object::new(ctx),
            player: ctx.sender(),
            banner_id,
            pity_counter: 0,
            total_pulls: 0,
            legendary_count: 0,
        }
    }

    // === Core Functions ===

    /// Perform a single pull
    public fun pull<T>(
        banner: &mut GachaBanner<T>,
        state: &mut PlayerGachaState,
        payment: Coin<T>,
        random_value: u64,
        ctx: &TxContext,
    ): PullResult {
        assert!(banner.active, EBannerNotActive);
        if (banner.end_epoch > 0) {
            assert!(ctx.epoch() <= banner.end_epoch, EBannerExpired);
        };
        assert!(coin::value(&payment) >= banner.pull_cost, EInsufficientPayment);

        // Take payment
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut banner.treasury, payment_balance);

        // Determine if pity triggers
        state.pity_counter = state.pity_counter + 1;
        let was_pity = state.pity_counter >= banner.pity_threshold;

        // Determine rarity
        let rarity = if (was_pity) {
            state.pity_counter = 0;
            event::emit(PityTriggered {
                banner_id: object::id(banner),
                player: state.player,
                pity_count: banner.pity_threshold,
            });
            RARITY_LEGENDARY
        } else {
            determine_rarity(&banner.rates, random_value)
        };

        // Reset pity if got legendary naturally
        if (rarity == RARITY_LEGENDARY && !was_pity) {
            state.pity_counter = 0;
        };

        // Get random item from pool
        let pool = vector::borrow(&banner.pools, (rarity as u64));
        assert!(vector::length(pool) > 0, ENoItemsInPool);
        let item_index = (random_value / 100) % vector::length(pool);
        let item = *vector::borrow(pool, item_index);

        // Update stats
        state.total_pulls = state.total_pulls + 1;
        banner.total_pulls = banner.total_pulls + 1;
        if (rarity == RARITY_LEGENDARY) {
            state.legendary_count = state.legendary_count + 1;
        };

        event::emit(GachaPull {
            banner_id: object::id(banner),
            player: state.player,
            item,
            rarity,
            was_pity,
        });

        PullResult { item, rarity, was_pity }
    }

    /// Determine rarity based on rates
    fun determine_rarity(rates: &vector<u64>, random_value: u64): u8 {
        let roll = random_value % BPS_MAX;
        let mut cumulative = 0u64;
        let mut i = 0u64;

        while (i < vector::length(rates)) {
            cumulative = cumulative + *vector::borrow(rates, i);
            if (roll < cumulative) {
                return (i as u8)
            };
            i = i + 1;
        };

        // Default to common if something goes wrong
        RARITY_COMMON
    }

    /// Multi-pull (10 pulls)
    public fun multi_pull<T>(
        banner: &mut GachaBanner<T>,
        state: &mut PlayerGachaState,
        payment: Coin<T>,
        random_values: vector<u64>,
        ctx: &mut TxContext,
    ): vector<PullResult> {
        let pull_count = vector::length(&random_values);
        let total_cost = banner.pull_cost * pull_count;
        assert!(coin::value(&payment) >= total_cost, EInsufficientPayment);

        let mut results = vector::empty<PullResult>();
        let mut remaining = payment;

        let mut i = 0;
        while (i < pull_count) {
            let pull_payment = coin::split(&mut remaining, banner.pull_cost, ctx);
            let random = *vector::borrow(&random_values, i);
            let result = pull(banner, state, pull_payment, random, ctx);
            vector::push_back(&mut results, result);
            i = i + 1;
        };

        // Return remaining payment if any
        if (coin::value(&remaining) > 0) {
            transfer::public_transfer(remaining, ctx.sender());
        } else {
            coin::destroy_zero(remaining);
        };

        results
    }

    // === Admin Functions ===

    /// Set banner active status
    public fun set_active<T>(banner: &mut GachaBanner<T>, active: bool) {
        banner.active = active;
    }

    /// Add item to pool
    public fun add_item_to_pool<T>(
        banner: &mut GachaBanner<T>,
        rarity: u8,
        item: String,
    ) {
        let pool = vector::borrow_mut(&mut banner.pools, (rarity as u64));
        vector::push_back(pool, item);
    }

    /// Withdraw treasury
    public fun withdraw_treasury<T>(
        banner: &mut GachaBanner<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        coin::take(&mut banner.treasury, amount, ctx)
    }

    // === View Functions ===

    /// Get pull cost
    public fun pull_cost<T>(banner: &GachaBanner<T>): u64 {
        banner.pull_cost
    }

    /// Get treasury balance
    public fun treasury_balance<T>(banner: &GachaBanner<T>): u64 {
        balance::value(&banner.treasury)
    }

    /// Get total pulls
    public fun total_pulls<T>(banner: &GachaBanner<T>): u64 {
        banner.total_pulls
    }

    /// Get player pity counter
    public fun pity_counter(state: &PlayerGachaState): u64 {
        state.pity_counter
    }

    /// Get player total pulls
    public fun player_total_pulls(state: &PlayerGachaState): u64 {
        state.total_pulls
    }

    /// Get player legendary count
    public fun player_legendary_count(state: &PlayerGachaState): u64 {
        state.legendary_count
    }

    /// Get pulls until pity
    public fun pulls_until_pity<T>(banner: &GachaBanner<T>, state: &PlayerGachaState): u64 {
        if (state.pity_counter >= banner.pity_threshold) {
            0
        } else {
            banner.pity_threshold - state.pity_counter
        }
    }

    /// Get result info
    public fun result_info(result: &PullResult): (String, u8, bool) {
        (result.item, result.rarity, result.was_pity)
    }

    /// Rarity constants
    public fun rarity_common(): u8 { RARITY_COMMON }
    public fun rarity_uncommon(): u8 { RARITY_UNCOMMON }
    public fun rarity_rare(): u8 { RARITY_RARE }
    public fun rarity_epic(): u8 { RARITY_EPIC }
    public fun rarity_legendary(): u8 { RARITY_LEGENDARY }

    // === Tests ===

    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use std::string;

    #[test]
    fun test_determine_rarity() {
        // Rates: 60% common, 25% uncommon, 10% rare, 4% epic, 1% legendary
        let rates = vector[6000u64, 2500, 1000, 400, 100];

        // Roll 0-5999 = common
        assert!(determine_rarity(&rates, 0) == RARITY_COMMON, 0);
        assert!(determine_rarity(&rates, 5999) == RARITY_COMMON, 1);

        // Roll 6000-8499 = uncommon
        assert!(determine_rarity(&rates, 6000) == RARITY_UNCOMMON, 2);

        // Roll 8500-9499 = rare
        assert!(determine_rarity(&rates, 8500) == RARITY_RARE, 3);

        // Roll 9500-9899 = epic
        assert!(determine_rarity(&rates, 9500) == RARITY_EPIC, 4);

        // Roll 9900-9999 = legendary
        assert!(determine_rarity(&rates, 9900) == RARITY_LEGENDARY, 5);
    }

    #[test]
    fun test_create_banner() {
        let ctx = &mut tx_context::dummy();

        let rates = vector[6000u64, 2500, 1000, 400, 100];
        let pools = vector[
            vector[string::utf8(b"common_item")],
            vector[string::utf8(b"uncommon_item")],
            vector[string::utf8(b"rare_item")],
            vector[string::utf8(b"epic_item")],
            vector[string::utf8(b"legendary_item")],
        ];

        let banner = new_banner<SUI>(
            string::utf8(b"Standard Banner"),
            1000000,
            rates,
            pools,
            90,
            0,
            ctx,
        );

        assert!(pull_cost(&banner) == 1000000, 0);
        assert!(total_pulls(&banner) == 0, 1);

        let GachaBanner {
            id,
            name: _,
            pull_cost: _,
            treasury,
            rates: _,
            pools: _,
            pity_threshold: _,
            active: _,
            end_epoch: _,
            total_pulls: _,
        } = banner;

        balance::destroy_zero(treasury);
        object::delete(id);
    }

    #[test]
    fun test_create_player_state() {
        let ctx = &mut tx_context::dummy();
        let banner_id = object::id_from_address(@0x123);

        let state = new_player_state(banner_id, ctx);

        assert!(pity_counter(&state) == 0, 0);
        assert!(player_total_pulls(&state) == 0, 1);
        assert!(player_legendary_count(&state) == 0, 2);

        let PlayerGachaState {
            id,
            player: _,
            banner_id: _,
            pity_counter: _,
            total_pulls: _,
            legendary_count: _,
        } = state;
        object::delete(id);
    }
}
