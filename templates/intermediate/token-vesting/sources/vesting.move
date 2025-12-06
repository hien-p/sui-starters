/// @title Token Vesting
/// @notice Token vesting with cliff and linear release
/// @dev Demonstrates time-based mechanics and balance management
module token_vesting::vesting {
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;

    // === Errors ===

    const ENothingToClaim: u64 = 0;
    const EVestingNotStarted: u64 = 1;
    const EAlreadyRevoked: u64 = 2;
    const ENotRevocable: u64 = 3;
    const ENotBeneficiary: u64 = 4;

    // === Structs ===

    /// Vesting schedule for a beneficiary
    public struct VestingSchedule<phantom T> has key, store {
        id: UID,
        /// Beneficiary address
        beneficiary: address,
        /// Granter who created this schedule
        granter: address,
        /// Total tokens to vest
        total_amount: u64,
        /// Tokens already claimed
        claimed_amount: u64,
        /// Tokens in escrow
        escrowed: Balance<T>,
        /// Start timestamp (ms)
        start_time: u64,
        /// Cliff duration (ms) - no tokens vest before cliff
        cliff_duration: u64,
        /// Total vesting duration (ms)
        vesting_duration: u64,
        /// Is schedule revocable by granter
        revocable: bool,
        /// Has been revoked
        revoked: bool,
    }

    // === Events ===

    public struct VestingCreated has copy, drop {
        schedule_id: ID,
        beneficiary: address,
        total_amount: u64,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
    }

    public struct TokensClaimed has copy, drop {
        schedule_id: ID,
        beneficiary: address,
        amount: u64,
        total_claimed: u64,
    }

    public struct VestingRevoked has copy, drop {
        schedule_id: ID,
        beneficiary: address,
        amount_returned: u64,
    }

    // === Entry Functions ===

    /// Create a vesting schedule
    public entry fun create_vesting<T>(
        tokens: Coin<T>,
        beneficiary: address,
        start_time: u64,
        cliff_duration: u64,
        vesting_duration: u64,
        revocable: bool,
        ctx: &mut TxContext,
    ) {
        let total_amount = coin::value(&tokens);

        let schedule = VestingSchedule {
            id: object::new(ctx),
            beneficiary,
            granter: ctx.sender(),
            total_amount,
            claimed_amount: 0,
            escrowed: coin::into_balance(tokens),
            start_time,
            cliff_duration,
            vesting_duration,
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

        transfer::transfer(schedule, beneficiary);
    }

    /// Claim vested tokens
    public entry fun claim<T>(
        schedule: &mut VestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(schedule.beneficiary == ctx.sender(), ENotBeneficiary);
        assert!(!schedule.revoked, EAlreadyRevoked);

        let current_time = sui::clock::timestamp_ms(clock);
        let vested = calculate_vested(schedule, current_time);
        let claimable = vested - schedule.claimed_amount;

        assert!(claimable > 0, ENothingToClaim);

        schedule.claimed_amount = schedule.claimed_amount + claimable;

        let claim_balance = balance::split(&mut schedule.escrowed, claimable);
        let claim_coin = coin::from_balance(claim_balance, ctx);

        event::emit(TokensClaimed {
            schedule_id: object::id(schedule),
            beneficiary: schedule.beneficiary,
            amount: claimable,
            total_claimed: schedule.claimed_amount,
        });

        transfer::public_transfer(claim_coin, schedule.beneficiary);
    }

    /// Revoke vesting (granter only, if revocable)
    public entry fun revoke<T>(
        schedule: &mut VestingSchedule<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(schedule.granter == ctx.sender(), ENotBeneficiary);
        assert!(schedule.revocable, ENotRevocable);
        assert!(!schedule.revoked, EAlreadyRevoked);

        let current_time = sui::clock::timestamp_ms(clock);
        let vested = calculate_vested(schedule, current_time);
        let unvested = schedule.total_amount - vested;

        schedule.revoked = true;

        // Transfer unvested back to granter
        if (unvested > 0) {
            let return_balance = balance::split(&mut schedule.escrowed, unvested);
            let return_coin = coin::from_balance(return_balance, ctx);

            event::emit(VestingRevoked {
                schedule_id: object::id(schedule),
                beneficiary: schedule.beneficiary,
                amount_returned: unvested,
            });

            transfer::public_transfer(return_coin, schedule.granter);
        };
    }

    // === View Functions ===

    /// Calculate vested amount at given time
    public fun calculate_vested<T>(schedule: &VestingSchedule<T>, current_time: u64): u64 {
        if (current_time < schedule.start_time) {
            return 0
        };

        let elapsed = current_time - schedule.start_time;

        // Before cliff: nothing vested
        if (elapsed < schedule.cliff_duration) {
            return 0
        };

        // After full duration: everything vested
        if (elapsed >= schedule.vesting_duration) {
            return schedule.total_amount
        };

        // Linear vesting
        ((schedule.total_amount as u128) * (elapsed as u128) / (schedule.vesting_duration as u128)) as u64
    }

    /// Get claimable amount
    public fun claimable<T>(schedule: &VestingSchedule<T>, clock: &Clock): u64 {
        if (schedule.revoked) {
            return 0
        };

        let current_time = sui::clock::timestamp_ms(clock);
        let vested = calculate_vested(schedule, current_time);

        if (vested > schedule.claimed_amount) {
            vested - schedule.claimed_amount
        } else {
            0
        }
    }

    /// Get schedule info
    public fun schedule_info<T>(schedule: &VestingSchedule<T>): (u64, u64, u64, u64, bool) {
        (
            schedule.total_amount,
            schedule.claimed_amount,
            schedule.start_time,
            schedule.vesting_duration,
            schedule.revoked,
        )
    }

    /// Get beneficiary
    public fun beneficiary<T>(schedule: &VestingSchedule<T>): address {
        schedule.beneficiary
    }

    /// Get granter
    public fun granter<T>(schedule: &VestingSchedule<T>): address {
        schedule.granter
    }

    /// Is revocable
    public fun is_revocable<T>(schedule: &VestingSchedule<T>): bool {
        schedule.revocable
    }

    /// Is revoked
    public fun is_revoked<T>(schedule: &VestingSchedule<T>): bool {
        schedule.revoked
    }

    /// Get remaining tokens
    public fun remaining<T>(schedule: &VestingSchedule<T>): u64 {
        balance::value(&schedule.escrowed)
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::clock;
    #[test_only]
    use sui::sui::SUI;

    #[test]
    fun test_create_vesting() {
        let granter = @0x1;
        let beneficiary = @0x2;
        let mut scenario = test_scenario::begin(granter);

        {
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            create_vesting(
                tokens,
                beneficiary,
                0, // Start now
                1000, // 1 second cliff
                10000, // 10 second vesting
                true,
                scenario.ctx(),
            );
        };

        scenario.next_tx(beneficiary);
        {
            let schedule = scenario.take_from_sender<VestingSchedule<SUI>>();

            let (total, claimed, _, _, revoked) = schedule_info(&schedule);
            assert!(total == 10000, 0);
            assert!(claimed == 0, 1);
            assert!(!revoked, 2);

            scenario.return_to_sender(schedule);
        };

        scenario.end();
    }

    #[test]
    fun test_vesting_calculation() {
        let granter = @0x1;
        let beneficiary = @0x2;
        let mut scenario = test_scenario::begin(granter);

        {
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            create_vesting(
                tokens,
                beneficiary,
                0,
                2000, // 2 second cliff
                10000, // 10 second total
                false,
                scenario.ctx(),
            );
        };

        scenario.next_tx(beneficiary);
        {
            let schedule = scenario.take_from_sender<VestingSchedule<SUI>>();

            // Before cliff
            let vested_0 = calculate_vested(&schedule, 1000);
            assert!(vested_0 == 0, 0);

            // At cliff
            let vested_cliff = calculate_vested(&schedule, 2000);
            assert!(vested_cliff == 2000, 1); // 20% at 20%

            // Halfway
            let vested_half = calculate_vested(&schedule, 5000);
            assert!(vested_half == 5000, 2); // 50%

            // Full
            let vested_full = calculate_vested(&schedule, 10000);
            assert!(vested_full == 10000, 3);

            scenario.return_to_sender(schedule);
        };

        scenario.end();
    }

    #[test]
    fun test_claim() {
        let granter = @0x1;
        let beneficiary = @0x2;
        let mut scenario = test_scenario::begin(granter);

        {
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            create_vesting(
                tokens,
                beneficiary,
                0,
                0, // No cliff
                10000,
                false,
                scenario.ctx(),
            );
        };

        scenario.next_tx(beneficiary);
        {
            let mut schedule = scenario.take_from_sender<VestingSchedule<SUI>>();
            let mut clk = clock::create_for_testing(scenario.ctx());

            // Move time to 50%
            clock::set_for_testing(&mut clk, 5000);

            claim(&mut schedule, &clk, scenario.ctx());

            let (_, claimed, _, _, _) = schedule_info(&schedule);
            assert!(claimed == 5000, 0);

            clock::destroy_for_testing(clk);
            scenario.return_to_sender(schedule);
        };

        scenario.end();
    }
}
