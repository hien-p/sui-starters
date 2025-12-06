/// @title Sale
/// @notice Core token sale functionality
/// @dev Part of @sui-starters/launchpad package
module sui_starters_launchpad::sale {
    use std::string::String;
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;

    // === Errors ===

    const ESaleNotStarted: u64 = 0;
    const ESaleEnded: u64 = 1;
    const EHardCapReached: u64 = 2;
    const EMinPurchaseNotMet: u64 = 3;
    const EMaxPurchaseExceeded: u64 = 4;
    const ESaleNotEnded: u64 = 5;
    const EUnauthorized: u64 = 6;
    const ESalePaused: u64 = 7;

    // === Structs ===

    /// Token sale configuration
    public struct Sale<phantom T, phantom P> has key, store {
        id: UID,
        name: String,
        /// Tokens for sale
        tokens_for_sale: Balance<T>,
        /// Payment tokens collected
        payments_collected: Balance<P>,
        /// Price per token (in payment token units, scaled by 1e9)
        price: u64,
        /// Hard cap in payment tokens
        hard_cap: u64,
        /// Soft cap in payment tokens
        soft_cap: u64,
        /// Minimum purchase per user
        min_purchase: u64,
        /// Maximum purchase per user
        max_purchase: u64,
        /// Start timestamp (ms)
        start_time: u64,
        /// End timestamp (ms)
        end_time: u64,
        /// Total raised
        total_raised: u64,
        /// Total participants
        participant_count: u64,
        /// Is sale paused
        paused: bool,
        /// Is sale finalized
        finalized: bool,
    }

    /// Admin capability
    public struct SaleAdmin<phantom T, phantom P> has key, store {
        id: UID,
        sale_id: ID,
    }

    /// Purchase receipt
    public struct PurchaseReceipt<phantom T, phantom P> has key, store {
        id: UID,
        sale_id: ID,
        buyer: address,
        payment_amount: u64,
        token_amount: u64,
        purchase_time: u64,
        claimed: bool,
    }

    // === Events ===

    public struct SaleCreated has copy, drop {
        sale_id: ID,
        name: String,
        hard_cap: u64,
        start_time: u64,
        end_time: u64,
    }

    public struct TokensPurchased has copy, drop {
        sale_id: ID,
        buyer: address,
        payment_amount: u64,
        token_amount: u64,
    }

    public struct TokensClaimed has copy, drop {
        sale_id: ID,
        buyer: address,
        amount: u64,
    }

    public struct SaleFinalized has copy, drop {
        sale_id: ID,
        total_raised: u64,
        participants: u64,
        success: bool,
    }

    // === Constants ===

    const PRICE_PRECISION: u64 = 1000000000; // 1e9

    // === Create Functions ===

    /// Create a new token sale
    public fun new<T, P>(
        name: String,
        tokens: Coin<T>,
        price: u64,
        hard_cap: u64,
        soft_cap: u64,
        min_purchase: u64,
        max_purchase: u64,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext,
    ): (Sale<T, P>, SaleAdmin<T, P>) {
        let token_balance = coin::into_balance(tokens);

        let sale = Sale {
            id: object::new(ctx),
            name,
            tokens_for_sale: token_balance,
            payments_collected: balance::zero(),
            price,
            hard_cap,
            soft_cap,
            min_purchase,
            max_purchase,
            start_time,
            end_time,
            total_raised: 0,
            participant_count: 0,
            paused: false,
            finalized: false,
        };

        let sale_id = object::id(&sale);

        let admin = SaleAdmin {
            id: object::new(ctx),
            sale_id,
        };

        event::emit(SaleCreated {
            sale_id,
            name: sale.name,
            hard_cap,
            start_time,
            end_time,
        });

        (sale, admin)
    }

    // === Core Functions ===

    /// Purchase tokens
    public fun purchase<T, P>(
        sale: &mut Sale<T, P>,
        payment: Coin<P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): PurchaseReceipt<T, P> {
        let current_time = sui::clock::timestamp_ms(clock);

        assert!(!sale.paused, ESalePaused);
        assert!(current_time >= sale.start_time, ESaleNotStarted);
        assert!(current_time <= sale.end_time, ESaleEnded);

        let payment_amount = coin::value(&payment);
        assert!(payment_amount >= sale.min_purchase, EMinPurchaseNotMet);
        assert!(payment_amount <= sale.max_purchase, EMaxPurchaseExceeded);
        assert!(sale.total_raised + payment_amount <= sale.hard_cap, EHardCapReached);

        // Calculate tokens to receive
        let token_amount = calculate_tokens(payment_amount, sale.price);

        // Update sale state
        sale.total_raised = sale.total_raised + payment_amount;
        sale.participant_count = sale.participant_count + 1;

        // Collect payment
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut sale.payments_collected, payment_balance);

        let receipt = PurchaseReceipt {
            id: object::new(ctx),
            sale_id: object::id(sale),
            buyer: ctx.sender(),
            payment_amount,
            token_amount,
            purchase_time: current_time,
            claimed: false,
        };

        event::emit(TokensPurchased {
            sale_id: object::id(sale),
            buyer: ctx.sender(),
            payment_amount,
            token_amount,
        });

        receipt
    }

    /// Claim purchased tokens after sale ends
    public fun claim<T, P>(
        sale: &mut Sale<T, P>,
        receipt: &mut PurchaseReceipt<T, P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let current_time = sui::clock::timestamp_ms(clock);

        assert!(current_time > sale.end_time, ESaleNotEnded);
        assert!(!receipt.claimed, EUnauthorized);
        assert!(sale.total_raised >= sale.soft_cap, ESaleNotEnded); // Sale must meet soft cap

        receipt.claimed = true;

        let tokens = balance::split(&mut sale.tokens_for_sale, receipt.token_amount);

        event::emit(TokensClaimed {
            sale_id: object::id(sale),
            buyer: receipt.buyer,
            amount: receipt.token_amount,
        });

        coin::from_balance(tokens, ctx)
    }

    /// Refund if sale fails (doesn't meet soft cap)
    public fun refund<T, P>(
        sale: &mut Sale<T, P>,
        receipt: PurchaseReceipt<T, P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<P> {
        let current_time = sui::clock::timestamp_ms(clock);

        assert!(current_time > sale.end_time, ESaleNotEnded);
        assert!(sale.total_raised < sale.soft_cap, EUnauthorized); // Sale must have failed

        let PurchaseReceipt {
            id,
            sale_id: _,
            buyer: _,
            payment_amount,
            token_amount: _,
            purchase_time: _,
            claimed: _,
        } = receipt;

        object::delete(id);

        // Refund from collected payments
        let refund_balance = balance::split(&mut sale.payments_collected, payment_amount);
        coin::from_balance(refund_balance, ctx)
    }

    /// Calculate tokens for payment amount
    fun calculate_tokens(payment_amount: u64, price: u64): u64 {
        ((payment_amount as u128) * (PRICE_PRECISION as u128) / (price as u128)) as u64
    }

    // === Admin Functions ===

    /// Pause sale
    public fun pause<T, P>(
        sale: &mut Sale<T, P>,
        _admin: &SaleAdmin<T, P>,
    ) {
        sale.paused = true;
    }

    /// Unpause sale
    public fun unpause<T, P>(
        sale: &mut Sale<T, P>,
        _admin: &SaleAdmin<T, P>,
    ) {
        sale.paused = false;
    }

    /// Finalize sale and withdraw funds
    public fun finalize<T, P>(
        sale: &mut Sale<T, P>,
        _admin: &SaleAdmin<T, P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<P> {
        let current_time = sui::clock::timestamp_ms(clock);

        assert!(current_time > sale.end_time, ESaleNotEnded);
        assert!(!sale.finalized, EUnauthorized);
        assert!(sale.total_raised >= sale.soft_cap, EUnauthorized);

        sale.finalized = true;

        let amount = balance::value(&sale.payments_collected);
        let funds = balance::split(&mut sale.payments_collected, amount);

        event::emit(SaleFinalized {
            sale_id: object::id(sale),
            total_raised: sale.total_raised,
            participants: sale.participant_count,
            success: true,
        });

        coin::from_balance(funds, ctx)
    }

    /// Withdraw unsold tokens
    public fun withdraw_unsold<T, P>(
        sale: &mut Sale<T, P>,
        _admin: &SaleAdmin<T, P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let current_time = sui::clock::timestamp_ms(clock);

        assert!(current_time > sale.end_time, ESaleNotEnded);
        assert!(sale.finalized, EUnauthorized);

        let amount = balance::value(&sale.tokens_for_sale);
        let tokens = balance::split(&mut sale.tokens_for_sale, amount);

        coin::from_balance(tokens, ctx)
    }

    // === View Functions ===

    /// Get sale info
    public fun sale_info<T, P>(sale: &Sale<T, P>): (u64, u64, u64, u64, u64) {
        (
            balance::value(&sale.tokens_for_sale),
            sale.total_raised,
            sale.hard_cap,
            sale.soft_cap,
            sale.participant_count,
        )
    }

    /// Get total raised
    public fun total_raised<T, P>(sale: &Sale<T, P>): u64 {
        sale.total_raised
    }

    /// Get participant count
    public fun participant_count<T, P>(sale: &Sale<T, P>): u64 {
        sale.participant_count
    }

    /// Is sale active
    public fun is_active<T, P>(sale: &Sale<T, P>, clock: &Clock): bool {
        let current_time = sui::clock::timestamp_ms(clock);
        !sale.paused &&
        current_time >= sale.start_time &&
        current_time <= sale.end_time &&
        sale.total_raised < sale.hard_cap
    }

    /// Is soft cap reached
    public fun soft_cap_reached<T, P>(sale: &Sale<T, P>): bool {
        sale.total_raised >= sale.soft_cap
    }

    /// Get receipt info
    public fun receipt_info<T, P>(receipt: &PurchaseReceipt<T, P>): (u64, u64, bool) {
        (receipt.payment_amount, receipt.token_amount, receipt.claimed)
    }

    /// Price precision constant
    public fun price_precision(): u64 { PRICE_PRECISION }

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
    fun test_create_sale() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let (sale, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Test Sale"),
                tokens,
                1000000000, // 1:1 price
                100000, // 100k hard cap
                50000, // 50k soft cap
                100, // min 100
                10000, // max 10k
                0,
                1000000000, // 1000 seconds
                scenario.ctx(),
            );

            let (tokens_available, raised, hard, soft, participants) = sale_info(&sale);
            assert!(tokens_available == 1000000, 0);
            assert!(raised == 0, 1);
            assert!(hard == 100000, 2);
            assert!(soft == 50000, 3);
            assert!(participants == 0, 4);

            transfer::public_share_object(sale);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_purchase() {
        let admin = @0xAD;
        let buyer = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create sale
        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let (sale, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Test Sale"),
                tokens,
                1000000000,
                100000,
                50000,
                100,
                10000,
                0,
                1000000000000,
                scenario.ctx(),
            );

            transfer::public_share_object(sale);
            transfer::public_transfer(admin_cap, admin);
        };

        // Purchase
        scenario.next_tx(buyer);
        {
            let mut sale = scenario.take_shared<Sale<SUI, SUI>>();
            let payment = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let clk = clock::create_for_testing(scenario.ctx());

            let receipt = purchase(&mut sale, payment, &clk, scenario.ctx());

            let (payment_amt, token_amt, claimed) = receipt_info(&receipt);
            assert!(payment_amt == 1000, 0);
            assert!(token_amt == 1000, 1);
            assert!(!claimed, 2);
            assert!(total_raised(&sale) == 1000, 3);
            assert!(participant_count(&sale) == 1, 4);

            transfer::public_transfer(receipt, buyer);
            clock::destroy_for_testing(clk);
            test_scenario::return_shared(sale);
        };

        scenario.end();
    }

    #[test]
    fun test_price_calculation() {
        // 1:1 price
        assert!(calculate_tokens(1000, 1000000000) == 1000, 0);

        // 2:1 price (2 payment = 1 token)
        assert!(calculate_tokens(2000, 2000000000) == 1000, 1);

        // 1:2 price (1 payment = 2 tokens)
        assert!(calculate_tokens(1000, 500000000) == 2000, 2);
    }
}
