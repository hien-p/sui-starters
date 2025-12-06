/// @title Reward Distribution
/// @notice Reward calculation and distribution utilities
/// @dev Part of @sui-starters/defi package
module sui_starters_defi::rewards {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;

    // === Errors ===

    /// No rewards to claim
    const ENoRewards: u64 = 0;

    /// Invalid reward rate
    const EInvalidRate: u64 = 1;

    /// Pool is paused
    const EPoolPaused: u64 = 2;

    /// Insufficient rewards
    const EInsufficientRewards: u64 = 3;

    // === Constants ===

    /// Precision for reward per share calculations
    const PRECISION: u128 = 1_000_000_000_000; // 10^12

    // === Structs ===

    /// Reward pool configuration
    public struct RewardPool<phantom S, phantom R> has key, store {
        id: UID,
        /// Total staked amount
        total_staked: u64,
        /// Reward tokens available
        reward_balance: Balance<R>,
        /// Accumulated reward per share (scaled by PRECISION)
        acc_reward_per_share: u128,
        /// Reward rate per second
        reward_per_second: u64,
        /// Last update timestamp
        last_update_time: u64,
        /// End time for rewards
        end_time: u64,
        /// Is pool paused
        paused: bool,
    }

    /// User stake info
    public struct UserStake<phantom S, phantom R> has key, store {
        id: UID,
        /// Pool ID
        pool_id: ID,
        /// User address
        user: address,
        /// Staked amount
        amount: u64,
        /// Reward debt (for reward calculation)
        reward_debt: u128,
    }

    // === Events ===

    /// Emitted when rewards are claimed
    public struct RewardsClaimed<phantom S, phantom R> has copy, drop {
        pool_id: ID,
        user: address,
        amount: u64,
    }

    /// Emitted when rewards are added
    public struct RewardsAdded<phantom S, phantom R> has copy, drop {
        pool_id: ID,
        amount: u64,
        new_end_time: u64,
    }

    /// Emitted when reward rate is updated
    public struct RewardRateUpdated<phantom S, phantom R> has copy, drop {
        pool_id: ID,
        old_rate: u64,
        new_rate: u64,
    }

    // === Create Functions ===

    /// Create a new reward pool
    public fun new_pool<S, R>(
        reward_per_second: u64,
        end_time: u64,
        ctx: &mut TxContext,
    ): RewardPool<S, R> {
        RewardPool<S, R> {
            id: object::new(ctx),
            total_staked: 0,
            reward_balance: balance::zero(),
            acc_reward_per_share: 0,
            reward_per_second,
            last_update_time: 0,
            end_time,
            paused: false,
        }
    }

    /// Create user stake
    public fun new_stake<S, R>(
        pool: &RewardPool<S, R>,
        ctx: &mut TxContext,
    ): UserStake<S, R> {
        UserStake<S, R> {
            id: object::new(ctx),
            pool_id: object::id(pool),
            user: ctx.sender(),
            amount: 0,
            reward_debt: 0,
        }
    }

    // === Core Functions ===

    /// Update pool rewards
    public fun update_pool<S, R>(
        pool: &mut RewardPool<S, R>,
        current_time: u64,
    ) {
        if (current_time <= pool.last_update_time) {
            return
        };

        if (pool.total_staked == 0) {
            pool.last_update_time = current_time;
            return
        };

        let time_elapsed = if (current_time > pool.end_time) {
            if (pool.last_update_time >= pool.end_time) {
                0
            } else {
                pool.end_time - pool.last_update_time
            }
        } else {
            current_time - pool.last_update_time
        };

        if (time_elapsed > 0) {
            let rewards = (time_elapsed as u128) * (pool.reward_per_second as u128);
            pool.acc_reward_per_share = pool.acc_reward_per_share +
                (rewards * PRECISION / (pool.total_staked as u128));
        };

        pool.last_update_time = current_time;
    }

    /// Calculate pending rewards for a user
    public fun pending_rewards<S, R>(
        pool: &RewardPool<S, R>,
        stake: &UserStake<S, R>,
        current_time: u64,
    ): u64 {
        let mut acc_reward = pool.acc_reward_per_share;

        if (current_time > pool.last_update_time && pool.total_staked > 0) {
            let time_elapsed = if (current_time > pool.end_time) {
                if (pool.last_update_time >= pool.end_time) {
                    0
                } else {
                    pool.end_time - pool.last_update_time
                }
            } else {
                current_time - pool.last_update_time
            };

            if (time_elapsed > 0) {
                let rewards = (time_elapsed as u128) * (pool.reward_per_second as u128);
                acc_reward = acc_reward + (rewards * PRECISION / (pool.total_staked as u128));
            };
        };

        let pending = ((stake.amount as u128) * acc_reward / PRECISION) - stake.reward_debt;
        (pending as u64)
    }

    /// Deposit stake
    public fun deposit<S, R>(
        pool: &mut RewardPool<S, R>,
        stake: &mut UserStake<S, R>,
        amount: u64,
        current_time: u64,
    ) {
        assert!(!pool.paused, EPoolPaused);

        update_pool(pool, current_time);

        // Claim pending rewards first
        if (stake.amount > 0) {
            let pending = ((stake.amount as u128) * pool.acc_reward_per_share / PRECISION) - stake.reward_debt;
            // Rewards would be claimed here in full implementation
            let _ = pending;
        };

        stake.amount = stake.amount + amount;
        pool.total_staked = pool.total_staked + amount;

        stake.reward_debt = (stake.amount as u128) * pool.acc_reward_per_share / PRECISION;
    }

    /// Withdraw stake
    public fun withdraw<S, R>(
        pool: &mut RewardPool<S, R>,
        stake: &mut UserStake<S, R>,
        amount: u64,
        current_time: u64,
    ): u64 {
        assert!(stake.amount >= amount, ENoRewards);

        update_pool(pool, current_time);

        // Calculate pending rewards
        let pending = ((stake.amount as u128) * pool.acc_reward_per_share / PRECISION) - stake.reward_debt;

        stake.amount = stake.amount - amount;
        pool.total_staked = pool.total_staked - amount;

        stake.reward_debt = (stake.amount as u128) * pool.acc_reward_per_share / PRECISION;

        (pending as u64)
    }

    /// Claim rewards
    public fun claim_rewards<S, R>(
        pool: &mut RewardPool<S, R>,
        stake: &mut UserStake<S, R>,
        current_time: u64,
        ctx: &mut TxContext,
    ): Coin<R> {
        update_pool(pool, current_time);

        let pending = ((stake.amount as u128) * pool.acc_reward_per_share / PRECISION) - stake.reward_debt;
        let pending_u64 = (pending as u64);

        assert!(pending_u64 > 0, ENoRewards);
        assert!(balance::value(&pool.reward_balance) >= pending_u64, EInsufficientRewards);

        stake.reward_debt = (stake.amount as u128) * pool.acc_reward_per_share / PRECISION;

        event::emit(RewardsClaimed<S, R> {
            pool_id: object::id(pool),
            user: stake.user,
            amount: pending_u64,
        });

        coin::from_balance(balance::split(&mut pool.reward_balance, pending_u64), ctx)
    }

    /// Add rewards to pool
    public fun add_rewards<S, R>(
        pool: &mut RewardPool<S, R>,
        rewards: Coin<R>,
        new_end_time: u64,
    ) {
        let amount = coin::value(&rewards);
        balance::join(&mut pool.reward_balance, coin::into_balance(rewards));

        if (new_end_time > pool.end_time) {
            pool.end_time = new_end_time;
        };

        event::emit(RewardsAdded<S, R> {
            pool_id: object::id(pool),
            amount,
            new_end_time: pool.end_time,
        });
    }

    /// Update reward rate
    public fun set_reward_rate<S, R>(
        pool: &mut RewardPool<S, R>,
        new_rate: u64,
        current_time: u64,
    ) {
        update_pool(pool, current_time);

        let old_rate = pool.reward_per_second;
        pool.reward_per_second = new_rate;

        event::emit(RewardRateUpdated<S, R> {
            pool_id: object::id(pool),
            old_rate,
            new_rate,
        });
    }

    // === Admin Functions ===

    /// Pause pool
    public fun pause<S, R>(pool: &mut RewardPool<S, R>) {
        pool.paused = true;
    }

    /// Unpause pool
    public fun unpause<S, R>(pool: &mut RewardPool<S, R>) {
        pool.paused = false;
    }

    // === View Functions ===

    /// Get pool info
    public fun pool_info<S, R>(pool: &RewardPool<S, R>): (u64, u64, u64, u64, bool) {
        (
            pool.total_staked,
            balance::value(&pool.reward_balance),
            pool.reward_per_second,
            pool.end_time,
            pool.paused,
        )
    }

    /// Get stake info
    public fun stake_info<S, R>(stake: &UserStake<S, R>): (address, u64) {
        (stake.user, stake.amount)
    }

    /// Get total staked
    public fun total_staked<S, R>(pool: &RewardPool<S, R>): u64 {
        pool.total_staked
    }

    /// Get reward balance
    public fun reward_balance<S, R>(pool: &RewardPool<S, R>): u64 {
        balance::value(&pool.reward_balance)
    }

    /// Is pool active
    public fun is_active<S, R>(pool: &RewardPool<S, R>, current_time: u64): bool {
        !pool.paused && current_time < pool.end_time
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::sui::SUI;

    #[test]
    fun test_create_pool() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new_pool<SUI, SUI>(
                1000,       // 1000 per second
                1000000,    // end time
                scenario.ctx(),
            );

            let (staked, balance, rate, end, paused) = pool_info(&pool);
            assert!(staked == 0, 0);
            assert!(balance == 0, 1);
            assert!(rate == 1000, 2);
            assert!(end == 1000000, 3);
            assert!(!paused, 4);

            transfer::public_share_object(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_deposit_withdraw() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut pool = new_pool<SUI, SUI>(1000, 1000000, scenario.ctx());
            let mut stake = new_stake(&pool, scenario.ctx());

            // Deposit
            deposit(&mut pool, &mut stake, 1000, 100);
            assert!(total_staked(&pool) == 1000, 0);

            let (_, amount) = stake_info(&stake);
            assert!(amount == 1000, 1);

            // Withdraw
            let _pending = withdraw(&mut pool, &mut stake, 500, 200);
            assert!(total_staked(&pool) == 500, 2);

            transfer::public_share_object(pool);
            transfer::public_transfer(stake, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_pending_rewards() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut pool = new_pool<SUI, SUI>(
                1000,       // 1000 per second
                1000000,
                scenario.ctx(),
            );
            let mut stake = new_stake(&pool, scenario.ctx());

            // Initialize last_update_time
            pool.last_update_time = 0;

            // Deposit
            deposit(&mut pool, &mut stake, 1000, 0);

            // Check pending after some time
            let pending = pending_rewards(&pool, &stake, 100);
            // Should have 100 seconds * 1000 rate = 100000 rewards
            assert!(pending == 100000, 0);

            transfer::public_share_object(pool);
            transfer::public_transfer(stake, admin);
        };

        scenario.end();
    }
}
