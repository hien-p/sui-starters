/// @title Dutch Auction
/// @notice Descending price auction for token sales
/// @dev Part of @sui-starters/launchpad package
module sui_starters_launchpad::dutch_auction {
    use std::string::String;
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;

    // === Errors ===

    const EAuctionNotStarted: u64 = 0;
    const EAuctionEnded: u64 = 1;
    const ESoldOut: u64 = 2;
    const EInsufficientPayment: u64 = 3;
    const EAuctionNotEnded: u64 = 4;
    const EAlreadyFinalized: u64 = 5;
    const EInvalidPriceRange: u64 = 6;

    // === Structs ===

    /// Dutch auction configuration
    public struct DutchAuction<phantom T, phantom P> has key, store {
        id: UID,
        name: String,
        /// Tokens for sale
        tokens_for_sale: Balance<T>,
        /// Payments collected
        payments_collected: Balance<P>,
        /// Starting price (high)
        start_price: u64,
        /// Ending/reserve price (low)
        end_price: u64,
        /// Price decrease per second (scaled by 1e9)
        price_decay_per_second: u64,
        /// Start timestamp (ms)
        start_time: u64,
        /// End timestamp (ms)
        end_time: u64,
        /// Total tokens for sale
        total_supply: u64,
        /// Tokens sold
        tokens_sold: u64,
        /// Final clearing price (set when finalized)
        clearing_price: u64,
        /// Is finalized
        finalized: bool,
    }

    /// Admin capability
    public struct AuctionAdmin<phantom T, phantom P> has key, store {
        id: UID,
        auction_id: ID,
    }

    /// Bid receipt
    public struct BidReceipt<phantom T, phantom P> has key, store {
        id: UID,
        auction_id: ID,
        bidder: address,
        /// Amount paid
        amount_paid: u64,
        /// Price at time of bid
        bid_price: u64,
        /// Tokens purchased
        tokens_purchased: u64,
        /// Bid timestamp
        bid_time: u64,
        /// Refund amount (difference between bid price and clearing price)
        refund_amount: u64,
        /// Has claimed refund
        refund_claimed: bool,
    }

    // === Events ===

    public struct AuctionCreated has copy, drop {
        auction_id: ID,
        name: String,
        start_price: u64,
        end_price: u64,
        total_supply: u64,
    }

    public struct BidPlaced has copy, drop {
        auction_id: ID,
        bidder: address,
        amount: u64,
        price: u64,
        tokens: u64,
    }

    public struct AuctionFinalized has copy, drop {
        auction_id: ID,
        clearing_price: u64,
        tokens_sold: u64,
        total_raised: u64,
    }

    // === Constants ===

    const PRICE_PRECISION: u64 = 1000000000; // 1e9

    // === Create Functions ===

    /// Create a new Dutch auction
    public fun new<T, P>(
        name: String,
        tokens: Coin<T>,
        start_price: u64,
        end_price: u64,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext,
    ): (DutchAuction<T, P>, AuctionAdmin<T, P>) {
        assert!(start_price > end_price, EInvalidPriceRange);

        let total_supply = coin::value(&tokens);
        let token_balance = coin::into_balance(tokens);

        // Calculate decay rate
        let duration_seconds = (end_time - start_time) / 1000;
        let price_diff = start_price - end_price;
        let decay_per_second = price_diff / duration_seconds;

        let auction = DutchAuction {
            id: object::new(ctx),
            name,
            tokens_for_sale: token_balance,
            payments_collected: balance::zero(),
            start_price,
            end_price,
            price_decay_per_second: decay_per_second,
            start_time,
            end_time,
            total_supply,
            tokens_sold: 0,
            clearing_price: 0,
            finalized: false,
        };

        let auction_id = object::id(&auction);

        let admin = AuctionAdmin {
            id: object::new(ctx),
            auction_id,
        };

        event::emit(AuctionCreated {
            auction_id,
            name: auction.name,
            start_price,
            end_price,
            total_supply,
        });

        (auction, admin)
    }

    // === Core Functions ===

    /// Place a bid at current price
    public fun bid<T, P>(
        auction: &mut DutchAuction<T, P>,
        payment: Coin<P>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Coin<T>, BidReceipt<T, P>) {
        let current_time = sui::clock::timestamp_ms(clock);

        assert!(current_time >= auction.start_time, EAuctionNotStarted);
        assert!(current_time <= auction.end_time, EAuctionEnded);

        let available_tokens = balance::value(&auction.tokens_for_sale);
        assert!(available_tokens > 0, ESoldOut);

        // Get current price
        let current_price = get_current_price(auction, current_time);

        let payment_amount = coin::value(&payment);

        // Calculate tokens to receive
        let tokens_to_buy = calculate_tokens_for_payment(payment_amount, current_price);
        let actual_tokens = if (tokens_to_buy > available_tokens) {
            available_tokens
        } else {
            tokens_to_buy
        };

        // Calculate actual payment needed
        let actual_payment = calculate_payment_for_tokens(actual_tokens, current_price);
        assert!(payment_amount >= actual_payment, EInsufficientPayment);

        // Handle payment
        let mut payment_balance = coin::into_balance(payment);

        // Return excess payment
        let excess = payment_amount - actual_payment;
        let excess_balance = if (excess > 0) {
            balance::split(&mut payment_balance, excess)
        } else {
            balance::zero()
        };

        balance::join(&mut auction.payments_collected, payment_balance);

        // Transfer tokens
        let tokens = balance::split(&mut auction.tokens_for_sale, actual_tokens);
        auction.tokens_sold = auction.tokens_sold + actual_tokens;

        let receipt = BidReceipt {
            id: object::new(ctx),
            auction_id: object::id(auction),
            bidder: ctx.sender(),
            amount_paid: actual_payment,
            bid_price: current_price,
            tokens_purchased: actual_tokens,
            bid_time: current_time,
            refund_amount: 0, // Will be calculated when auction finalizes
            refund_claimed: false,
        };

        event::emit(BidPlaced {
            auction_id: object::id(auction),
            bidder: ctx.sender(),
            amount: actual_payment,
            price: current_price,
            tokens: actual_tokens,
        });

        // Return tokens and excess payment combined into receipt
        let token_coin = coin::from_balance(tokens, ctx);
        let excess_coin = coin::from_balance(excess_balance, ctx);
        // Merge excess back to buyer
        if (coin::value(&excess_coin) > 0) {
            transfer::public_transfer(excess_coin, ctx.sender());
        } else {
            coin::destroy_zero(excess_coin);
        };

        (token_coin, receipt)
    }

    /// Calculate current price based on time elapsed
    fun get_current_price<T, P>(auction: &DutchAuction<T, P>, current_time: u64): u64 {
        if (current_time >= auction.end_time) {
            return auction.end_price
        };

        let elapsed_seconds = (current_time - auction.start_time) / 1000;
        let price_decrease = elapsed_seconds * auction.price_decay_per_second;

        if (auction.start_price > price_decrease + auction.end_price) {
            auction.start_price - price_decrease
        } else {
            auction.end_price
        }
    }

    /// Calculate tokens for payment amount
    fun calculate_tokens_for_payment(payment: u64, price: u64): u64 {
        ((payment as u128) * (PRICE_PRECISION as u128) / (price as u128)) as u64
    }

    /// Calculate payment for token amount
    fun calculate_payment_for_tokens(tokens: u64, price: u64): u64 {
        ((tokens as u128) * (price as u128) / (PRICE_PRECISION as u128)) as u64
    }

    // === Admin Functions ===

    /// Finalize auction and set clearing price
    public fun finalize<T, P>(
        auction: &mut DutchAuction<T, P>,
        _admin: &AuctionAdmin<T, P>,
        clock: &Clock,
    ) {
        let current_time = sui::clock::timestamp_ms(clock);

        // Can finalize if ended OR sold out
        let ended = current_time > auction.end_time;
        let sold_out = balance::value(&auction.tokens_for_sale) == 0;

        assert!(ended || sold_out, EAuctionNotEnded);
        assert!(!auction.finalized, EAlreadyFinalized);

        // Set clearing price to current/final price
        auction.clearing_price = get_current_price(auction, current_time);
        auction.finalized = true;

        event::emit(AuctionFinalized {
            auction_id: object::id(auction),
            clearing_price: auction.clearing_price,
            tokens_sold: auction.tokens_sold,
            total_raised: balance::value(&auction.payments_collected),
        });
    }

    /// Withdraw collected payments
    public fun withdraw_payments<T, P>(
        auction: &mut DutchAuction<T, P>,
        _admin: &AuctionAdmin<T, P>,
        ctx: &mut TxContext,
    ): Coin<P> {
        assert!(auction.finalized, EAuctionNotEnded);

        let amount = balance::value(&auction.payments_collected);
        let payments = balance::split(&mut auction.payments_collected, amount);

        coin::from_balance(payments, ctx)
    }

    /// Withdraw unsold tokens
    public fun withdraw_unsold<T, P>(
        auction: &mut DutchAuction<T, P>,
        _admin: &AuctionAdmin<T, P>,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(auction.finalized, EAuctionNotEnded);

        let amount = balance::value(&auction.tokens_for_sale);
        let tokens = balance::split(&mut auction.tokens_for_sale, amount);

        coin::from_balance(tokens, ctx)
    }

    // === View Functions ===

    /// Get current price
    public fun current_price<T, P>(auction: &DutchAuction<T, P>, clock: &Clock): u64 {
        let current_time = sui::clock::timestamp_ms(clock);
        get_current_price(auction, current_time)
    }

    /// Get auction info
    public fun auction_info<T, P>(auction: &DutchAuction<T, P>): (u64, u64, u64, u64, u64) {
        (
            auction.start_price,
            auction.end_price,
            auction.total_supply,
            auction.tokens_sold,
            balance::value(&auction.payments_collected),
        )
    }

    /// Get available tokens
    public fun available_tokens<T, P>(auction: &DutchAuction<T, P>): u64 {
        balance::value(&auction.tokens_for_sale)
    }

    /// Get tokens sold
    public fun tokens_sold<T, P>(auction: &DutchAuction<T, P>): u64 {
        auction.tokens_sold
    }

    /// Get clearing price (only after finalized)
    public fun clearing_price<T, P>(auction: &DutchAuction<T, P>): u64 {
        auction.clearing_price
    }

    /// Is auction active
    public fun is_active<T, P>(auction: &DutchAuction<T, P>, clock: &Clock): bool {
        let current_time = sui::clock::timestamp_ms(clock);
        current_time >= auction.start_time &&
        current_time <= auction.end_time &&
        balance::value(&auction.tokens_for_sale) > 0
    }

    /// Is finalized
    public fun is_finalized<T, P>(auction: &DutchAuction<T, P>): bool {
        auction.finalized
    }

    /// Get receipt info
    public fun receipt_info<T, P>(receipt: &BidReceipt<T, P>): (u64, u64, u64, u64) {
        (receipt.amount_paid, receipt.bid_price, receipt.tokens_purchased, receipt.bid_time)
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
    fun test_create_auction() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let (auction, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Test Auction"),
                tokens,
                2000000000, // Start: 2 tokens per 1 payment
                1000000000, // End: 1 token per 1 payment
                0, // Start now
                1000000, // End in 1000 seconds
                scenario.ctx(),
            );

            let (start, end, supply, sold, raised) = auction_info(&auction);
            assert!(start == 2000000000, 0);
            assert!(end == 1000000000, 1);
            assert!(supply == 1000000, 2);
            assert!(sold == 0, 3);
            assert!(raised == 0, 4);

            transfer::public_share_object(auction);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_price_decay() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        // Create auction
        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let (auction, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Test Auction"),
                tokens,
                2000000000, // Start: 2
                1000000000, // End: 1
                0,
                1000000, // 1000 seconds
                scenario.ctx(),
            );

            transfer::public_share_object(auction);
            transfer::public_transfer(admin_cap, admin);
        };

        // Check price at different times
        scenario.next_tx(admin);
        {
            let auction = scenario.take_shared<DutchAuction<SUI, SUI>>();

            // At start
            let mut clk = clock::create_for_testing(scenario.ctx());
            let price_start = current_price(&auction, &clk);
            assert!(price_start == 2000000000, 0);

            // At middle (500 seconds)
            clock::set_for_testing(&mut clk, 500000);
            let price_mid = current_price(&auction, &clk);
            assert!(price_mid == 1500000000, 1);

            // At end
            clock::set_for_testing(&mut clk, 1000000);
            let price_end = current_price(&auction, &clk);
            assert!(price_end == 1000000000, 2);

            clock::destroy_for_testing(clk);
            test_scenario::return_shared(auction);
        };

        scenario.end();
    }

    #[test]
    fun test_bid() {
        let admin = @0xAD;
        let bidder = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create auction
        {
            let tokens = coin::mint_for_testing<SUI>(1000000, scenario.ctx());
            let (auction, admin_cap) = new<SUI, SUI>(
                string::utf8(b"Test Auction"),
                tokens,
                1000000000, // 1:1 at start
                500000000, // 2:1 at end
                0,
                1000000,
                scenario.ctx(),
            );

            transfer::public_share_object(auction);
            transfer::public_transfer(admin_cap, admin);
        };

        // Place bid
        scenario.next_tx(bidder);
        {
            let mut auction = scenario.take_shared<DutchAuction<SUI, SUI>>();
            let payment = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let clk = clock::create_for_testing(scenario.ctx());

            let (tokens, receipt) = bid(&mut auction, payment, &clk, scenario.ctx());

            // At 1:1 price, 1000 payment = 1000 tokens
            assert!(coin::value(&tokens) == 1000, 0);
            assert!(tokens_sold(&auction) == 1000, 1);

            let (paid, price, purchased, _) = receipt_info(&receipt);
            assert!(paid == 1000, 2);
            assert!(price == 1000000000, 3);
            assert!(purchased == 1000, 4);

            transfer::public_transfer(tokens, bidder);
            transfer::public_transfer(receipt, bidder);
            clock::destroy_for_testing(clk);
            test_scenario::return_shared(auction);
        };

        scenario.end();
    }
}
