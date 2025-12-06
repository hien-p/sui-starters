/// @title Lockup
/// @notice Time-locked staking with bonus rewards
/// @dev Part of @sui-starters/staking package
module sui_starters_staking::lockup {
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};

    // === Errors ===

    const ELockupNotExpired: u64 = 0;
    const EInvalidDuration: u64 = 1;
    const EAlreadyUnlocked: u64 = 2;

    // === Structs ===

    /// Lockup configuration
    public struct LockupConfig has store, copy, drop {
        /// Minimum lock duration in epochs
        min_duration: u64,
        /// Maximum lock duration in epochs
        max_duration: u64,
        /// Bonus multiplier per epoch locked (in bps, e.g., 10 = 0.1% per epoch)
        bonus_per_epoch: u64,
        /// Maximum bonus (in bps, e.g., 5000 = 50%)
        max_bonus: u64,
    }

    /// Locked stake position
    public struct LockedStake<phantom T> has key, store {
        id: UID,
        owner: address,
        /// Locked tokens
        locked: Balance<T>,
        /// Lock start epoch
        start_epoch: u64,
        /// Lock end epoch
        end_epoch: u64,
        /// Lock duration
        duration: u64,
        /// Bonus rate achieved (in bps)
        bonus_rate: u64,
        /// Is already unlocked
        unlocked: bool,
    }

    // === Events ===

    public struct TokensLocked has copy, drop {
        lock_id: ID,
        owner: address,
        amount: u64,
        duration: u64,
        end_epoch: u64,
        bonus_rate: u64,
    }

    public struct TokensUnlocked has copy, drop {
        lock_id: ID,
        owner: address,
        amount: u64,
        bonus_earned: u64,
    }

    public struct EarlyUnlock has copy, drop {
        lock_id: ID,
        owner: address,
        amount: u64,
        penalty: u64,
    }

    // === Create Functions ===

    /// Create lockup config
    public fun new_config(
        min_duration: u64,
        max_duration: u64,
        bonus_per_epoch: u64,
        max_bonus: u64,
    ): LockupConfig {
        assert!(max_duration >= min_duration, EInvalidDuration);

        LockupConfig {
            min_duration,
            max_duration,
            bonus_per_epoch,
            max_bonus,
        }
    }

    // === Core Functions ===

    /// Lock tokens
    public fun lock<T>(
        config: &LockupConfig,
        tokens: Coin<T>,
        duration: u64,
        ctx: &mut TxContext,
    ): LockedStake<T> {
        assert!(duration >= config.min_duration, EInvalidDuration);
        assert!(duration <= config.max_duration, EInvalidDuration);

        let amount = coin::value(&tokens);
        let token_balance = coin::into_balance(tokens);

        let current_epoch = ctx.epoch();
        let end_epoch = current_epoch + duration;

        // Calculate bonus rate
        let calculated_bonus = duration * config.bonus_per_epoch;
        let bonus_rate = if (calculated_bonus > config.max_bonus) {
            config.max_bonus
        } else {
            calculated_bonus
        };

        let locked = LockedStake {
            id: object::new(ctx),
            owner: ctx.sender(),
            locked: token_balance,
            start_epoch: current_epoch,
            end_epoch,
            duration,
            bonus_rate,
            unlocked: false,
        };

        event::emit(TokensLocked {
            lock_id: object::id(&locked),
            owner: ctx.sender(),
            amount,
            duration,
            end_epoch,
            bonus_rate,
        });

        locked
    }

    /// Unlock tokens after lockup period
    public fun unlock<T>(
        locked: LockedStake<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        let LockedStake {
            id,
            owner,
            locked: locked_balance,
            start_epoch: _,
            end_epoch,
            duration: _,
            bonus_rate,
            unlocked,
        } = locked;

        assert!(!unlocked, EAlreadyUnlocked);
        assert!(ctx.epoch() >= end_epoch, ELockupNotExpired);

        let amount = balance::value(&locked_balance);

        event::emit(TokensUnlocked {
            lock_id: object::uid_to_inner(&id),
            owner,
            amount,
            bonus_earned: (amount * bonus_rate) / 10000,
        });

        object::delete(id);
        coin::from_balance(locked_balance, ctx)
    }

    /// Early unlock with penalty - returns (user_tokens, penalty_tokens)
    public fun early_unlock<T>(
        locked: LockedStake<T>,
        penalty_bps: u64,
        ctx: &mut TxContext,
    ): (Coin<T>, Coin<T>) {
        let LockedStake {
            id,
            owner,
            locked: locked_balance,
            start_epoch: _,
            end_epoch: _,
            duration: _,
            bonus_rate: _,
            unlocked,
        } = locked;

        assert!(!unlocked, EAlreadyUnlocked);

        let total_amount = balance::value(&locked_balance);
        let penalty_amount = (total_amount * penalty_bps) / 10000;
        let return_amount = total_amount - penalty_amount;

        // Split penalty from locked balance
        let mut remaining = locked_balance;
        let penalty_balance = balance::split(&mut remaining, penalty_amount);

        event::emit(EarlyUnlock {
            lock_id: object::uid_to_inner(&id),
            owner,
            amount: return_amount,
            penalty: penalty_amount,
        });

        object::delete(id);

        // Return both user tokens and penalty tokens (caller decides what to do with penalty)
        let returned_coin = coin::from_balance(remaining, ctx);
        let penalty_coin = coin::from_balance(penalty_balance, ctx);
        (returned_coin, penalty_coin)
    }

    /// Extend lock duration
    public fun extend_lock<T>(
        config: &LockupConfig,
        locked: &mut LockedStake<T>,
        additional_duration: u64,
        ctx: &TxContext,
    ) {
        let new_total_duration = locked.duration + additional_duration;
        assert!(new_total_duration <= config.max_duration, EInvalidDuration);

        locked.duration = new_total_duration;
        locked.end_epoch = locked.end_epoch + additional_duration;

        // Recalculate bonus
        let calculated_bonus = new_total_duration * config.bonus_per_epoch;
        locked.bonus_rate = if (calculated_bonus > config.max_bonus) {
            config.max_bonus
        } else {
            calculated_bonus
        };
    }

    // === View Functions ===

    /// Get lock info
    public fun lock_info<T>(locked: &LockedStake<T>): (u64, u64, u64, u64, bool) {
        (
            balance::value(&locked.locked),
            locked.start_epoch,
            locked.end_epoch,
            locked.bonus_rate,
            locked.unlocked,
        )
    }

    /// Get locked amount
    public fun locked_amount<T>(locked: &LockedStake<T>): u64 {
        balance::value(&locked.locked)
    }

    /// Get bonus rate
    public fun bonus_rate<T>(locked: &LockedStake<T>): u64 {
        locked.bonus_rate
    }

    /// Get end epoch
    public fun end_epoch<T>(locked: &LockedStake<T>): u64 {
        locked.end_epoch
    }

    /// Is lock expired
    public fun is_expired<T>(locked: &LockedStake<T>, current_epoch: u64): bool {
        current_epoch >= locked.end_epoch
    }

    /// Get remaining epochs
    public fun remaining_epochs<T>(locked: &LockedStake<T>, current_epoch: u64): u64 {
        if (current_epoch >= locked.end_epoch) {
            0
        } else {
            locked.end_epoch - current_epoch
        }
    }

    /// Calculate bonus amount
    public fun calculate_bonus<T>(locked: &LockedStake<T>): u64 {
        let amount = balance::value(&locked.locked);
        (amount * locked.bonus_rate) / 10000
    }

    /// Config getters
    public fun config_min_duration(config: &LockupConfig): u64 { config.min_duration }
    public fun config_max_duration(config: &LockupConfig): u64 { config.max_duration }
    public fun config_bonus_per_epoch(config: &LockupConfig): u64 { config.bonus_per_epoch }
    public fun config_max_bonus(config: &LockupConfig): u64 { config.max_bonus }

    // === Tests ===

    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_config() {
        let config = new_config(7, 365, 10, 5000);

        assert!(config_min_duration(&config) == 7, 0);
        assert!(config_max_duration(&config) == 365, 1);
        assert!(config_bonus_per_epoch(&config) == 10, 2);
        assert!(config_max_bonus(&config) == 5000, 3);
    }

    #[test]
    fun test_lock_tokens() {
        let user = @0x1;
        let mut scenario = test_scenario::begin(user);

        {
            let config = new_config(7, 365, 10, 5000);
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());

            let locked = lock(&config, tokens, 30, scenario.ctx());

            let (amount, _, _, bonus, _) = lock_info(&locked);
            assert!(amount == 1000, 0);
            assert!(bonus == 300, 1); // 30 epochs * 10 bps

            transfer::public_transfer(locked, user);
        };

        scenario.end();
    }

    #[test]
    fun test_bonus_calculation() {
        let user = @0x1;
        let mut scenario = test_scenario::begin(user);

        {
            let config = new_config(7, 365, 10, 5000);
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());

            // Lock for 365 epochs at 10 bps per epoch = 3650 bps
            let locked = lock(&config, tokens, 365, scenario.ctx());

            let bonus = calculate_bonus(&locked);
            // 10000 * 3650 / 10000 = 3650
            assert!(bonus == 3650, 0);

            transfer::public_transfer(locked, user);
        };

        scenario.end();
    }

    #[test]
    fun test_max_bonus_cap() {
        let user = @0x1;
        let mut scenario = test_scenario::begin(user);

        {
            let config = new_config(7, 1000, 100, 5000); // 100 bps per epoch, max 50%
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());

            // Lock for 100 epochs at 100 bps = 10000 bps, but capped at 5000
            let locked = lock(&config, tokens, 100, scenario.ctx());

            assert!(bonus_rate(&locked) == 5000, 0); // Capped at 50%

            transfer::public_transfer(locked, user);
        };

        scenario.end();
    }
}
