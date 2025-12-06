/// @title Vesting Sale
/// @notice Token sale with vesting schedule
/// @dev Part of @sui-starters/launchpad package
module sui_starters_launchpad::vesting_sale {
    use std::string::String;
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;

    // === Errors ===

    const ESaleNotStarted: u64 = 0;
    const ESaleEnded: u64 = 1;
    const EHardCapReached: u64 = 2;
    const EMinPurchaseNotMet: u64 = 3;
    const EMaxPurchaseExceeded: u64 = 4;
    const ENothingToClaim: u64 = 5;
    const ESaleNotEnded: u64 = 6;
    const EInvalidVestingConfig: u64 = 7;

    // === Structs ===

    /// Vesting configuration
    public struct VestingConfig has store, copy, drop {
        /// Initial unlock percentage (bps, e.g., 1000 = 10%)
        initial_unlock_bps: u64,
        /// Cliff duration (ms from sale end)
        cliff_duration: u64,
        /// Vesting duration after cliff (ms)
        vesting_duration: u64,
        /// Vesting release periods (e.g., monthly = 30 days in ms)
        release_period: u64,
    }

    /// Vesting sale
    public struct VestingSale<phantom T, phantom P> has key, store {
        id: UID,
        name: String,
        /// Tokens for sale
        tokens_for_sale: Balance<T>,
        /// Payments collected
        payments_collected: Balance<P>,
        /// Token price (payment per token, scaled by 1e9)
        price: u64,
        /// Hard cap in payment tokens
        hard_cap: u64,
        /// Minimum purchase
        min_purchase: u64,
        /// Maximum purchase per user
        max_purchase: u64,
        /// Sale start time (ms)
        start_time: u64,
        /// Sale end time (ms)
        end_time: u64,
        /// Vesting config
        vesting_config: VestingConfig,
        /// Total raised
        total_raised: u64,
        /// Total participants
        participant_count: u64,
    }

    /// Admin capability
    public struct VestingSaleAdmin<phantom T, phantom P> has key, store {
        id: UID,
        sale_id: ID,
    }

    /// Vesting position (tracks user's vested tokens)
    public struct VestingPosition<phantom T, phantom P> has key, store {
        id: UID,
        sale_id: ID,
        owner: address,
        /// Total tokens purchased
        total_tokens: u64,
        /// Tokens already claimed
        claimed_tokens: u64,
        /// Purchase timestamp
        purchase_time: u64,
        /// Payment amount
        payment_amount: u64,
    }

    // === Events ===

    public struct VestingSaleCreated has copy, drop {
        sale_id: ID,
        name: String,
        hard_cap: u64,
        initial_unlock_bps: u64,
        cliff_duration: u64,
        vesting_duration: u64,
    }

    public struct TokensPurchased has copy, drop {
        sale_id: ID,
        buyer: address,
        payment_amount: u64,
        token_amount: u64,
    }

    public struct TokensClaimed has copy, drop {
        sale_id: ID,
        claimer: address,
        amount: u64,
        total_claimed: u64,
        remaining: u64,
    }

    // === Constants ===

    const PRICE_PRECISION: u64 = 1000000000; // 1e9
    const BPS_BASE: u64 = 10000;

    // === Create Functions ===

    /// Create vesting config
    public fun new_vesting_config(
        initial_unlock_bps: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        release_period: u64,
    ): VestingConfig {
        assert!(initial_unlock_bps <= BPS_BASE, EInvalidVestingConfig);
        assert!(release_period > 0, EInvalidVestingConfig);

        VestingConfig {
            initial_unlock_bps,
            cliff_duration,
            vesting_duration,
            release_period,
        }
    }

    /// Create a new vesting sale
    public fun new<T, P>(
        name: String,
        tokens: Coin<T>,
        price: u64,
        hard_cap: u64,
        min_purchase: u64,
        max_purchase: u64,
        start_time: u64,
        end_time: u64,
        vesting_config: VestingConfig,
        ctx: &mut TxContext,
    ): (VestingSale<T, P>, VestingSaleAdmin<T, P>) {
        let token_balance = coin::into_balance(tokens);

        let sale = VestingSale {
            id: object::new(ctx),
            name,
            tokens_for_sale: token_balance,
            payments_collected: balance::zero(),
            price,
            hard_cap,
            min_purchase,
            max_purchase,
            start_time,
            end_time,
            vesting_config,
            total_raised: 0,
            participant_count: 0,
        };

        let sale_id = object::id(&sale);

        let admin = VestingSaleAdmin {
            id: object::new(ctx),
            sale_id,
        };

        event::emit(VestingSaleCreated {
            sale_id,
            name: sale.name,
            hard_cap,
            initial_unlock_bps: vesting_config.initial_unlock_bps,
            cliff_duration: vesting_config.cliff_duration,
            vesting_duration: vesting_config.vesting_duration,
        });

        (sale, admin)
    }

    // === Core Functions ===

    /// Purchase tokens with vesting
    public fun purchase<T, P>(
        sale: &mut VestingSale<T, P>,
        payment: Coin<P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): VestingPosition<T, P> {
        let current_time = sui::clock::timestamp_ms(clock);

        assert!(current_time >= sale.start_time, ESaleNotStarted);
        assert!(current_time <= sale.end_time, ESaleEnded);

        let payment_amount = coin::value(&payment);
        assert!(payment_amount >= sale.min_purchase, EMinPurchaseNotMet);
        assert!(payment_amount <= sale.max_purchase, EMaxPurchaseExceeded);
        assert!(sale.total_raised + payment_amount <= sale.hard_cap, EHardCapReached);

        // Calculate tokens
        let token_amount = calculate_tokens(payment_amount, sale.price);

        // Update sale state
        sale.total_raised = sale.total_raised + payment_amount;
        sale.participant_count = sale.participant_count + 1;

        // Collect payment
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut sale.payments_collected, payment_balance);

        let position = VestingPosition {
            id: object::new(ctx),
            sale_id: object::id(sale),
            owner: ctx.sender(),
            total_tokens: token_amount,
            claimed_tokens: 0,
            purchase_time: current_time,
            payment_amount,
        };

        event::emit(TokensPurchased {
            sale_id: object::id(sale),
            buyer: ctx.sender(),
            payment_amount,
            token_amount,
        });

        position
    }

    /// Claim vested tokens
    public fun claim<T, P>(
        sale: &mut VestingSale<T, P>,
        position: &mut VestingPosition<T, P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let current_time = sui::clock::timestamp_ms(clock);

        // Sale must be ended
        assert!(current_time > sale.end_time, ESaleNotEnded);

        // Calculate claimable
        let claimable = calculate_claimable(
            &sale.vesting_config,
            position,
            sale.end_time,
            current_time,
        );

        assert!(claimable > 0, ENothingToClaim);

        // Update position
        position.claimed_tokens = position.claimed_tokens + claimable;

        // Transfer tokens
        let tokens = balance::split(&mut sale.tokens_for_sale, claimable);

        event::emit(TokensClaimed {
            sale_id: object::id(sale),
            claimer: position.owner,
            amount: claimable,
            total_claimed: position.claimed_tokens,
            remaining: position.total_tokens - position.claimed_tokens,
        });

        coin::from_balance(tokens, ctx)
    }

    /// Calculate claimable tokens
    fun calculate_claimable<T, P>(
        config: &VestingConfig,
        position: &VestingPosition<T, P>,
        sale_end_time: u64,
        current_time: u64,
    ): u64 {
        let total = position.total_tokens;
        let claimed = position.claimed_tokens;

        // Calculate unlocked amount
        let unlocked = calculate_unlocked(config, total, sale_end_time, current_time);

        // Claimable = unlocked - already claimed
        if (unlocked > claimed) {
            unlocked - claimed
        } else {
            0
        }
    }

    /// Calculate total unlocked tokens
    fun calculate_unlocked(
        config: &VestingConfig,
        total_tokens: u64,
        sale_end_time: u64,
        current_time: u64,
    ): u64 {
        // Initial unlock (available immediately after sale ends)
        let initial_unlock = (total_tokens * config.initial_unlock_bps) / BPS_BASE;
        let vesting_tokens = total_tokens - initial_unlock;

        if (current_time < sale_end_time) {
            return 0
        };

        let time_since_end = current_time - sale_end_time;

        // Before cliff: only initial unlock
        if (time_since_end < config.cliff_duration) {
            return initial_unlock
        };

        // After cliff: initial + vested portion
        let time_since_cliff = time_since_end - config.cliff_duration;

        if (time_since_cliff >= config.vesting_duration) {
            // Fully vested
            return total_tokens
        };

        // Calculate vested periods
        let periods_elapsed = time_since_cliff / config.release_period;
        let total_periods = config.vesting_duration / config.release_period;

        if (total_periods == 0) {
            return total_tokens
        };

        let vested = (vesting_tokens * periods_elapsed) / total_periods;

        initial_unlock + vested
    }

    /// Calculate tokens for payment
    fun calculate_tokens(payment: u64, price: u64): u64 {
        ((payment as u128) * (PRICE_PRECISION as u128) / (price as u128)) as u64
    }

    // === Admin Functions ===

    /// Withdraw collected payments
    public fun withdraw_payments<T, P>(
        sale: &mut VestingSale<T, P>,
        _admin: &VestingSaleAdmin<T, P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<P> {
        let current_time = sui::clock::timestamp_ms(clock);
        assert!(current_time > sale.end_time, ESaleNotEnded);

        let amount = balance::value(&sale.payments_collected);
        let payments = balance::split(&mut sale.payments_collected, amount);

        coin::from_balance(payments, ctx)
    }

    /// Withdraw unsold tokens
    public fun withdraw_unsold<T, P>(
        sale: &mut VestingSale<T, P>,
        _admin: &VestingSaleAdmin<T, P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let current_time = sui::clock::timestamp_ms(clock);
        assert!(current_time > sale.end_time, ESaleNotEnded);

        // Calculate unsold tokens
        let total_sold_value = (sale.total_raised * PRICE_PRECISION) / sale.price;
        let _ = total_sold_value; // Suppress warning

        let available = balance::value(&sale.tokens_for_sale);
        let tokens = balance::split(&mut sale.tokens_for_sale, available);

        coin::from_balance(tokens, ctx)
    }

    // === View Functions ===

    /// Get sale info
    public fun sale_info<T, P>(sale: &VestingSale<T, P>): (u64, u64, u64, u64) {
        (
            balance::value(&sale.tokens_for_sale),
            sale.total_raised,
            sale.hard_cap,
            sale.participant_count,
        )
    }

    /// Get vesting config
    public fun get_vesting_config<T, P>(sale: &VestingSale<T, P>): (u64, u64, u64, u64) {
        (
            sale.vesting_config.initial_unlock_bps,
            sale.vesting_config.cliff_duration,
            sale.vesting_config.vesting_duration,
            sale.vesting_config.release_period,
        )
    }

    /// Get position info
    public fun position_info<T, P>(position: &VestingPosition<T, P>): (u64, u64, u64) {
        (position.total_tokens, position.claimed_tokens, position.payment_amount)
    }

    /// Preview claimable amount
    public fun preview_claimable<T, P>(
        sale: &VestingSale<T, P>,
        position: &VestingPosition<T, P>,
        clock: &Clock,
    ): u64 {
        let current_time = sui::clock::timestamp_ms(clock);

        if (current_time <= sale.end_time) {
            return 0
        };

        calculate_claimable(
            &sale.vesting_config,
            position,
            sale.end_time,
            current_time,
        )
    }

    /// Get unlocked percentage
    public fun unlocked_percentage<T, P>(
        sale: &VestingSale<T, P>,
        position: &VestingPosition<T, P>,
        clock: &Clock,
    ): u64 {
        let current_time = sui::clock::timestamp_ms(clock);

        if (current_time <= sale.end_time || position.total_tokens == 0) {
            return 0
        };

        let unlocked = calculate_unlocked(
            &sale.vesting_config,
            position.total_tokens,
            sale.end_time,
            current_time,
        );

        (unlocked * BPS_BASE) / position.total_tokens
    }

    /// Is sale active
    public fun is_active<T, P>(sale: &VestingSale<T, P>, clock: &Clock): bool {
        let current_time = sui::clock::timestamp_ms(clock);
        current_time >= sale.start_time &&
        current_time <= sale.end_time &&
        sale.total_raised < sale.hard_cap
    }

    /// Get total raised
    public fun total_raised<T, P>(sale: &VestingSale<T, P>): u64 {
        sale.total_raised
    }

    /// Get remaining to claim
    public fun remaining_to_claim<T, P>(position: &VestingPosition<T, P>): u64 {
        position.total_tokens - position.claimed_tokens
    }

    /// Price precision constant
    public fun price_precision(): u64 { PRICE_PRECISION }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::clock;
    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use std::string;

    #[test]
    fun test_create_vesting_config() {
        let config = new_vesting_config(
            1000, // 10% initial unlock
            2592000000, // 30 day cliff (ms)
            7776000000, // 90 day vesting
            2592000000, // Monthly release
        );

        assert!(config.initial_unlock_bps == 1000, 0);
        assert!(config.cliff_duration == 2592000000, 1);
        assert!(config.vesting_duration == 7776000000, 2);
        assert!(config.release_period == 2592000000, 3);
    }

    #[test]
    fun test_create_vesting_sale() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let config = new_vesting_config(1000, 2592000000, 7776000000, 2592000000);

            let (sale, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Vesting Sale"),
                tokens,
                1000000000, // 1:1
                100000, // 100k hard cap
                100, // min
                10000, // max
                0,
                1000000000, // 1000 seconds
                config,
                scenario.ctx(),
            );

            let (tokens_avail, raised, hard_cap, participants) = sale_info(&sale);
            assert!(tokens_avail == 1000000, 0);
            assert!(raised == 0, 1);
            assert!(hard_cap == 100000, 2);
            assert!(participants == 0, 3);

            transfer::public_share_object(sale);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_purchase_with_vesting() {
        let admin = @0xAD;
        let buyer = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create sale
        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let config = new_vesting_config(1000, 0, 3000, 1000); // 10% initial, no cliff, 3s vesting, 1s periods

            let (sale, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Vesting Sale"),
                tokens,
                1000000000,
                100000,
                100,
                10000,
                0,
                1000000000000,
                config,
                scenario.ctx(),
            );

            transfer::public_share_object(sale);
            transfer::public_transfer(admin_cap, admin);
        };

        // Purchase
        scenario.next_tx(buyer);
        {
            let mut sale = scenario.take_shared<VestingSale<SUI, SUI>>();
            let payment = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let clk = clock::create_for_testing(scenario.ctx());

            let position = purchase(&mut sale, payment, &clk, scenario.ctx());

            let (total, claimed, payment_amt) = position_info(&position);
            assert!(total == 1000, 0);
            assert!(claimed == 0, 1);
            assert!(payment_amt == 1000, 2);

            assert!(total_raised(&sale) == 1000, 3);

            transfer::public_transfer(position, buyer);
            clock::destroy_for_testing(clk);
            test_scenario::return_shared(sale);
        };

        scenario.end();
    }

    #[test]
    fun test_vesting_unlock_calculation() {
        // Test initial unlock
        let config = new_vesting_config(
            2000, // 20% initial
            1000, // 1s cliff
            3000, // 3s vesting
            1000, // 1s periods
        );

        let total = 10000;

        // Before sale ends - 0
        let unlocked0 = calculate_unlocked(&config, total, 10000, 5000);
        assert!(unlocked0 == 0, 0);

        // After sale, before cliff - 20%
        let unlocked1 = calculate_unlocked(&config, total, 10000, 10500);
        assert!(unlocked1 == 2000, 1); // 20% initial

        // After cliff, 1 period (1s) - 20% + 1/3 of 80%
        let unlocked2 = calculate_unlocked(&config, total, 10000, 12000);
        assert!(unlocked2 == 2000 + 2666, 2); // ~46.66%

        // Fully vested
        let unlocked3 = calculate_unlocked(&config, total, 10000, 20000);
        assert!(unlocked3 == 10000, 3); // 100%
    }

    #[test]
    fun test_vesting_config_getters() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let config = new_vesting_config(1000, 2000, 3000, 500);

            let (sale, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Test"),
                tokens,
                1000000000,
                100000,
                100,
                10000,
                0,
                1000000000000,
                config,
                scenario.ctx(),
            );

            let (initial, cliff, duration, period) = get_vesting_config(&sale);
            assert!(initial == 1000, 0);
            assert!(cliff == 2000, 1);
            assert!(duration == 3000, 2);
            assert!(period == 500, 3);

            transfer::public_share_object(sale);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }
}
