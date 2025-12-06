/// @title Staking Pool
/// @notice Generic staking pool with reward distribution
/// @dev Part of @sui-starters/defi package
module sui_starters_defi::staking {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use sui::event;

    // === Errors ===

    /// No stake found
    const ENoStake: u64 = 0;

    /// Insufficient stake
    const EInsufficientStake: u64 = 1;

    /// Pool is paused
    const EPoolPaused: u64 = 2;

    /// Lockup not expired
    const ELockupNotExpired: u64 = 3;

    /// Invalid amount
    const EInvalidAmount: u64 = 4;

    /// No rewards available
    const ENoRewards: u64 = 5;

    // === Constants ===

    /// Precision for reward calculations
    const PRECISION: u128 = 1000000000000; // 10^12

    // === Structs ===

    /// Staking pool for a token pair (stake T, earn R)
    public struct StakingPool<phantom T, phantom R> has key, store {
        id: UID,
        /// Total staked tokens
        total_staked: Balance<T>,
        /// Reward tokens available
        reward_balance: Balance<R>,
        /// Accumulated reward per share (scaled by PRECISION)
        acc_reward_per_share: u128,
        /// Reward rate per second (scaled by PRECISION)
        reward_rate: u128,
        /// Last reward update timestamp
        last_reward_time: u64,
        /// Pool end time (0 = no end)
        end_time: u64,
        /// Minimum lockup duration in ms
        min_lockup: u64,
        /// Is pool paused
        paused: bool,
    }

    /// User stake position
    public struct StakePosition<phantom T, phantom R> has key, store {
        id: UID,
        /// Pool ID reference
        pool_id: ID,
        /// Staked amount
        amount: u64,
        /// Reward debt for calculating pending rewards
        reward_debt: u128,
        /// Stake start time
        stake_time: u64,
        /// Lockup end time
        lockup_end: u64,
    }

    /// Pool configuration
    public struct PoolConfig has copy, drop {
        total_staked: u64,
        reward_balance: u64,
        reward_rate: u128,
        min_lockup: u64,
        paused: bool,
    }

    // === Events ===

    /// Emitted when tokens are staked
    public struct Staked has copy, drop {
        pool_id: ID,
        user: address,
        amount: u64,
        lockup_end: u64,
    }

    /// Emitted when tokens are unstaked
    public struct Unstaked has copy, drop {
        pool_id: ID,
        user: address,
        amount: u64,
    }

    /// Emitted when rewards are claimed
    public struct RewardsClaimed has copy, drop {
        pool_id: ID,
        user: address,
        amount: u64,
    }

    /// Emitted when rewards are added
    public struct RewardsAdded has copy, drop {
        pool_id: ID,
        amount: u64,
        new_rate: u128,
    }

    // === Create Functions ===

    /// Create a new staking pool
    public fun new<T, R>(
        reward_rate: u128,
        min_lockup: u64,
        end_time: u64,
        ctx: &mut TxContext,
    ): StakingPool<T, R> {
        StakingPool<T, R> {
            id: object::new(ctx),
            total_staked: balance::zero(),
            reward_balance: balance::zero(),
            acc_reward_per_share: 0,
            reward_rate,
            last_reward_time: 0,
            end_time,
            min_lockup,
            paused: false,
        }
    }

    /// Create pool with no lockup
    public fun new_no_lockup<T, R>(
        reward_rate: u128,
        ctx: &mut TxContext,
    ): StakingPool<T, R> {
        new(reward_rate, 0, 0, ctx)
    }

    // === Stake Functions ===

    /// Stake tokens into the pool
    public fun stake<T, R>(
        pool: &mut StakingPool<T, R>,
        tokens: Coin<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): StakePosition<T, R> {
        assert!(!pool.paused, EPoolPaused);

        let amount = coin::value(&tokens);
        assert!(amount > 0, EInvalidAmount);

        let now = sui::clock::timestamp_ms(clock);

        // Update pool rewards before staking
        update_pool(pool, now);

        // Add stake
        balance::join(&mut pool.total_staked, coin::into_balance(tokens));

        // Calculate lockup end
        let lockup_end = now + pool.min_lockup;

        // Calculate reward debt
        let reward_debt = (amount as u128) * pool.acc_reward_per_share / PRECISION;

        let position = StakePosition<T, R> {
            id: object::new(ctx),
            pool_id: object::id(pool),
            amount,
            reward_debt,
            stake_time: now,
            lockup_end,
        };

        event::emit(Staked {
            pool_id: object::id(pool),
            user: ctx.sender(),
            amount,
            lockup_end,
        });

        position
    }

    /// Unstake tokens from the pool
    public fun unstake<T, R>(
        pool: &mut StakingPool<T, R>,
        position: StakePosition<T, R>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Coin<T>, Coin<R>) {
        assert!(!pool.paused, EPoolPaused);

        let now = sui::clock::timestamp_ms(clock);
        assert!(now >= position.lockup_end, ELockupNotExpired);

        // Update pool rewards
        update_pool(pool, now);

        let StakePosition {
            id,
            pool_id: _,
            amount,
            reward_debt,
            stake_time: _,
            lockup_end: _,
        } = position;
        object::delete(id);

        // Calculate pending rewards
        let pending = calculate_pending(pool, amount, reward_debt);

        // Withdraw stake
        let staked_tokens = coin::from_balance(
            balance::split(&mut pool.total_staked, amount),
            ctx,
        );

        // Withdraw rewards
        let reward_amount = if (pending > balance::value(&pool.reward_balance)) {
            balance::value(&pool.reward_balance)
        } else {
            pending
        };

        let reward_tokens = if (reward_amount > 0) {
            coin::from_balance(
                balance::split(&mut pool.reward_balance, reward_amount),
                ctx,
            )
        } else {
            coin::zero(ctx)
        };

        event::emit(Unstaked {
            pool_id: object::id(pool),
            user: ctx.sender(),
            amount,
        });

        if (reward_amount > 0) {
            event::emit(RewardsClaimed {
                pool_id: object::id(pool),
                user: ctx.sender(),
                amount: reward_amount,
            });
        };

        (staked_tokens, reward_tokens)
    }

    /// Claim rewards without unstaking
    public fun claim_rewards<T, R>(
        pool: &mut StakingPool<T, R>,
        position: &mut StakePosition<T, R>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<R> {
        let now = sui::clock::timestamp_ms(clock);

        // Update pool rewards
        update_pool(pool, now);

        // Calculate pending rewards
        let pending = calculate_pending(pool, position.amount, position.reward_debt);
        assert!(pending > 0, ENoRewards);

        // Update reward debt
        position.reward_debt = (position.amount as u128) * pool.acc_reward_per_share / PRECISION;

        // Withdraw rewards
        let reward_amount = if (pending > balance::value(&pool.reward_balance)) {
            balance::value(&pool.reward_balance)
        } else {
            pending
        };

        let reward_tokens = coin::from_balance(
            balance::split(&mut pool.reward_balance, reward_amount),
            ctx,
        );

        event::emit(RewardsClaimed {
            pool_id: object::id(pool),
            user: ctx.sender(),
            amount: reward_amount,
        });

        reward_tokens
    }

    /// Add more stake to existing position
    public fun add_stake<T, R>(
        pool: &mut StakingPool<T, R>,
        position: &mut StakePosition<T, R>,
        tokens: Coin<T>,
        clock: &Clock,
    ) {
        assert!(!pool.paused, EPoolPaused);

        let amount = coin::value(&tokens);
        assert!(amount > 0, EInvalidAmount);

        let now = sui::clock::timestamp_ms(clock);

        // Update pool rewards
        update_pool(pool, now);

        // Claim pending rewards to position's debt (compound)
        let pending = calculate_pending(pool, position.amount, position.reward_debt);

        // Add new stake
        position.amount = position.amount + amount;
        balance::join(&mut pool.total_staked, coin::into_balance(tokens));

        // Update reward debt (include pending)
        position.reward_debt = (position.amount as u128) * pool.acc_reward_per_share / PRECISION - (pending as u128);

        // Extend lockup
        let new_lockup_end = now + pool.min_lockup;
        if (new_lockup_end > position.lockup_end) {
            position.lockup_end = new_lockup_end;
        };
    }

    // === Admin Functions ===

    /// Add rewards to the pool
    public fun add_rewards<T, R>(
        pool: &mut StakingPool<T, R>,
        rewards: Coin<R>,
        clock: &Clock,
    ) {
        let now = sui::clock::timestamp_ms(clock);
        update_pool(pool, now);

        let amount = coin::value(&rewards);
        balance::join(&mut pool.reward_balance, coin::into_balance(rewards));

        event::emit(RewardsAdded {
            pool_id: object::id(pool),
            amount,
            new_rate: pool.reward_rate,
        });
    }

    /// Set reward rate
    public fun set_reward_rate<T, R>(
        pool: &mut StakingPool<T, R>,
        rate: u128,
        clock: &Clock,
    ) {
        let now = sui::clock::timestamp_ms(clock);
        update_pool(pool, now);
        pool.reward_rate = rate;
    }

    /// Set end time
    public fun set_end_time<T, R>(pool: &mut StakingPool<T, R>, end_time: u64) {
        pool.end_time = end_time;
    }

    /// Set minimum lockup
    public fun set_min_lockup<T, R>(pool: &mut StakingPool<T, R>, min_lockup: u64) {
        pool.min_lockup = min_lockup;
    }

    /// Pause pool
    public fun pause<T, R>(pool: &mut StakingPool<T, R>) {
        pool.paused = true;
    }

    /// Unpause pool
    public fun unpause<T, R>(pool: &mut StakingPool<T, R>) {
        pool.paused = false;
    }

    // === Internal Functions ===

    /// Update pool accumulated rewards
    fun update_pool<T, R>(pool: &mut StakingPool<T, R>, now: u64) {
        if (pool.last_reward_time == 0) {
            pool.last_reward_time = now;
            return
        };

        let total_staked = balance::value(&pool.total_staked);
        if (total_staked == 0) {
            pool.last_reward_time = now;
            return
        };

        // Check if pool has ended
        let end_time = if (pool.end_time > 0 && pool.end_time < now) {
            pool.end_time
        } else {
            now
        };

        if (end_time <= pool.last_reward_time) {
            return
        };

        // Calculate time elapsed (in seconds for reward calculation)
        let time_elapsed = (end_time - pool.last_reward_time) / 1000; // ms to seconds
        if (time_elapsed == 0) {
            return
        };

        // Calculate rewards
        let rewards = pool.reward_rate * (time_elapsed as u128);

        // Update accumulated reward per share
        pool.acc_reward_per_share = pool.acc_reward_per_share +
            rewards * PRECISION / (total_staked as u128);

        pool.last_reward_time = now;
    }

    /// Calculate pending rewards for a position
    fun calculate_pending<T, R>(
        pool: &StakingPool<T, R>,
        amount: u64,
        reward_debt: u128,
    ): u64 {
        let accumulated = (amount as u128) * pool.acc_reward_per_share / PRECISION;
        if (accumulated > reward_debt) {
            ((accumulated - reward_debt) as u64)
        } else {
            0
        }
    }

    // === View Functions ===

    /// Get pending rewards for a position
    public fun pending_rewards<T, R>(
        pool: &StakingPool<T, R>,
        position: &StakePosition<T, R>,
        clock: &Clock,
    ): u64 {
        let now = sui::clock::timestamp_ms(clock);
        let total_staked = balance::value(&pool.total_staked);

        if (total_staked == 0) {
            return 0
        };

        // Simulate pool update
        let mut acc_reward_per_share = pool.acc_reward_per_share;
        let last_time = pool.last_reward_time;

        if (now > last_time && last_time > 0) {
            let end_time = if (pool.end_time > 0 && pool.end_time < now) {
                pool.end_time
            } else {
                now
            };

            if (end_time > last_time) {
                let time_elapsed = (end_time - last_time) / 1000;
                let rewards = pool.reward_rate * (time_elapsed as u128);
                acc_reward_per_share = acc_reward_per_share +
                    rewards * PRECISION / (total_staked as u128);
            };
        };

        let accumulated = (position.amount as u128) * acc_reward_per_share / PRECISION;
        if (accumulated > position.reward_debt) {
            ((accumulated - position.reward_debt) as u64)
        } else {
            0
        }
    }

    /// Get total staked
    public fun total_staked<T, R>(pool: &StakingPool<T, R>): u64 {
        balance::value(&pool.total_staked)
    }

    /// Get reward balance
    public fun reward_balance<T, R>(pool: &StakingPool<T, R>): u64 {
        balance::value(&pool.reward_balance)
    }

    /// Get reward rate
    public fun reward_rate<T, R>(pool: &StakingPool<T, R>): u128 {
        pool.reward_rate
    }

    /// Get pool config
    public fun get_config<T, R>(pool: &StakingPool<T, R>): PoolConfig {
        PoolConfig {
            total_staked: balance::value(&pool.total_staked),
            reward_balance: balance::value(&pool.reward_balance),
            reward_rate: pool.reward_rate,
            min_lockup: pool.min_lockup,
            paused: pool.paused,
        }
    }

    /// Get position amount
    public fun position_amount<T, R>(position: &StakePosition<T, R>): u64 {
        position.amount
    }

    /// Get position lockup end
    public fun position_lockup_end<T, R>(position: &StakePosition<T, R>): u64 {
        position.lockup_end
    }

    /// Get position stake time
    public fun position_stake_time<T, R>(position: &StakePosition<T, R>): u64 {
        position.stake_time
    }

    /// Check if position is locked
    public fun is_locked<T, R>(position: &StakePosition<T, R>, clock: &Clock): bool {
        let now = sui::clock::timestamp_ms(clock);
        now < position.lockup_end
    }

    /// Get precision constant
    public fun precision(): u128 {
        PRECISION
    }

    // === Tests ===

    #[test]
    fun test_create_pool() {
        use sui::test_scenario;
        use sui::sui::SUI;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new_no_lockup<SUI, SUI>(1000000, scenario.ctx());

            assert!(total_staked(&pool) == 0, 0);
            assert!(reward_rate(&pool) == 1000000, 1);

            transfer::public_share_object(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_stake_unstake() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new_no_lockup<SUI, SUI>(0, scenario.ctx()); // No rewards for simple test
            transfer::public_share_object(pool);
        };

        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<StakingPool<SUI, SUI>>();
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let stake_coins = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let position = stake(&mut pool, stake_coins, &test_clock, scenario.ctx());

            assert!(total_staked(&pool) == 1000, 0);
            assert!(position_amount(&position) == 1000, 1);

            // Unstake
            let (staked, rewards) = unstake(&mut pool, position, &test_clock, scenario.ctx());

            assert!(coin::value(&staked) == 1000, 2);
            assert!(coin::value(&rewards) == 0, 3);
            assert!(total_staked(&pool) == 0, 4);

            coin::burn_for_testing(staked);
            coin::burn_for_testing(rewards);
            clock::destroy_for_testing(test_clock);
            test_scenario::return_shared(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_stake_with_lockup() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            // 5 second lockup
            let pool = new<SUI, SUI>(0, 5000, 0, scenario.ctx());
            transfer::public_share_object(pool);
        };

        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<StakingPool<SUI, SUI>>();
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let stake_coins = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let position = stake(&mut pool, stake_coins, &test_clock, scenario.ctx());

            assert!(position_lockup_end(&position) == 6000, 0); // 1000 + 5000
            assert!(is_locked(&position, &test_clock), 1);

            // Move time past lockup
            clock::set_for_testing(&mut test_clock, 7000);
            assert!(!is_locked(&position, &test_clock), 2);

            // Now can unstake
            let (staked, rewards) = unstake(&mut pool, position, &test_clock, scenario.ctx());

            coin::burn_for_testing(staked);
            coin::burn_for_testing(rewards);
            clock::destroy_for_testing(test_clock);
            test_scenario::return_shared(pool);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ELockupNotExpired)]
    fun test_unstake_locked_fails() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new<SUI, SUI>(0, 5000, 0, scenario.ctx());
            transfer::public_share_object(pool);
        };

        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<StakingPool<SUI, SUI>>();
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let stake_coins = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let position = stake(&mut pool, stake_coins, &test_clock, scenario.ctx());

            // Try to unstake before lockup ends (should fail)
            clock::set_for_testing(&mut test_clock, 3000);
            let (staked, rewards) = unstake(&mut pool, position, &test_clock, scenario.ctx());

            coin::burn_for_testing(staked);
            coin::burn_for_testing(rewards);
            clock::destroy_for_testing(test_clock);
            test_scenario::return_shared(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_add_rewards() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new_no_lockup<SUI, SUI>(1000000, scenario.ctx());
            transfer::public_share_object(pool);
        };

        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<StakingPool<SUI, SUI>>();
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let reward_coins = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            add_rewards(&mut pool, reward_coins, &test_clock);

            assert!(reward_balance(&pool) == 10000, 0);

            clock::destroy_for_testing(test_clock);
            test_scenario::return_shared(pool);
        };

        scenario.end();
    }
}
