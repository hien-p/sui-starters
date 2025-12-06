/// @title Token Vesting
/// @notice Linear and cliff vesting schedules for tokens
/// @dev Part of @sui-starters/token package
module sui_starters_token::vesting {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::clock::Clock;

    // === Errors ===

    /// Cliff not reached
    const ECliffNotReached: u64 = 0;

    /// Nothing to claim
    const ENothingToClaim: u64 = 1;

    /// Vesting not started
    const EVestingNotStarted: u64 = 2;

    /// Invalid schedule
    const EInvalidSchedule: u64 = 3;

    /// Not the beneficiary
    const ENotBeneficiary: u64 = 4;

    /// Already revoked
    const EAlreadyRevoked: u64 = 5;

    /// Not revocable
    const ENotRevocable: u64 = 6;

    // === Constants ===

    /// Basis points denominator
    const BPS_DENOMINATOR: u64 = 10000;

    // === Structs ===

    /// Linear vesting schedule
    public struct VestingSchedule<phantom T> has key, store {
        id: UID,
        /// Beneficiary address
        beneficiary: address,
        /// Total amount to vest
        total_amount: u64,
        /// Amount already claimed
        claimed_amount: u64,
        /// Vesting start time (ms)
        start_time: u64,
        /// Cliff duration (ms) - no tokens before this
        cliff_duration: u64,
        /// Total vesting duration (ms)
        vesting_duration: u64,
        /// Token balance
        balance: Balance<T>,
        /// Is revocable by admin
        revocable: bool,
        /// Is revoked
        revoked: bool,
    }

    /// Vesting info (read-only)
    public struct VestingInfo has copy, drop {
        beneficiary: address,
        total_amount: u64,
        claimed_amount: u64,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        revocable: bool,
        revoked: bool,
    }

    /// Milestone-based vesting
    public struct MilestoneVesting<phantom T> has key, store {
        id: UID,
        /// Beneficiary address
        beneficiary: address,
        /// Milestones with amounts
        milestones: vector<Milestone>,
        /// Current milestone index
        current_milestone: u64,
        /// Token balance
        balance: Balance<T>,
        /// Total amount
        total_amount: u64,
        /// Claimed amount
        claimed_amount: u64,
    }

    /// Vesting milestone
    public struct Milestone has store, copy, drop {
        /// Unlock time (ms)
        unlock_time: u64,
        /// Amount to unlock
        amount: u64,
        /// Is claimed
        claimed: bool,
    }

    // === Events ===

    /// Emitted when vesting schedule is created
    public struct VestingCreated has copy, drop {
        schedule_id: ID,
        beneficiary: address,
        total_amount: u64,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
    }

    /// Emitted when tokens are claimed
    public struct TokensClaimed has copy, drop {
        schedule_id: ID,
        beneficiary: address,
        amount: u64,
        total_claimed: u64,
    }

    /// Emitted when vesting is revoked
    public struct VestingRevoked has copy, drop {
        schedule_id: ID,
        beneficiary: address,
        returned_amount: u64,
    }

    /// Emitted when milestone is reached
    public struct MilestoneReached has copy, drop {
        vesting_id: ID,
        milestone_index: u64,
        amount: u64,
    }

    // === VestingSchedule Functions ===

    /// Create new vesting schedule
    public fun new<T>(
        tokens: Coin<T>,
        beneficiary: address,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        revocable: bool,
        ctx: &mut TxContext,
    ): VestingSchedule<T> {
        assert!(vesting_duration > 0, EInvalidSchedule);
        assert!(cliff_duration <= vesting_duration, EInvalidSchedule);

        let total_amount = coin::value(&tokens);

        let schedule = VestingSchedule<T> {
            id: object::new(ctx),
            beneficiary,
            total_amount,
            claimed_amount: 0,
            start_time,
            cliff_duration,
            vesting_duration,
            balance: coin::into_balance(tokens),
            revocable,
            revoked: false,
        };

        event::emit(VestingCreated {
            schedule_id: object::id(&schedule),
            beneficiary,
            total_amount,
            start_time,
            cliff_duration,
            vesting_duration,
        });

        schedule
    }

    /// Create and transfer to beneficiary
    public fun create_and_transfer<T>(
        tokens: Coin<T>,
        beneficiary: address,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        revocable: bool,
        ctx: &mut TxContext,
    ) {
        let schedule = new(tokens, beneficiary, start_time, cliff_duration, vesting_duration, revocable, ctx);
        transfer::transfer(schedule, beneficiary);
    }

    /// Calculate vested amount at given time
    public fun vested_amount<T>(schedule: &VestingSchedule<T>, current_time: u64): u64 {
        if (schedule.revoked) {
            return 0
        };

        if (current_time < schedule.start_time) {
            return 0
        };

        let elapsed = current_time - schedule.start_time;

        // Before cliff
        if (elapsed < schedule.cliff_duration) {
            return 0
        };

        // Fully vested
        if (elapsed >= schedule.vesting_duration) {
            return schedule.total_amount
        };

        // Linear vesting
        ((schedule.total_amount as u128) * (elapsed as u128) / (schedule.vesting_duration as u128)) as u64
    }

    /// Calculate claimable amount
    public fun claimable_amount<T>(schedule: &VestingSchedule<T>, current_time: u64): u64 {
        let vested = vested_amount(schedule, current_time);
        if (vested <= schedule.claimed_amount) {
            0
        } else {
            vested - schedule.claimed_amount
        }
    }

    /// Claim vested tokens
    public fun claim<T>(
        schedule: &mut VestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(ctx.sender() == schedule.beneficiary, ENotBeneficiary);
        assert!(!schedule.revoked, EAlreadyRevoked);

        let current_time = sui::clock::timestamp_ms(clock);
        let claim_amount = claimable_amount(schedule, current_time);

        assert!(claim_amount > 0, ENothingToClaim);

        schedule.claimed_amount = schedule.claimed_amount + claim_amount;

        event::emit(TokensClaimed {
            schedule_id: object::id(schedule),
            beneficiary: schedule.beneficiary,
            amount: claim_amount,
            total_claimed: schedule.claimed_amount,
        });

        coin::from_balance(balance::split(&mut schedule.balance, claim_amount), ctx)
    }

    /// Claim and transfer to beneficiary
    public fun claim_to_beneficiary<T>(
        schedule: &mut VestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let tokens = claim(schedule, clock, ctx);
        transfer::public_transfer(tokens, schedule.beneficiary);
    }

    /// Revoke vesting (admin only)
    public fun revoke<T>(
        schedule: &mut VestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(schedule.revocable, ENotRevocable);
        assert!(!schedule.revoked, EAlreadyRevoked);

        let current_time = sui::clock::timestamp_ms(clock);
        let vested = vested_amount(schedule, current_time);
        let unvested = schedule.total_amount - vested;

        schedule.revoked = true;

        // Return unvested tokens
        let returned = if (unvested > 0 && balance::value(&schedule.balance) >= unvested) {
            balance::split(&mut schedule.balance, unvested)
        } else {
            balance::zero()
        };

        let returned_amount = balance::value(&returned);

        event::emit(VestingRevoked {
            schedule_id: object::id(schedule),
            beneficiary: schedule.beneficiary,
            returned_amount,
        });

        coin::from_balance(returned, ctx)
    }

    // === View Functions ===

    /// Get beneficiary
    public fun beneficiary<T>(schedule: &VestingSchedule<T>): address {
        schedule.beneficiary
    }

    /// Get total amount
    public fun total_amount<T>(schedule: &VestingSchedule<T>): u64 {
        schedule.total_amount
    }

    /// Get claimed amount
    public fun claimed_amount<T>(schedule: &VestingSchedule<T>): u64 {
        schedule.claimed_amount
    }

    /// Get start time
    public fun start_time<T>(schedule: &VestingSchedule<T>): u64 {
        schedule.start_time
    }

    /// Get cliff duration
    public fun cliff_duration<T>(schedule: &VestingSchedule<T>): u64 {
        schedule.cliff_duration
    }

    /// Get vesting duration
    public fun vesting_duration<T>(schedule: &VestingSchedule<T>): u64 {
        schedule.vesting_duration
    }

    /// Check if revocable
    public fun is_revocable<T>(schedule: &VestingSchedule<T>): bool {
        schedule.revocable
    }

    /// Check if revoked
    public fun is_revoked<T>(schedule: &VestingSchedule<T>): bool {
        schedule.revoked
    }

    /// Get remaining balance
    public fun remaining_balance<T>(schedule: &VestingSchedule<T>): u64 {
        balance::value(&schedule.balance)
    }

    /// Get vesting info
    public fun info<T>(schedule: &VestingSchedule<T>): VestingInfo {
        VestingInfo {
            beneficiary: schedule.beneficiary,
            total_amount: schedule.total_amount,
            claimed_amount: schedule.claimed_amount,
            start_time: schedule.start_time,
            cliff_duration: schedule.cliff_duration,
            vesting_duration: schedule.vesting_duration,
            revocable: schedule.revocable,
            revoked: schedule.revoked,
        }
    }

    /// Calculate vesting progress in basis points
    public fun progress_bps<T>(schedule: &VestingSchedule<T>, current_time: u64): u64 {
        let vested = vested_amount(schedule, current_time);
        if (schedule.total_amount == 0) {
            return 0
        };
        ((vested as u128) * (BPS_DENOMINATOR as u128) / (schedule.total_amount as u128)) as u64
    }

    // === MilestoneVesting Functions ===

    /// Create milestone vesting
    public fun new_milestone<T>(
        tokens: Coin<T>,
        beneficiary: address,
        ctx: &mut TxContext,
    ): MilestoneVesting<T> {
        let total_amount = coin::value(&tokens);
        MilestoneVesting<T> {
            id: object::new(ctx),
            beneficiary,
            milestones: vector[],
            current_milestone: 0,
            balance: coin::into_balance(tokens),
            total_amount,
            claimed_amount: 0,
        }
    }

    /// Add milestone
    public fun add_milestone<T>(
        vesting: &mut MilestoneVesting<T>,
        unlock_time: u64,
        amount: u64,
    ) {
        let milestone = Milestone {
            unlock_time,
            amount,
            claimed: false,
        };
        vector::push_back(&mut vesting.milestones, milestone);
    }

    /// Claim available milestones
    public fun claim_milestones<T>(
        vesting: &mut MilestoneVesting<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(ctx.sender() == vesting.beneficiary, ENotBeneficiary);

        let current_time = sui::clock::timestamp_ms(clock);
        let mut total_claim: u64 = 0;
        let vesting_id = object::id(vesting);

        let len = vector::length(&vesting.milestones);
        let mut i = 0;
        while (i < len) {
            let milestone = vector::borrow_mut(&mut vesting.milestones, i);
            if (!milestone.claimed && current_time >= milestone.unlock_time) {
                milestone.claimed = true;
                let amount = milestone.amount;
                total_claim = total_claim + amount;

                event::emit(MilestoneReached {
                    vesting_id,
                    milestone_index: i,
                    amount,
                });
            };
            i = i + 1;
        };

        assert!(total_claim > 0, ENothingToClaim);

        vesting.claimed_amount = vesting.claimed_amount + total_claim;
        coin::from_balance(balance::split(&mut vesting.balance, total_claim), ctx)
    }

    /// Get milestone count
    public fun milestone_count<T>(vesting: &MilestoneVesting<T>): u64 {
        vector::length(&vesting.milestones)
    }

    /// Get milestone at index
    public fun get_milestone<T>(vesting: &MilestoneVesting<T>, index: u64): Milestone {
        *vector::borrow(&vesting.milestones, index)
    }

    /// Get next claimable milestone
    public fun next_claimable_milestone<T>(vesting: &MilestoneVesting<T>, current_time: u64): Option<u64> {
        let len = vector::length(&vesting.milestones);
        let mut i = 0;
        while (i < len) {
            let milestone = vector::borrow(&vesting.milestones, i);
            if (!milestone.claimed) {
                if (current_time >= milestone.unlock_time) {
                    return option::some(i)
                };
            };
            i = i + 1;
        };
        option::none()
    }

    /// Get milestone beneficiary
    public fun milestone_beneficiary<T>(vesting: &MilestoneVesting<T>): address {
        vesting.beneficiary
    }

    /// Get milestone total amount
    public fun milestone_total_amount<T>(vesting: &MilestoneVesting<T>): u64 {
        vesting.total_amount
    }

    /// Get milestone claimed amount
    public fun milestone_claimed_amount<T>(vesting: &MilestoneVesting<T>): u64 {
        vesting.claimed_amount
    }

    // === Tests ===

    #[test]
    fun test_vesting_calculation() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            // Create 1000 tokens vesting over 100 days with 10 day cliff
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let start = 0;
            let cliff = 10000; // 10 seconds as ms
            let duration = 100000; // 100 seconds as ms

            let schedule = new(tokens, user, start, cliff, duration, true, scenario.ctx());

            // Before cliff (5 seconds)
            assert!(vested_amount(&schedule, 5000) == 0, 0);

            // At cliff (10 seconds)
            assert!(vested_amount(&schedule, 10000) == 100, 1); // 10% vested

            // Halfway (50 seconds)
            assert!(vested_amount(&schedule, 50000) == 500, 2); // 50% vested

            // At end (100 seconds)
            assert!(vested_amount(&schedule, 100000) == 1000, 3); // 100% vested

            // After end
            assert!(vested_amount(&schedule, 150000) == 1000, 4); // Still 100%

            transfer::transfer(schedule, user);
        };

        scenario.end();
    }

    #[test]
    fun test_claimable_amount() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let schedule = new(tokens, user, 0, 0, 100000, false, scenario.ctx());

            // At 50%
            assert!(claimable_amount(&schedule, 50000) == 500, 0);

            transfer::transfer(schedule, user);
        };

        scenario.end();
    }

    #[test]
    fun test_progress_bps() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let schedule = new(tokens, user, 0, 0, 100000, false, scenario.ctx());

            // 25% progress
            assert!(progress_bps(&schedule, 25000) == 2500, 0);

            // 50% progress
            assert!(progress_bps(&schedule, 50000) == 5000, 1);

            // 100% progress
            assert!(progress_bps(&schedule, 100000) == 10000, 2);

            transfer::transfer(schedule, user);
        };

        scenario.end();
    }

    #[test]
    fun test_vesting_info() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let schedule = new(tokens, user, 1000, 500, 10000, true, scenario.ctx());

            let vesting_info = info(&schedule);
            assert!(vesting_info.beneficiary == user, 0);
            assert!(vesting_info.total_amount == 1000, 1);
            assert!(vesting_info.start_time == 1000, 2);
            assert!(vesting_info.cliff_duration == 500, 3);
            assert!(vesting_info.vesting_duration == 10000, 4);
            assert!(vesting_info.revocable == true, 5);

            transfer::transfer(schedule, user);
        };

        scenario.end();
    }

    #[test]
    fun test_milestone_vesting() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let mut vesting = new_milestone(tokens, user, scenario.ctx());

            // Add 4 milestones (25% each)
            add_milestone(&mut vesting, 1000, 250);
            add_milestone(&mut vesting, 2000, 250);
            add_milestone(&mut vesting, 3000, 250);
            add_milestone(&mut vesting, 4000, 250);

            assert!(milestone_count(&vesting) == 4, 0);
            assert!(milestone_total_amount(&vesting) == 1000, 1);

            let m0 = get_milestone(&vesting, 0);
            assert!(m0.unlock_time == 1000, 2);
            assert!(m0.amount == 250, 3);

            transfer::transfer(vesting, user);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EInvalidSchedule)]
    fun test_invalid_cliff() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            // Cliff > duration should fail
            let schedule = new(tokens, user, 0, 10000, 5000, false, scenario.ctx());
            transfer::transfer(schedule, user);
        };

        scenario.end();
    }
}
