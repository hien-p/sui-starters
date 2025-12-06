/// @title Timelock
/// @notice Time-locked funds with configurable release schedules
/// @dev Part of @sui-starters/escrow package
module sui_starters_escrow::timelock {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use sui::event;

    // === Errors ===

    /// Timelock not expired
    const ETimelockNotExpired: u64 = 0;

    /// Not the beneficiary
    const ENotBeneficiary: u64 = 1;

    /// Not the creator
    const ENotCreator: u64 = 2;

    /// Invalid unlock time
    const EInvalidUnlockTime: u64 = 3;

    /// Already revoked
    const EAlreadyRevoked: u64 = 4;

    /// Not revocable
    const ENotRevocable: u64 = 5;

    /// Invalid amount
    const EInvalidAmount: u64 = 6;

    /// Cliff not reached
    const ECliffNotReached: u64 = 7;

    // === Structs ===

    /// Simple timelock
    public struct Timelock<phantom T> has key, store {
        id: UID,
        /// Creator
        creator: address,
        /// Beneficiary who can claim
        beneficiary: address,
        /// Locked funds
        balance: Balance<T>,
        /// Unlock timestamp
        unlock_time: u64,
        /// Is revocable by creator
        revocable: bool,
        /// Has been revoked
        revoked: bool,
    }

    /// Linear vesting timelock
    public struct VestingTimelock<phantom T> has key, store {
        id: UID,
        /// Creator
        creator: address,
        /// Beneficiary
        beneficiary: address,
        /// Locked funds
        balance: Balance<T>,
        /// Total amount locked
        total_amount: u64,
        /// Amount already claimed
        claimed_amount: u64,
        /// Vesting start time
        start_time: u64,
        /// Cliff time (before this, nothing can be claimed)
        cliff_time: u64,
        /// Vesting end time (full amount available)
        end_time: u64,
        /// Is revocable
        revocable: bool,
        /// Has been revoked
        revoked: bool,
    }

    /// Multi-stage timelock
    public struct StagedTimelock<phantom T> has key, store {
        id: UID,
        /// Creator
        creator: address,
        /// Beneficiary
        beneficiary: address,
        /// Locked funds
        balance: Balance<T>,
        /// Unlock timestamps
        unlock_times: vector<u64>,
        /// Amount per stage
        amounts: vector<u64>,
        /// Stages claimed
        stages_claimed: u64,
    }

    // === Events ===

    /// Emitted when timelock is created
    public struct TimelockCreated has copy, drop {
        timelock_id: ID,
        creator: address,
        beneficiary: address,
        amount: u64,
        unlock_time: u64,
    }

    /// Emitted when timelock is claimed
    public struct TimelockClaimed has copy, drop {
        timelock_id: ID,
        beneficiary: address,
        amount: u64,
    }

    /// Emitted when timelock is revoked
    public struct TimelockRevoked has copy, drop {
        timelock_id: ID,
        creator: address,
        returned_amount: u64,
    }

    /// Emitted when vesting is claimed
    public struct VestingClaimed has copy, drop {
        timelock_id: ID,
        beneficiary: address,
        amount: u64,
        total_claimed: u64,
    }

    // === Simple Timelock Functions ===

    /// Create a simple timelock
    public fun create_timelock<T>(
        tokens: Coin<T>,
        beneficiary: address,
        unlock_time: u64,
        revocable: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Timelock<T> {
        let now = sui::clock::timestamp_ms(clock);
        assert!(unlock_time > now, EInvalidUnlockTime);

        let amount = coin::value(&tokens);
        assert!(amount > 0, EInvalidAmount);

        let timelock = Timelock<T> {
            id: object::new(ctx),
            creator: ctx.sender(),
            beneficiary,
            balance: coin::into_balance(tokens),
            unlock_time,
            revocable,
            revoked: false,
        };

        event::emit(TimelockCreated {
            timelock_id: object::id(&timelock),
            creator: ctx.sender(),
            beneficiary,
            amount,
            unlock_time,
        });

        timelock
    }

    /// Claim timelock after expiration
    public fun claim_timelock<T>(
        timelock: Timelock<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let now = sui::clock::timestamp_ms(clock);
        assert!(now >= timelock.unlock_time, ETimelockNotExpired);
        assert!(ctx.sender() == timelock.beneficiary, ENotBeneficiary);
        assert!(!timelock.revoked, EAlreadyRevoked);

        let Timelock {
            id,
            creator: _,
            beneficiary,
            balance,
            unlock_time: _,
            revocable: _,
            revoked: _,
        } = timelock;

        let amount = balance::value(&balance);
        let timelock_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(TimelockClaimed {
            timelock_id,
            beneficiary,
            amount,
        });

        coin::from_balance(balance, ctx)
    }

    /// Revoke timelock (if revocable)
    public fun revoke_timelock<T>(
        timelock: Timelock<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(ctx.sender() == timelock.creator, ENotCreator);
        assert!(timelock.revocable, ENotRevocable);
        assert!(!timelock.revoked, EAlreadyRevoked);

        let Timelock {
            id,
            creator,
            beneficiary: _,
            balance,
            unlock_time: _,
            revocable: _,
            revoked: _,
        } = timelock;

        let amount = balance::value(&balance);
        let timelock_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(TimelockRevoked {
            timelock_id,
            creator,
            returned_amount: amount,
        });

        coin::from_balance(balance, ctx)
    }

    // === Vesting Timelock Functions ===

    /// Create vesting timelock
    public fun create_vesting_timelock<T>(
        tokens: Coin<T>,
        beneficiary: address,
        cliff_duration: u64,
        vesting_duration: u64,
        revocable: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ): VestingTimelock<T> {
        let amount = coin::value(&tokens);
        assert!(amount > 0, EInvalidAmount);
        assert!(vesting_duration > 0, EInvalidUnlockTime);

        let now = sui::clock::timestamp_ms(clock);
        let start_time = now;
        let cliff_time = now + cliff_duration;
        let end_time = now + vesting_duration;

        VestingTimelock<T> {
            id: object::new(ctx),
            creator: ctx.sender(),
            beneficiary,
            balance: coin::into_balance(tokens),
            total_amount: amount,
            claimed_amount: 0,
            start_time,
            cliff_time,
            end_time,
            revocable,
            revoked: false,
        }
    }

    /// Claim vested tokens
    public fun claim_vested<T>(
        timelock: &mut VestingTimelock<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(ctx.sender() == timelock.beneficiary, ENotBeneficiary);
        assert!(!timelock.revoked, EAlreadyRevoked);

        let now = sui::clock::timestamp_ms(clock);
        assert!(now >= timelock.cliff_time, ECliffNotReached);

        let vested = calculate_vested(timelock, now);
        let claimable = vested - timelock.claimed_amount;

        assert!(claimable > 0, EInvalidAmount);

        timelock.claimed_amount = vested;

        event::emit(VestingClaimed {
            timelock_id: object::id(timelock),
            beneficiary: timelock.beneficiary,
            amount: claimable,
            total_claimed: vested,
        });

        coin::from_balance(
            balance::split(&mut timelock.balance, claimable),
            ctx,
        )
    }

    /// Revoke vesting timelock
    public fun revoke_vesting_timelock<T>(
        timelock: VestingTimelock<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Coin<T>, Coin<T>) {
        assert!(ctx.sender() == timelock.creator, ENotCreator);
        assert!(timelock.revocable, ENotRevocable);
        assert!(!timelock.revoked, EAlreadyRevoked);

        let now = sui::clock::timestamp_ms(clock);

        // Calculate what beneficiary has vested
        let vested = if (now < timelock.cliff_time) {
            0
        } else {
            calculate_vested(&timelock, now) - timelock.claimed_amount
        };

        let VestingTimelock {
            id,
            creator,
            beneficiary: _,
            mut balance,
            total_amount: _,
            claimed_amount: _,
            start_time: _,
            cliff_time: _,
            end_time: _,
            revocable: _,
            revoked: _,
        } = timelock;

        // Split: beneficiary gets vested, creator gets rest
        let beneficiary_tokens = if (vested > 0 && balance::value(&balance) >= vested) {
            coin::from_balance(balance::split(&mut balance, vested), ctx)
        } else {
            coin::zero(ctx)
        };

        let remaining = balance::value(&balance);
        let creator_tokens = coin::from_balance(balance, ctx);

        let timelock_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(TimelockRevoked {
            timelock_id,
            creator,
            returned_amount: remaining,
        });

        (beneficiary_tokens, creator_tokens)
    }

    /// Calculate vested amount
    fun calculate_vested<T>(timelock: &VestingTimelock<T>, now: u64): u64 {
        if (now < timelock.cliff_time) {
            0
        } else if (now >= timelock.end_time) {
            timelock.total_amount
        } else {
            let elapsed = now - timelock.start_time;
            let total_duration = timelock.end_time - timelock.start_time;
            ((timelock.total_amount as u128) * (elapsed as u128) / (total_duration as u128)) as u64
        }
    }

    // === Staged Timelock Functions ===

    /// Create staged timelock
    public fun create_staged_timelock<T>(
        tokens: Coin<T>,
        beneficiary: address,
        unlock_times: vector<u64>,
        amounts: vector<u64>,
        ctx: &mut TxContext,
    ): StagedTimelock<T> {
        let total = coin::value(&tokens);
        assert!(total > 0, EInvalidAmount);
        assert!(vector::length(&unlock_times) == vector::length(&amounts), EInvalidAmount);
        assert!(vector::length(&unlock_times) > 0, EInvalidAmount);

        // Verify amounts sum to total
        let mut sum: u64 = 0;
        let mut i = 0;
        while (i < vector::length(&amounts)) {
            sum = sum + *vector::borrow(&amounts, i);
            i = i + 1;
        };
        assert!(sum <= total, EInvalidAmount);

        StagedTimelock<T> {
            id: object::new(ctx),
            creator: ctx.sender(),
            beneficiary,
            balance: coin::into_balance(tokens),
            unlock_times,
            amounts,
            stages_claimed: 0,
        }
    }

    /// Claim next available stage
    public fun claim_stage<T>(
        timelock: &mut StagedTimelock<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(ctx.sender() == timelock.beneficiary, ENotBeneficiary);

        let now = sui::clock::timestamp_ms(clock);
        let next_stage = timelock.stages_claimed;

        assert!(next_stage < vector::length(&timelock.unlock_times), EInvalidAmount);

        let unlock_time = *vector::borrow(&timelock.unlock_times, next_stage);
        assert!(now >= unlock_time, ETimelockNotExpired);

        let amount = *vector::borrow(&timelock.amounts, next_stage);
        timelock.stages_claimed = next_stage + 1;

        coin::from_balance(
            balance::split(&mut timelock.balance, amount),
            ctx,
        )
    }

    /// Claim all available stages
    public fun claim_all_available_stages<T>(
        timelock: &mut StagedTimelock<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(ctx.sender() == timelock.beneficiary, ENotBeneficiary);

        let now = sui::clock::timestamp_ms(clock);
        let mut total_claimable: u64 = 0;
        let mut claimable_stages: u64 = 0;

        let mut i = timelock.stages_claimed;
        while (i < vector::length(&timelock.unlock_times)) {
            let unlock_time = *vector::borrow(&timelock.unlock_times, i);
            if (now >= unlock_time) {
                total_claimable = total_claimable + *vector::borrow(&timelock.amounts, i);
                claimable_stages = claimable_stages + 1;
            } else {
                break
            };
            i = i + 1;
        };

        assert!(total_claimable > 0, EInvalidAmount);

        timelock.stages_claimed = timelock.stages_claimed + claimable_stages;

        coin::from_balance(
            balance::split(&mut timelock.balance, total_claimable),
            ctx,
        )
    }

    // === View Functions ===

    /// Get timelock info
    public fun timelock_info<T>(timelock: &Timelock<T>): (address, address, u64, u64, bool) {
        (
            timelock.creator,
            timelock.beneficiary,
            balance::value(&timelock.balance),
            timelock.unlock_time,
            timelock.revocable,
        )
    }

    /// Check if timelock is unlocked
    public fun is_unlocked<T>(timelock: &Timelock<T>, clock: &Clock): bool {
        let now = sui::clock::timestamp_ms(clock);
        now >= timelock.unlock_time
    }

    /// Get remaining time
    public fun remaining_time<T>(timelock: &Timelock<T>, clock: &Clock): u64 {
        let now = sui::clock::timestamp_ms(clock);
        if (now >= timelock.unlock_time) {
            0
        } else {
            timelock.unlock_time - now
        }
    }

    /// Get vesting info
    public fun vesting_info<T>(timelock: &VestingTimelock<T>): (u64, u64, u64, u64, u64) {
        (
            timelock.total_amount,
            timelock.claimed_amount,
            timelock.start_time,
            timelock.cliff_time,
            timelock.end_time,
        )
    }

    /// Get claimable amount from vesting
    public fun claimable_vested<T>(timelock: &VestingTimelock<T>, clock: &Clock): u64 {
        let now = sui::clock::timestamp_ms(clock);
        if (now < timelock.cliff_time || timelock.revoked) {
            0
        } else {
            let vested = calculate_vested(timelock, now);
            vested - timelock.claimed_amount
        }
    }

    /// Get staged timelock info
    public fun staged_info<T>(timelock: &StagedTimelock<T>): (u64, u64, u64) {
        (
            balance::value(&timelock.balance),
            vector::length(&timelock.unlock_times),
            timelock.stages_claimed,
        )
    }

    /// Get claimable stages count
    public fun claimable_stages<T>(timelock: &StagedTimelock<T>, clock: &Clock): u64 {
        let now = sui::clock::timestamp_ms(clock);
        let mut count: u64 = 0;

        let mut i = timelock.stages_claimed;
        while (i < vector::length(&timelock.unlock_times)) {
            let unlock_time = *vector::borrow(&timelock.unlock_times, i);
            if (now >= unlock_time) {
                count = count + 1;
            } else {
                break
            };
            i = i + 1;
        };

        count
    }

    // === Tests ===

    #[test]
    fun test_simple_timelock() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let creator = @0xAA;
        let beneficiary = @0xBB;
        let mut scenario = test_scenario::begin(creator);

        // Create timelock
        {
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let timelock = create_timelock(
                tokens,
                beneficiary,
                5000, // Unlock at 5000
                false,
                &test_clock,
                scenario.ctx(),
            );

            assert!(!is_unlocked(&timelock, &test_clock), 0);
            assert!(remaining_time(&timelock, &test_clock) == 4000, 1);

            clock::destroy_for_testing(test_clock);
            transfer::public_transfer(timelock, beneficiary);
        };

        // Claim timelock
        scenario.next_tx(beneficiary);
        {
            let timelock = scenario.take_from_sender<Timelock<SUI>>();
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 6000);

            assert!(is_unlocked(&timelock, &test_clock), 2);

            let claimed = claim_timelock(timelock, &test_clock, scenario.ctx());
            assert!(coin::value(&claimed) == 1000, 3);

            coin::burn_for_testing(claimed);
            clock::destroy_for_testing(test_clock);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ETimelockNotExpired)]
    fun test_claim_before_unlock_fails() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let creator = @0xAA;
        let beneficiary = @0xBB;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let timelock = create_timelock(
                tokens,
                beneficiary,
                5000,
                false,
                &test_clock,
                scenario.ctx(),
            );

            clock::destroy_for_testing(test_clock);
            transfer::public_transfer(timelock, beneficiary);
        };

        scenario.next_tx(beneficiary);
        {
            let timelock = scenario.take_from_sender<Timelock<SUI>>();
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 3000); // Before unlock

            // Should fail
            let claimed = claim_timelock(timelock, &test_clock, scenario.ctx());

            coin::burn_for_testing(claimed);
            clock::destroy_for_testing(test_clock);
        };

        scenario.end();
    }

    #[test]
    fun test_revocable_timelock() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let creator = @0xAA;
        let beneficiary = @0xBB;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let timelock = create_timelock(
                tokens,
                beneficiary,
                5000,
                true, // Revocable
                &test_clock,
                scenario.ctx(),
            );

            // Revoke before unlock
            let revoked = revoke_timelock(timelock, scenario.ctx());
            assert!(coin::value(&revoked) == 1000, 0);

            coin::burn_for_testing(revoked);
            clock::destroy_for_testing(test_clock);
        };

        scenario.end();
    }

    #[test]
    fun test_vesting_timelock() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let creator = @0xAA;
        let beneficiary = @0xBB;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            let mut vesting = create_vesting_timelock(
                tokens,
                beneficiary,
                1000,  // 1 second cliff
                10000, // 10 second vesting
                false,
                &test_clock,
                scenario.ctx(),
            );

            // Before cliff - nothing claimable
            assert!(claimable_vested(&vesting, &test_clock) == 0, 0);

            // At cliff - some vested
            clock::set_for_testing(&mut test_clock, 2000);
            // At 1 second into 10 second vesting = 10%
            let claimable = claimable_vested(&vesting, &test_clock);
            assert!(claimable == 1000, 1);

            // Halfway through
            clock::set_for_testing(&mut test_clock, 6000);
            // At 5 seconds into 10 second vesting = 50%
            let claimable2 = claimable_vested(&vesting, &test_clock);
            assert!(claimable2 == 5000, 2);

            clock::destroy_for_testing(test_clock);
            transfer::public_share_object(vesting);
        };

        scenario.end();
    }

    #[test]
    fun test_staged_timelock() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let creator = @0xAA;
        let beneficiary = @0xBB;
        let mut scenario = test_scenario::begin(creator);

        {
            let tokens = coin::mint_for_testing<SUI>(6000, scenario.ctx());
            let unlock_times = vector[1000, 2000, 3000];
            let amounts = vector[1000, 2000, 3000];

            let mut staged = create_staged_timelock(
                tokens,
                beneficiary,
                unlock_times,
                amounts,
                scenario.ctx(),
            );

            let mut test_clock = clock::create_for_testing(scenario.ctx());

            // No stages claimable yet
            clock::set_for_testing(&mut test_clock, 500);
            assert!(claimable_stages(&staged, &test_clock) == 0, 0);

            // First stage claimable
            clock::set_for_testing(&mut test_clock, 1500);
            assert!(claimable_stages(&staged, &test_clock) == 1, 1);

            // All stages claimable
            clock::set_for_testing(&mut test_clock, 4000);
            assert!(claimable_stages(&staged, &test_clock) == 3, 2);

            clock::destroy_for_testing(test_clock);
            transfer::public_share_object(staged);
        };

        scenario.end();
    }
}
