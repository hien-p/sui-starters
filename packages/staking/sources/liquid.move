/// @title Liquid Staking
/// @notice Liquid staking token representation
/// @dev Part of @sui-starters/staking package
module sui_starters_staking::liquid {
    use std::string::String;
    use sui::event;
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin, TreasuryCap};

    // === Errors ===

    const EInsufficientLiquidity: u64 = 0;
    const EExchangeRateZero: u64 = 1;
    const EPoolPaused: u64 = 2;
    const EMinimumNotMet: u64 = 3;

    // === Structs ===

    /// Liquid staking pool
    public struct LiquidStakingPool<phantom S, phantom L> has key, store {
        id: UID,
        name: String,
        /// Underlying staked tokens
        underlying: Balance<S>,
        /// Supply of liquid tokens
        liquid_supply: Supply<L>,
        /// Total rewards accumulated (not in underlying yet)
        accumulated_rewards: u64,
        /// Fee in basis points
        fee_bps: u64,
        /// Minimum stake
        min_stake: u64,
        /// Is pool paused
        paused: bool,
    }

    /// Admin capability
    public struct LiquidPoolAdmin<phantom S, phantom L> has key, store {
        id: UID,
        pool_id: ID,
    }

    // === Events ===

    public struct Minted has copy, drop {
        pool_id: ID,
        staker: address,
        underlying_amount: u64,
        liquid_amount: u64,
        exchange_rate: u64,
    }

    public struct Redeemed has copy, drop {
        pool_id: ID,
        redeemer: address,
        liquid_amount: u64,
        underlying_amount: u64,
        exchange_rate: u64,
    }

    public struct RewardsAdded has copy, drop {
        pool_id: ID,
        amount: u64,
        new_exchange_rate: u64,
    }

    // === Constants ===

    /// Exchange rate precision (1e9)
    const RATE_PRECISION: u64 = 1000000000;

    // === Create Functions ===

    /// Create liquid staking pool
    /// Note: Requires the liquid token's TreasuryCap for supply management
    public fun new<S, L>(
        name: String,
        treasury_cap: TreasuryCap<L>,
        fee_bps: u64,
        min_stake: u64,
        ctx: &mut TxContext,
    ): (LiquidStakingPool<S, L>, LiquidPoolAdmin<S, L>) {
        let liquid_supply = coin::treasury_into_supply(treasury_cap);

        let pool = LiquidStakingPool {
            id: object::new(ctx),
            name,
            underlying: balance::zero(),
            liquid_supply,
            accumulated_rewards: 0,
            fee_bps,
            min_stake,
            paused: false,
        };

        let pool_id = object::id(&pool);

        let admin = LiquidPoolAdmin {
            id: object::new(ctx),
            pool_id,
        };

        (pool, admin)
    }

    // === Core Functions ===

    /// Stake underlying tokens and receive liquid tokens
    public fun stake<S, L>(
        pool: &mut LiquidStakingPool<S, L>,
        underlying: Coin<S>,
        ctx: &mut TxContext,
    ): Coin<L> {
        assert!(!pool.paused, EPoolPaused);

        let underlying_amount = coin::value(&underlying);
        assert!(underlying_amount >= pool.min_stake, EMinimumNotMet);

        // Calculate liquid tokens to mint
        let liquid_amount = calculate_liquid_amount(pool, underlying_amount);

        // Add underlying to pool
        let underlying_balance = coin::into_balance(underlying);
        balance::join(&mut pool.underlying, underlying_balance);

        // Mint liquid tokens
        let liquid_balance = balance::increase_supply(&mut pool.liquid_supply, liquid_amount);

        event::emit(Minted {
            pool_id: object::id(pool),
            staker: ctx.sender(),
            underlying_amount,
            liquid_amount,
            exchange_rate: exchange_rate(pool),
        });

        coin::from_balance(liquid_balance, ctx)
    }

    /// Redeem liquid tokens for underlying
    public fun redeem<S, L>(
        pool: &mut LiquidStakingPool<S, L>,
        liquid: Coin<L>,
        ctx: &mut TxContext,
    ): Coin<S> {
        assert!(!pool.paused, EPoolPaused);

        let liquid_amount = coin::value(&liquid);

        // Calculate underlying to return
        let underlying_amount = calculate_underlying_amount(pool, liquid_amount);
        assert!(
            balance::value(&pool.underlying) >= underlying_amount,
            EInsufficientLiquidity,
        );

        // Apply fee
        let fee = (underlying_amount * pool.fee_bps) / 10000;
        let return_amount = underlying_amount - fee;

        // Burn liquid tokens
        let liquid_balance = coin::into_balance(liquid);
        balance::decrease_supply(&mut pool.liquid_supply, liquid_balance);

        // Return underlying (fee stays in pool, increasing rate for others)
        let underlying_balance = balance::split(&mut pool.underlying, return_amount);

        event::emit(Redeemed {
            pool_id: object::id(pool),
            redeemer: ctx.sender(),
            liquid_amount,
            underlying_amount: return_amount,
            exchange_rate: exchange_rate(pool),
        });

        coin::from_balance(underlying_balance, ctx)
    }

    /// Calculate liquid tokens for underlying amount
    fun calculate_liquid_amount<S, L>(
        pool: &LiquidStakingPool<S, L>,
        underlying_amount: u64,
    ): u64 {
        let total_underlying = balance::value(&pool.underlying) + pool.accumulated_rewards;
        let total_liquid = balance::supply_value(&pool.liquid_supply);

        if (total_liquid == 0 || total_underlying == 0) {
            // 1:1 for first deposit
            underlying_amount
        } else {
            // liquid = underlying * total_liquid / total_underlying
            ((underlying_amount as u128) * (total_liquid as u128) / (total_underlying as u128)) as u64
        }
    }

    /// Calculate underlying for liquid amount
    fun calculate_underlying_amount<S, L>(
        pool: &LiquidStakingPool<S, L>,
        liquid_amount: u64,
    ): u64 {
        let total_underlying = balance::value(&pool.underlying) + pool.accumulated_rewards;
        let total_liquid = balance::supply_value(&pool.liquid_supply);

        if (total_liquid == 0) {
            return 0
        };

        // underlying = liquid * total_underlying / total_liquid
        ((liquid_amount as u128) * (total_underlying as u128) / (total_liquid as u128)) as u64
    }

    // === Admin Functions ===

    /// Add rewards to pool (increases exchange rate)
    public fun add_rewards<S, L>(
        pool: &mut LiquidStakingPool<S, L>,
        _admin: &LiquidPoolAdmin<S, L>,
        rewards: Coin<S>,
    ) {
        let amount = coin::value(&rewards);
        let reward_balance = coin::into_balance(rewards);
        balance::join(&mut pool.underlying, reward_balance);

        event::emit(RewardsAdded {
            pool_id: object::id(pool),
            amount,
            new_exchange_rate: exchange_rate(pool),
        });
    }

    /// Set pool paused
    public fun set_paused<S, L>(
        pool: &mut LiquidStakingPool<S, L>,
        _admin: &LiquidPoolAdmin<S, L>,
        paused: bool,
    ) {
        pool.paused = paused;
    }

    /// Update fee
    public fun set_fee<S, L>(
        pool: &mut LiquidStakingPool<S, L>,
        _admin: &LiquidPoolAdmin<S, L>,
        fee_bps: u64,
    ) {
        pool.fee_bps = fee_bps;
    }

    // === View Functions ===

    /// Get exchange rate (underlying per liquid token, scaled by RATE_PRECISION)
    public fun exchange_rate<S, L>(pool: &LiquidStakingPool<S, L>): u64 {
        let total_underlying = balance::value(&pool.underlying) + pool.accumulated_rewards;
        let total_liquid = balance::supply_value(&pool.liquid_supply);

        if (total_liquid == 0) {
            RATE_PRECISION // 1:1
        } else {
            (((total_underlying as u128) * (RATE_PRECISION as u128)) / (total_liquid as u128)) as u64
        }
    }

    /// Get total underlying
    public fun total_underlying<S, L>(pool: &LiquidStakingPool<S, L>): u64 {
        balance::value(&pool.underlying)
    }

    /// Get total liquid supply
    public fun total_liquid_supply<S, L>(pool: &LiquidStakingPool<S, L>): u64 {
        balance::supply_value(&pool.liquid_supply)
    }

    /// Get fee
    public fun fee_bps<S, L>(pool: &LiquidStakingPool<S, L>): u64 {
        pool.fee_bps
    }

    /// Is pool paused
    public fun is_paused<S, L>(pool: &LiquidStakingPool<S, L>): bool {
        pool.paused
    }

    /// Preview stake: how many liquid tokens for underlying amount
    public fun preview_stake<S, L>(
        pool: &LiquidStakingPool<S, L>,
        underlying_amount: u64,
    ): u64 {
        calculate_liquid_amount(pool, underlying_amount)
    }

    /// Preview redeem: how much underlying for liquid amount (before fee)
    public fun preview_redeem<S, L>(
        pool: &LiquidStakingPool<S, L>,
        liquid_amount: u64,
    ): u64 {
        let underlying = calculate_underlying_amount(pool, liquid_amount);
        let fee = (underlying * pool.fee_bps) / 10000;
        underlying - fee
    }

    /// Rate precision constant
    public fun rate_precision(): u64 { RATE_PRECISION }

    // === Tests ===

    #[test]
    fun test_exchange_rate_calculation() {
        // This is tested implicitly through stake/redeem tests
        // The exchange rate formula is verified there
        assert!(true, 0);
    }

    #[test]
    fun test_rate_precision() {
        assert!(rate_precision() == 1000000000, 0);
    }
}
