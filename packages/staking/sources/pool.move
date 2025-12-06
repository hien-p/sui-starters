/// @title Staking Pool
/// @notice Core staking pool management
/// @dev Part of @sui-starters/staking package
module sui_starters_staking::pool {
    use std::string::String;
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};

    // === Errors ===

    const EPoolPaused: u64 = 0;
    const EInsufficientBalance: u64 = 1;
    const EMinStakeNotMet: u64 = 2;
    const EMaxStakeExceeded: u64 = 3;
    const EPoolFull: u64 = 4;

    // === Structs ===

    /// Staking pool
    public struct StakingPool<phantom S, phantom R> has key, store {
        id: UID,
        name: String,
        /// Staked token balance
        total_staked: Balance<S>,
        /// Reward token balance
        reward_balance: Balance<R>,
        /// Reward rate per epoch (in reward tokens per staked token * 1e9)
        reward_rate: u64,
        /// Minimum stake amount
        min_stake: u64,
        /// Maximum stake amount (0 = no limit)
        max_stake: u64,
        /// Maximum total staked (0 = no limit)
        max_pool_size: u64,
        /// Total stakers
        staker_count: u64,
        /// Is pool paused
        paused: bool,
        /// Pool creation epoch
        created_epoch: u64,
    }

    /// User stake position
    public struct StakePosition<phantom S, phantom R> has key, store {
        id: UID,
        pool_id: ID,
        owner: address,
        /// Staked amount
        staked: Balance<S>,
        /// Accumulated rewards (pending claim)
        pending_rewards: u64,
        /// Last update epoch
        last_update_epoch: u64,
        /// Stake start epoch
        start_epoch: u64,
    }

    /// Admin capability
    public struct PoolAdminCap<phantom S, phantom R> has key, store {
        id: UID,
        pool_id: ID,
    }

    // === Events ===

    public struct PoolCreated has copy, drop {
        pool_id: ID,
        name: String,
        reward_rate: u64,
    }

    public struct Staked has copy, drop {
        pool_id: ID,
        staker: address,
        amount: u64,
        total_staked: u64,
    }

    public struct Unstaked has copy, drop {
        pool_id: ID,
        staker: address,
        amount: u64,
        remaining: u64,
    }

    public struct RewardsClaimed has copy, drop {
        pool_id: ID,
        staker: address,
        amount: u64,
    }

    // === Create Functions ===

    /// Create new staking pool
    public fun new<S, R>(
        name: String,
        reward_rate: u64,
        min_stake: u64,
        max_stake: u64,
        max_pool_size: u64,
        ctx: &mut TxContext,
    ): (StakingPool<S, R>, PoolAdminCap<S, R>) {
        let pool = StakingPool {
            id: object::new(ctx),
            name,
            total_staked: balance::zero(),
            reward_balance: balance::zero(),
            reward_rate,
            min_stake,
            max_stake,
            max_pool_size,
            staker_count: 0,
            paused: false,
            created_epoch: ctx.epoch(),
        };

        let pool_id = object::id(&pool);

        let admin_cap = PoolAdminCap {
            id: object::new(ctx),
            pool_id,
        };

        event::emit(PoolCreated {
            pool_id,
            name: pool.name,
            reward_rate,
        });

        (pool, admin_cap)
    }

    // === Core Functions ===

    /// Stake tokens
    public fun stake<S, R>(
        pool: &mut StakingPool<S, R>,
        tokens: Coin<S>,
        ctx: &mut TxContext,
    ): StakePosition<S, R> {
        assert!(!pool.paused, EPoolPaused);

        let amount = coin::value(&tokens);
        assert!(amount >= pool.min_stake, EMinStakeNotMet);
        if (pool.max_stake > 0) {
            assert!(amount <= pool.max_stake, EMaxStakeExceeded);
        };

        let current_total = balance::value(&pool.total_staked);
        if (pool.max_pool_size > 0) {
            assert!(current_total + amount <= pool.max_pool_size, EPoolFull);
        };

        let token_balance = coin::into_balance(tokens);
        balance::join(&mut pool.total_staked, token_balance);

        pool.staker_count = pool.staker_count + 1;

        let position = StakePosition {
            id: object::new(ctx),
            pool_id: object::id(pool),
            owner: ctx.sender(),
            staked: balance::zero(),
            pending_rewards: 0,
            last_update_epoch: ctx.epoch(),
            start_epoch: ctx.epoch(),
        };

        // Add staked amount to position
        let staked_balance = balance::split(&mut pool.total_staked, amount);
        balance::join(&mut pool.total_staked, staked_balance);

        event::emit(Staked {
            pool_id: object::id(pool),
            staker: ctx.sender(),
            amount,
            total_staked: balance::value(&pool.total_staked),
        });

        position
    }

    /// Add more stake
    public fun add_stake<S, R>(
        pool: &mut StakingPool<S, R>,
        position: &mut StakePosition<S, R>,
        tokens: Coin<S>,
        ctx: &TxContext,
    ) {
        assert!(!pool.paused, EPoolPaused);

        // Update pending rewards first
        update_rewards(pool, position, ctx);

        let amount = coin::value(&tokens);
        let token_balance = coin::into_balance(tokens);

        balance::join(&mut position.staked, token_balance);

        if (pool.max_stake > 0) {
            assert!(balance::value(&position.staked) <= pool.max_stake, EMaxStakeExceeded);
        };

        // Update pool total
        let position_balance = balance::split(&mut position.staked, amount);
        balance::join(&mut pool.total_staked, position_balance);
        balance::join(&mut position.staked, balance::split(&mut pool.total_staked, amount));

        event::emit(Staked {
            pool_id: object::id(pool),
            staker: position.owner,
            amount,
            total_staked: balance::value(&pool.total_staked),
        });
    }

    /// Unstake tokens
    public fun unstake<S, R>(
        pool: &mut StakingPool<S, R>,
        position: &mut StakePosition<S, R>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<S> {
        assert!(balance::value(&position.staked) >= amount, EInsufficientBalance);

        // Update pending rewards first
        update_rewards(pool, position, ctx);

        let unstaked = balance::split(&mut position.staked, amount);

        event::emit(Unstaked {
            pool_id: object::id(pool),
            staker: position.owner,
            amount,
            remaining: balance::value(&position.staked),
        });

        coin::from_balance(unstaked, ctx)
    }

    /// Claim rewards
    public fun claim_rewards<S, R>(
        pool: &mut StakingPool<S, R>,
        position: &mut StakePosition<S, R>,
        ctx: &mut TxContext,
    ): Coin<R> {
        update_rewards(pool, position, ctx);

        let reward_amount = position.pending_rewards;
        assert!(balance::value(&pool.reward_balance) >= reward_amount, EInsufficientBalance);

        position.pending_rewards = 0;

        let rewards = balance::split(&mut pool.reward_balance, reward_amount);

        event::emit(RewardsClaimed {
            pool_id: object::id(pool),
            staker: position.owner,
            amount: reward_amount,
        });

        coin::from_balance(rewards, ctx)
    }

    /// Update pending rewards
    fun update_rewards<S, R>(
        pool: &StakingPool<S, R>,
        position: &mut StakePosition<S, R>,
        ctx: &TxContext,
    ) {
        let current_epoch = ctx.epoch();
        if (current_epoch <= position.last_update_epoch) {
            return
        };

        let epochs_elapsed = current_epoch - position.last_update_epoch;
        let staked_amount = balance::value(&position.staked);

        if (staked_amount > 0) {
            // rewards = staked * rate * epochs / 1e9
            let new_rewards = (staked_amount * pool.reward_rate * epochs_elapsed) / 1000000000;
            position.pending_rewards = position.pending_rewards + new_rewards;
        };

        position.last_update_epoch = current_epoch;
    }

    // === Admin Functions ===

    /// Add rewards to pool
    public fun add_rewards<S, R>(
        pool: &mut StakingPool<S, R>,
        _admin: &PoolAdminCap<S, R>,
        rewards: Coin<R>,
    ) {
        let reward_balance = coin::into_balance(rewards);
        balance::join(&mut pool.reward_balance, reward_balance);
    }

    /// Set pool paused
    public fun set_paused<S, R>(
        pool: &mut StakingPool<S, R>,
        _admin: &PoolAdminCap<S, R>,
        paused: bool,
    ) {
        pool.paused = paused;
    }

    /// Update reward rate
    public fun set_reward_rate<S, R>(
        pool: &mut StakingPool<S, R>,
        _admin: &PoolAdminCap<S, R>,
        rate: u64,
    ) {
        pool.reward_rate = rate;
    }

    // === View Functions ===

    /// Get total staked
    public fun total_staked<S, R>(pool: &StakingPool<S, R>): u64 {
        balance::value(&pool.total_staked)
    }

    /// Get reward balance
    public fun reward_balance<S, R>(pool: &StakingPool<S, R>): u64 {
        balance::value(&pool.reward_balance)
    }

    /// Get staker count
    public fun staker_count<S, R>(pool: &StakingPool<S, R>): u64 {
        pool.staker_count
    }

    /// Get reward rate
    public fun reward_rate<S, R>(pool: &StakingPool<S, R>): u64 {
        pool.reward_rate
    }

    /// Is pool paused
    public fun is_paused<S, R>(pool: &StakingPool<S, R>): bool {
        pool.paused
    }

    /// Get position staked
    public fun position_staked<S, R>(position: &StakePosition<S, R>): u64 {
        balance::value(&position.staked)
    }

    /// Get pending rewards
    public fun pending_rewards<S, R>(position: &StakePosition<S, R>): u64 {
        position.pending_rewards
    }

    /// Get position owner
    public fun position_owner<S, R>(position: &StakePosition<S, R>): address {
        position.owner
    }

    // === Tests ===

    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use std::string;

    #[test]
    fun test_create_pool() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let (pool, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Test Pool"),
                1000000, // 0.001 per epoch per token
                100,
                0,
                0,
                scenario.ctx(),
            );

            assert!(total_staked(&pool) == 0, 0);
            assert!(staker_count(&pool) == 0, 1);
            assert!(!is_paused(&pool), 2);

            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_stake() {
        let admin = @0xAD;
        let staker = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create pool
        {
            let (pool, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Test Pool"),
                1000000,
                100,
                0,
                0,
                scenario.ctx(),
            );
            transfer::public_share_object(pool);
            transfer::public_transfer(admin_cap, admin);
        };

        // Stake
        scenario.next_tx(staker);
        {
            let mut pool = scenario.take_shared<StakingPool<SUI, SUI>>();
            let stake_coin = coin::mint_for_testing<SUI>(1000, scenario.ctx());

            let position = stake(&mut pool, stake_coin, scenario.ctx());

            assert!(staker_count(&pool) == 1, 0);

            transfer::public_transfer(position, staker);
            test_scenario::return_shared(pool);
        };

        scenario.end();
    }
}
