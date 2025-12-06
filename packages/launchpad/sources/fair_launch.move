/// @title Fair Launch
/// @notice Fair token distribution with equal pricing
/// @dev Part of @sui-starters/launchpad package
module sui_starters_launchpad::fair_launch {
    use std::string::String;
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::table::{Self, Table};

    // === Errors ===

    const ELaunchNotStarted: u64 = 0;
    const ELaunchEnded: u64 = 1;
    const EAlreadyContributed: u64 = 2;
    const ENotContributed: u64 = 3;
    const ELaunchNotEnded: u64 = 4;
    const EAlreadyClaimed: u64 = 5;
    const EMinContributionNotMet: u64 = 6;
    const EMaxContributionExceeded: u64 = 7;
    const EAlreadyFinalized: u64 = 8;

    // === Structs ===

    /// Fair launch configuration (everyone gets same price)
    public struct FairLaunch<phantom T, phantom P> has key, store {
        id: UID,
        name: String,
        /// Tokens for distribution
        tokens_for_sale: Balance<T>,
        /// Payments collected
        payments_collected: Balance<P>,
        /// Start timestamp (ms)
        start_time: u64,
        /// End timestamp (ms)
        end_time: u64,
        /// Minimum contribution per user
        min_contribution: u64,
        /// Maximum contribution per user
        max_contribution: u64,
        /// Total contributions
        total_contributions: u64,
        /// Contributor count
        contributor_count: u64,
        /// Contributions by address
        contributions: Table<address, u64>,
        /// Has claimed by address
        claimed: Table<address, bool>,
        /// Is finalized
        finalized: bool,
        /// Final token price (calculated at finalization)
        final_price: u64,
    }

    /// Admin capability
    public struct LaunchAdmin<phantom T, phantom P> has key, store {
        id: UID,
        launch_id: ID,
    }

    /// Contribution receipt
    public struct ContributionReceipt<phantom T, phantom P> has key, store {
        id: UID,
        launch_id: ID,
        contributor: address,
        amount: u64,
        contribution_time: u64,
    }

    // === Events ===

    public struct LaunchCreated has copy, drop {
        launch_id: ID,
        name: String,
        total_tokens: u64,
        start_time: u64,
        end_time: u64,
    }

    public struct Contributed has copy, drop {
        launch_id: ID,
        contributor: address,
        amount: u64,
        total_contributions: u64,
    }

    public struct TokensClaimed has copy, drop {
        launch_id: ID,
        contributor: address,
        contribution: u64,
        tokens_received: u64,
    }

    public struct LaunchFinalized has copy, drop {
        launch_id: ID,
        total_contributions: u64,
        contributors: u64,
        final_price: u64,
    }

    // === Constants ===

    const PRICE_PRECISION: u64 = 1000000000; // 1e9

    // === Create Functions ===

    /// Create a new fair launch
    public fun new<T, P>(
        name: String,
        tokens: Coin<T>,
        start_time: u64,
        end_time: u64,
        min_contribution: u64,
        max_contribution: u64,
        ctx: &mut TxContext,
    ): (FairLaunch<T, P>, LaunchAdmin<T, P>) {
        let token_balance = coin::into_balance(tokens);

        let launch = FairLaunch {
            id: object::new(ctx),
            name,
            tokens_for_sale: token_balance,
            payments_collected: balance::zero(),
            start_time,
            end_time,
            min_contribution,
            max_contribution,
            total_contributions: 0,
            contributor_count: 0,
            contributions: table::new(ctx),
            claimed: table::new(ctx),
            finalized: false,
            final_price: 0,
        };

        let launch_id = object::id(&launch);

        let admin = LaunchAdmin {
            id: object::new(ctx),
            launch_id,
        };

        event::emit(LaunchCreated {
            launch_id,
            name: launch.name,
            total_tokens: balance::value(&launch.tokens_for_sale),
            start_time,
            end_time,
        });

        (launch, admin)
    }

    // === Core Functions ===

    /// Contribute to fair launch
    public fun contribute<T, P>(
        launch: &mut FairLaunch<T, P>,
        payment: Coin<P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): ContributionReceipt<T, P> {
        let current_time = sui::clock::timestamp_ms(clock);
        let sender = ctx.sender();

        assert!(current_time >= launch.start_time, ELaunchNotStarted);
        assert!(current_time <= launch.end_time, ELaunchEnded);
        assert!(!table::contains(&launch.contributions, sender), EAlreadyContributed);

        let amount = coin::value(&payment);
        assert!(amount >= launch.min_contribution, EMinContributionNotMet);
        assert!(amount <= launch.max_contribution, EMaxContributionExceeded);

        // Record contribution
        table::add(&mut launch.contributions, sender, amount);
        launch.total_contributions = launch.total_contributions + amount;
        launch.contributor_count = launch.contributor_count + 1;

        // Collect payment
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut launch.payments_collected, payment_balance);

        let receipt = ContributionReceipt {
            id: object::new(ctx),
            launch_id: object::id(launch),
            contributor: sender,
            amount,
            contribution_time: current_time,
        };

        event::emit(Contributed {
            launch_id: object::id(launch),
            contributor: sender,
            amount,
            total_contributions: launch.total_contributions,
        });

        receipt
    }

    /// Add to existing contribution
    public fun add_contribution<T, P>(
        launch: &mut FairLaunch<T, P>,
        payment: Coin<P>,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        let current_time = sui::clock::timestamp_ms(clock);
        let sender = ctx.sender();

        assert!(current_time >= launch.start_time, ELaunchNotStarted);
        assert!(current_time <= launch.end_time, ELaunchEnded);
        assert!(table::contains(&launch.contributions, sender), ENotContributed);

        let amount = coin::value(&payment);
        let current = *table::borrow(&launch.contributions, sender);
        let new_total = current + amount;

        assert!(new_total <= launch.max_contribution, EMaxContributionExceeded);

        // Update contribution
        *table::borrow_mut(&mut launch.contributions, sender) = new_total;
        launch.total_contributions = launch.total_contributions + amount;

        // Collect payment
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut launch.payments_collected, payment_balance);

        event::emit(Contributed {
            launch_id: object::id(launch),
            contributor: sender,
            amount: new_total,
            total_contributions: launch.total_contributions,
        });
    }

    /// Claim tokens after launch ends
    public fun claim<T, P>(
        launch: &mut FairLaunch<T, P>,
        receipt: ContributionReceipt<T, P>,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(launch.finalized, ELaunchNotEnded);

        let ContributionReceipt {
            id,
            launch_id: _,
            contributor,
            amount: contribution,
            contribution_time: _,
        } = receipt;

        object::delete(id);

        assert!(!*table::borrow(&launch.claimed, contributor), EAlreadyClaimed);

        // Calculate tokens: contribution * total_tokens / total_contributions
        let total_tokens = balance::value(&launch.tokens_for_sale) +
            (launch.contributor_count * contribution / launch.total_contributions); // Approximation for already distributed
        let _ = total_tokens; // Suppress warning

        let tokens_to_receive = calculate_tokens(
            contribution,
            launch.final_price,
        );

        // Mark as claimed
        *table::borrow_mut(&mut launch.claimed, contributor) = true;

        // Transfer tokens
        let tokens = balance::split(&mut launch.tokens_for_sale, tokens_to_receive);

        event::emit(TokensClaimed {
            launch_id: object::id(launch),
            contributor,
            contribution,
            tokens_received: tokens_to_receive,
        });

        coin::from_balance(tokens, ctx)
    }

    /// Calculate tokens for contribution
    fun calculate_tokens(contribution: u64, price: u64): u64 {
        if (price == 0) {
            return 0
        };
        ((contribution as u128) * (PRICE_PRECISION as u128) / (price as u128)) as u64
    }

    // === Admin Functions ===

    /// Finalize launch and calculate final price
    public fun finalize<T, P>(
        launch: &mut FairLaunch<T, P>,
        _admin: &LaunchAdmin<T, P>,
        clock: &Clock,
    ) {
        let current_time = sui::clock::timestamp_ms(clock);

        assert!(current_time > launch.end_time, ELaunchNotEnded);
        assert!(!launch.finalized, EAlreadyFinalized);

        // Calculate final price: total_contributions / total_tokens
        let total_tokens = balance::value(&launch.tokens_for_sale);
        let final_price = if (total_tokens == 0) {
            0
        } else {
            ((launch.total_contributions as u128) * (PRICE_PRECISION as u128) / (total_tokens as u128)) as u64
        };

        launch.final_price = final_price;
        launch.finalized = true;

        event::emit(LaunchFinalized {
            launch_id: object::id(launch),
            total_contributions: launch.total_contributions,
            contributors: launch.contributor_count,
            final_price,
        });
    }

    /// Withdraw collected payments
    public fun withdraw_payments<T, P>(
        launch: &mut FairLaunch<T, P>,
        _admin: &LaunchAdmin<T, P>,
        ctx: &mut TxContext,
    ): Coin<P> {
        assert!(launch.finalized, ELaunchNotEnded);

        let amount = balance::value(&launch.payments_collected);
        let payments = balance::split(&mut launch.payments_collected, amount);

        coin::from_balance(payments, ctx)
    }

    // === View Functions ===

    /// Get launch info
    public fun launch_info<T, P>(launch: &FairLaunch<T, P>): (u64, u64, u64, u64, bool) {
        (
            balance::value(&launch.tokens_for_sale),
            launch.total_contributions,
            launch.contributor_count,
            launch.final_price,
            launch.finalized,
        )
    }

    /// Get contribution for address
    public fun get_contribution<T, P>(launch: &FairLaunch<T, P>, addr: address): u64 {
        if (table::contains(&launch.contributions, addr)) {
            *table::borrow(&launch.contributions, addr)
        } else {
            0
        }
    }

    /// Has claimed
    public fun has_claimed<T, P>(launch: &FairLaunch<T, P>, addr: address): bool {
        if (table::contains(&launch.claimed, addr)) {
            *table::borrow(&launch.claimed, addr)
        } else {
            false
        }
    }

    /// Calculate expected tokens for contribution
    public fun preview_tokens<T, P>(launch: &FairLaunch<T, P>, contribution: u64): u64 {
        let total_tokens = balance::value(&launch.tokens_for_sale);
        let projected_total = launch.total_contributions + contribution;

        if (projected_total == 0) {
            return 0
        };

        // tokens = contribution * total_tokens / projected_total_contributions
        ((contribution as u128) * (total_tokens as u128) / (projected_total as u128)) as u64
    }

    /// Is launch active
    public fun is_active<T, P>(launch: &FairLaunch<T, P>, clock: &Clock): bool {
        let current_time = sui::clock::timestamp_ms(clock);
        current_time >= launch.start_time &&
        current_time <= launch.end_time &&
        !launch.finalized
    }

    /// Get total contributions
    public fun total_contributions<T, P>(launch: &FairLaunch<T, P>): u64 {
        launch.total_contributions
    }

    /// Get contributor count
    public fun contributor_count<T, P>(launch: &FairLaunch<T, P>): u64 {
        launch.contributor_count
    }

    /// Get final price (only after finalized)
    public fun final_price<T, P>(launch: &FairLaunch<T, P>): u64 {
        launch.final_price
    }

    /// Get receipt info
    public fun receipt_info<T, P>(receipt: &ContributionReceipt<T, P>): (address, u64, u64) {
        (receipt.contributor, receipt.amount, receipt.contribution_time)
    }

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
    fun test_create_fair_launch() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let (launch, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Fair Launch"),
                tokens,
                0,
                1000000000, // 1000 seconds
                100, // min
                10000, // max
                scenario.ctx(),
            );

            let (tokens_avail, contributions, contributors, price, finalized) = launch_info(&launch);
            assert!(tokens_avail == 1000000, 0);
            assert!(contributions == 0, 1);
            assert!(contributors == 0, 2);
            assert!(price == 0, 3);
            assert!(!finalized, 4);

            transfer::public_share_object(launch);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_contribute() {
        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create launch
        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let (launch, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Fair Launch"),
                tokens,
                0,
                1000000000000,
                100,
                10000,
                scenario.ctx(),
            );

            transfer::public_share_object(launch);
            transfer::public_transfer(admin_cap, admin);
        };

        // Contribute
        scenario.next_tx(user);
        {
            let mut launch = scenario.take_shared<FairLaunch<SUI, SUI>>();
            let payment = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let clk = clock::create_for_testing(scenario.ctx());

            let receipt = contribute(&mut launch, payment, &clk, scenario.ctx());

            assert!(total_contributions(&launch) == 1000, 0);
            assert!(contributor_count(&launch) == 1, 1);
            assert!(get_contribution(&launch, user) == 1000, 2);

            let (contrib, amt, _) = receipt_info(&receipt);
            assert!(contrib == user, 3);
            assert!(amt == 1000, 4);

            transfer::public_transfer(receipt, user);
            clock::destroy_for_testing(clk);
            test_scenario::return_shared(launch);
        };

        scenario.end();
    }

    #[test]
    fun test_multiple_contributors() {
        let admin = @0xAD;
        let user1 = @0x1;
        let user2 = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // Create launch
        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let (launch, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Fair Launch"),
                tokens,
                0,
                1000000000000,
                100,
                10000,
                scenario.ctx(),
            );

            transfer::public_share_object(launch);
            transfer::public_transfer(admin_cap, admin);
        };

        // User 1 contributes
        scenario.next_tx(user1);
        {
            let mut launch = scenario.take_shared<FairLaunch<SUI, SUI>>();
            let payment = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let clk = clock::create_for_testing(scenario.ctx());

            let receipt = contribute(&mut launch, payment, &clk, scenario.ctx());

            transfer::public_transfer(receipt, user1);
            clock::destroy_for_testing(clk);
            test_scenario::return_shared(launch);
        };

        // User 2 contributes
        scenario.next_tx(user2);
        {
            let mut launch = scenario.take_shared<FairLaunch<SUI, SUI>>();
            let payment = coin::mint_for_testing<SUI>(2000, scenario.ctx());
            let clk = clock::create_for_testing(scenario.ctx());

            let receipt = contribute(&mut launch, payment, &clk, scenario.ctx());

            assert!(total_contributions(&launch) == 3000, 0);
            assert!(contributor_count(&launch) == 2, 1);

            transfer::public_transfer(receipt, user2);
            clock::destroy_for_testing(clk);
            test_scenario::return_shared(launch);
        };

        scenario.end();
    }

    #[test]
    fun test_preview_tokens() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let (launch, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Fair Launch"),
                tokens,
                0,
                1000000000000,
                100,
                10000,
                scenario.ctx(),
            );

            // If contribution is 1000 and no other contributions
            // Should get all tokens
            let preview = preview_tokens(&launch, 1000);
            assert!(preview == 1000000, 0);

            transfer::public_share_object(launch);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }
}
