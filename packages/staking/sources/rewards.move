/// @title Staking Rewards
/// @notice Reward calculation and distribution
/// @dev Part of @sui-starters/staking package
module sui_starters_staking::rewards {
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};

    // === Errors ===

    const EInsufficientRewards: u64 = 0;
    const EDistributionEnded: u64 = 1;

    // === Structs ===

    /// Reward distributor
    public struct RewardDistributor<phantom R> has key, store {
        id: UID,
        /// Reward token balance
        rewards: Balance<R>,
        /// Total distributed
        total_distributed: u64,
        /// Distribution rate per epoch
        rate_per_epoch: u64,
        /// Start epoch
        start_epoch: u64,
        /// End epoch (0 = infinite)
        end_epoch: u64,
        /// Last distribution epoch
        last_distribution_epoch: u64,
    }

    /// Reward accumulator (tracks per-share rewards)
    public struct RewardAccumulator has store, copy, drop {
        /// Accumulated reward per share (scaled by 1e12)
        acc_reward_per_share: u128,
        /// Total shares
        total_shares: u64,
        /// Last update epoch
        last_update_epoch: u64,
    }

    /// User reward state
    public struct UserRewardState has store, copy, drop {
        /// User shares
        shares: u64,
        /// Reward debt (for accurate calculation)
        reward_debt: u128,
        /// Pending rewards
        pending: u64,
    }

    // === Events ===

    public struct RewardsDistributed has copy, drop {
        amount: u64,
        epoch: u64,
    }

    public struct RewardClaimed has copy, drop {
        user: address,
        amount: u64,
    }

    // === Constants ===

    const PRECISION: u128 = 1000000000000; // 1e12

    // === Create Functions ===

    /// Create reward distributor
    public fun new_distributor<R>(
        rate_per_epoch: u64,
        end_epoch: u64,
        ctx: &mut TxContext,
    ): RewardDistributor<R> {
        RewardDistributor {
            id: object::new(ctx),
            rewards: balance::zero(),
            total_distributed: 0,
            rate_per_epoch,
            start_epoch: ctx.epoch(),
            end_epoch,
            last_distribution_epoch: ctx.epoch(),
        }
    }

    /// Create reward accumulator
    public fun new_accumulator(): RewardAccumulator {
        RewardAccumulator {
            acc_reward_per_share: 0,
            total_shares: 0,
            last_update_epoch: 0,
        }
    }

    /// Create user reward state
    public fun new_user_state(): UserRewardState {
        UserRewardState {
            shares: 0,
            reward_debt: 0,
            pending: 0,
        }
    }

    // === Core Functions ===

    /// Add rewards to distributor
    public fun add_rewards<R>(
        distributor: &mut RewardDistributor<R>,
        rewards: Coin<R>,
    ) {
        let reward_balance = coin::into_balance(rewards);
        balance::join(&mut distributor.rewards, reward_balance);
    }

    /// Update accumulator (call before any share changes)
    public fun update_accumulator(
        acc: &mut RewardAccumulator,
        reward_amount: u64,
        current_epoch: u64,
    ) {
        if (acc.total_shares == 0 || current_epoch <= acc.last_update_epoch) {
            acc.last_update_epoch = current_epoch;
            return
        };

        if (reward_amount > 0) {
            let reward_per_share = ((reward_amount as u128) * PRECISION) / (acc.total_shares as u128);
            acc.acc_reward_per_share = acc.acc_reward_per_share + reward_per_share;
        };

        acc.last_update_epoch = current_epoch;
    }

    /// Add shares to accumulator
    public fun add_shares(
        acc: &mut RewardAccumulator,
        user_state: &mut UserRewardState,
        amount: u64,
    ) {
        // Calculate pending before adding shares
        if (user_state.shares > 0) {
            let pending = calculate_pending(acc, user_state);
            user_state.pending = user_state.pending + pending;
        };

        user_state.shares = user_state.shares + amount;
        acc.total_shares = acc.total_shares + amount;

        // Update debt
        user_state.reward_debt = (user_state.shares as u128) * acc.acc_reward_per_share;
    }

    /// Remove shares from accumulator
    public fun remove_shares(
        acc: &mut RewardAccumulator,
        user_state: &mut UserRewardState,
        amount: u64,
    ) {
        // Calculate pending before removing shares
        let pending = calculate_pending(acc, user_state);
        user_state.pending = user_state.pending + pending;

        user_state.shares = user_state.shares - amount;
        acc.total_shares = acc.total_shares - amount;

        // Update debt
        user_state.reward_debt = (user_state.shares as u128) * acc.acc_reward_per_share;
    }

    /// Calculate pending rewards for user
    public fun calculate_pending(
        acc: &RewardAccumulator,
        user_state: &UserRewardState,
    ): u64 {
        if (user_state.shares == 0) {
            return 0
        };

        let accumulated = (user_state.shares as u128) * acc.acc_reward_per_share;
        let pending = (accumulated - user_state.reward_debt) / PRECISION;
        (pending as u64)
    }

    /// Claim rewards
    public fun claim<R>(
        distributor: &mut RewardDistributor<R>,
        acc: &RewardAccumulator,
        user_state: &mut UserRewardState,
        ctx: &mut TxContext,
    ): Coin<R> {
        let pending = calculate_pending(acc, user_state);
        let total_claimable = pending + user_state.pending;

        assert!(balance::value(&distributor.rewards) >= total_claimable, EInsufficientRewards);

        user_state.pending = 0;
        user_state.reward_debt = (user_state.shares as u128) * acc.acc_reward_per_share;

        distributor.total_distributed = distributor.total_distributed + total_claimable;

        let rewards = balance::split(&mut distributor.rewards, total_claimable);

        event::emit(RewardClaimed {
            user: ctx.sender(),
            amount: total_claimable,
        });

        coin::from_balance(rewards, ctx)
    }

    /// Get distributable rewards for epoch
    public fun get_distributable<R>(
        distributor: &RewardDistributor<R>,
        current_epoch: u64,
    ): u64 {
        if (distributor.end_epoch > 0 && current_epoch > distributor.end_epoch) {
            return 0
        };

        let epochs_elapsed = current_epoch - distributor.last_distribution_epoch;
        let distributable = epochs_elapsed * distributor.rate_per_epoch;
        let available = balance::value(&distributor.rewards);

        if (distributable > available) {
            available
        } else {
            distributable
        }
    }

    // === View Functions ===

    /// Get reward balance
    public fun reward_balance<R>(distributor: &RewardDistributor<R>): u64 {
        balance::value(&distributor.rewards)
    }

    /// Get total distributed
    public fun total_distributed<R>(distributor: &RewardDistributor<R>): u64 {
        distributor.total_distributed
    }

    /// Get accumulator info
    public fun accumulator_info(acc: &RewardAccumulator): (u128, u64) {
        (acc.acc_reward_per_share, acc.total_shares)
    }

    /// Get user state info
    public fun user_state_info(state: &UserRewardState): (u64, u64) {
        (state.shares, state.pending)
    }

    /// Get total pending for user
    public fun total_pending(
        acc: &RewardAccumulator,
        user_state: &UserRewardState,
    ): u64 {
        calculate_pending(acc, user_state) + user_state.pending
    }

    // === Tests ===

    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_distributor() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let distributor = new_distributor<SUI>(1000, 100, scenario.ctx());

            assert!(reward_balance(&distributor) == 0, 0);
            assert!(total_distributed(&distributor) == 0, 1);

            transfer::public_share_object(distributor);
        };

        scenario.end();
    }

    #[test]
    fun test_accumulator() {
        let mut acc = new_accumulator();
        let mut user1 = new_user_state();
        let mut user2 = new_user_state();

        // Add shares
        add_shares(&mut acc, &mut user1, 1000);
        add_shares(&mut acc, &mut user2, 2000);

        let (_, total) = accumulator_info(&acc);
        assert!(total == 3000, 0);

        // Update with rewards
        update_accumulator(&mut acc, 300, 1);

        // User1 should get 100 (1000/3000 * 300)
        // User2 should get 200 (2000/3000 * 300)
        let pending1 = calculate_pending(&acc, &user1);
        let pending2 = calculate_pending(&acc, &user2);

        assert!(pending1 == 100, 1);
        assert!(pending2 == 200, 2);
    }

    #[test]
    fun test_add_remove_shares() {
        let mut acc = new_accumulator();
        let mut user = new_user_state();

        add_shares(&mut acc, &mut user, 1000);
        let (shares, _) = user_state_info(&user);
        assert!(shares == 1000, 0);

        remove_shares(&mut acc, &mut user, 500);
        let (shares_after, _) = user_state_info(&user);
        assert!(shares_after == 500, 1);
    }
}
