/// @title Flash Loan
/// @notice Flash loan functionality for DeFi applications
/// @dev Part of @sui-starters/defi package
module sui_starters_defi::flash_loan {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;

    // === Errors ===

    /// Insufficient liquidity
    const EInsufficientLiquidity: u64 = 0;

    /// Loan not repaid
    const ELoanNotRepaid: u64 = 1;

    /// Invalid receipt
    const EInvalidReceipt: u64 = 2;

    /// Pool is paused
    const EPoolPaused: u64 = 3;

    /// Invalid amount
    const EInvalidAmount: u64 = 4;

    /// Fee too high
    const EFeeTooHigh: u64 = 5;

    // === Constants ===

    /// Maximum fee in basis points (10%)
    const MAX_FEE_BPS: u64 = 1000;

    // === Structs ===

    /// Flash loan pool for a token type
    public struct FlashLoanPool<phantom T> has key, store {
        id: UID,
        /// Pool liquidity
        liquidity: Balance<T>,
        /// Fee in basis points
        fee_bps: u64,
        /// Total fees collected
        total_fees: u64,
        /// Total loans issued
        total_loans: u64,
        /// Is pool paused
        paused: bool,
    }

    /// Receipt for tracking flash loan repayment
    /// Hot potato pattern - must be consumed in same transaction
    public struct FlashLoanReceipt<phantom T> {
        /// Pool ID
        pool_id: ID,
        /// Borrowed amount
        borrow_amount: u64,
        /// Required repayment (amount + fee)
        repay_amount: u64,
    }

    /// Pool statistics
    public struct PoolStats has copy, drop {
        liquidity: u64,
        fee_bps: u64,
        total_fees: u64,
        total_loans: u64,
        paused: bool,
    }

    // === Events ===

    /// Emitted when flash loan is taken
    public struct FlashLoanTaken has copy, drop {
        pool_id: ID,
        borrower: address,
        amount: u64,
        fee: u64,
    }

    /// Emitted when flash loan is repaid
    public struct FlashLoanRepaid has copy, drop {
        pool_id: ID,
        borrower: address,
        amount: u64,
        fee_paid: u64,
    }

    /// Emitted when liquidity is added
    public struct LiquidityAdded has copy, drop {
        pool_id: ID,
        provider: address,
        amount: u64,
    }

    /// Emitted when liquidity is removed
    public struct LiquidityRemoved has copy, drop {
        pool_id: ID,
        provider: address,
        amount: u64,
    }

    // === Create Functions ===

    /// Create a new flash loan pool
    public fun new<T>(fee_bps: u64, ctx: &mut TxContext): FlashLoanPool<T> {
        assert!(fee_bps <= MAX_FEE_BPS, EFeeTooHigh);

        FlashLoanPool<T> {
            id: object::new(ctx),
            liquidity: balance::zero(),
            fee_bps,
            total_fees: 0,
            total_loans: 0,
            paused: false,
        }
    }

    /// Create pool with default fee (0.09% = 9 bps)
    public fun new_default<T>(ctx: &mut TxContext): FlashLoanPool<T> {
        new(9, ctx)
    }

    // === Flash Loan Functions ===

    /// Borrow tokens from the pool (flash loan)
    /// Returns borrowed tokens and a receipt that must be consumed by repay()
    public fun borrow<T>(
        pool: &mut FlashLoanPool<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): (Coin<T>, FlashLoanReceipt<T>) {
        assert!(!pool.paused, EPoolPaused);
        assert!(amount > 0, EInvalidAmount);
        assert!(balance::value(&pool.liquidity) >= amount, EInsufficientLiquidity);

        // Calculate fee
        let fee = (amount * pool.fee_bps + 9999) / 10000; // Round up
        let repay_amount = amount + fee;

        // Take tokens from pool
        let borrowed = coin::from_balance(
            balance::split(&mut pool.liquidity, amount),
            ctx,
        );

        // Create receipt (hot potato)
        let receipt = FlashLoanReceipt<T> {
            pool_id: object::id(pool),
            borrow_amount: amount,
            repay_amount,
        };

        pool.total_loans = pool.total_loans + 1;

        event::emit(FlashLoanTaken {
            pool_id: object::id(pool),
            borrower: ctx.sender(),
            amount,
            fee,
        });

        (borrowed, receipt)
    }

    /// Repay the flash loan
    /// Must be called in the same transaction as borrow()
    public fun repay<T>(
        pool: &mut FlashLoanPool<T>,
        receipt: FlashLoanReceipt<T>,
        payment: Coin<T>,
        ctx: &TxContext,
    ) {
        let FlashLoanReceipt {
            pool_id,
            borrow_amount,
            repay_amount,
        } = receipt;

        assert!(pool_id == object::id(pool), EInvalidReceipt);
        assert!(coin::value(&payment) >= repay_amount, ELoanNotRepaid);

        let fee_paid = repay_amount - borrow_amount;
        pool.total_fees = pool.total_fees + fee_paid;

        // Return liquidity to pool
        balance::join(&mut pool.liquidity, coin::into_balance(payment));

        event::emit(FlashLoanRepaid {
            pool_id: object::id(pool),
            borrower: ctx.sender(),
            amount: borrow_amount,
            fee_paid,
        });
    }

    // === Liquidity Functions ===

    /// Add liquidity to the pool
    public fun add_liquidity<T>(
        pool: &mut FlashLoanPool<T>,
        tokens: Coin<T>,
        ctx: &TxContext,
    ) {
        let amount = coin::value(&tokens);
        assert!(amount > 0, EInvalidAmount);

        balance::join(&mut pool.liquidity, coin::into_balance(tokens));

        event::emit(LiquidityAdded {
            pool_id: object::id(pool),
            provider: ctx.sender(),
            amount,
        });
    }

    /// Remove liquidity from the pool
    public fun remove_liquidity<T>(
        pool: &mut FlashLoanPool<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(balance::value(&pool.liquidity) >= amount, EInsufficientLiquidity);

        let tokens = coin::from_balance(
            balance::split(&mut pool.liquidity, amount),
            ctx,
        );

        event::emit(LiquidityRemoved {
            pool_id: object::id(pool),
            provider: ctx.sender(),
            amount,
        });

        tokens
    }

    // === Admin Functions ===

    /// Set fee
    public fun set_fee<T>(pool: &mut FlashLoanPool<T>, fee_bps: u64) {
        assert!(fee_bps <= MAX_FEE_BPS, EFeeTooHigh);
        pool.fee_bps = fee_bps;
    }

    /// Pause pool
    public fun pause<T>(pool: &mut FlashLoanPool<T>) {
        pool.paused = true;
    }

    /// Unpause pool
    public fun unpause<T>(pool: &mut FlashLoanPool<T>) {
        pool.paused = false;
    }

    // === View Functions ===

    /// Get pool liquidity
    public fun liquidity<T>(pool: &FlashLoanPool<T>): u64 {
        balance::value(&pool.liquidity)
    }

    /// Get pool fee
    public fun fee_bps<T>(pool: &FlashLoanPool<T>): u64 {
        pool.fee_bps
    }

    /// Get total fees collected
    public fun total_fees<T>(pool: &FlashLoanPool<T>): u64 {
        pool.total_fees
    }

    /// Get total loans issued
    public fun total_loans<T>(pool: &FlashLoanPool<T>): u64 {
        pool.total_loans
    }

    /// Check if pool is paused
    public fun is_paused<T>(pool: &FlashLoanPool<T>): bool {
        pool.paused
    }

    /// Calculate fee for an amount
    public fun calculate_fee<T>(pool: &FlashLoanPool<T>, amount: u64): u64 {
        (amount * pool.fee_bps + 9999) / 10000 // Round up
    }

    /// Calculate total repayment for an amount
    public fun calculate_repay_amount<T>(pool: &FlashLoanPool<T>, amount: u64): u64 {
        amount + calculate_fee(pool, amount)
    }

    /// Get pool stats
    public fun get_stats<T>(pool: &FlashLoanPool<T>): PoolStats {
        PoolStats {
            liquidity: balance::value(&pool.liquidity),
            fee_bps: pool.fee_bps,
            total_fees: pool.total_fees,
            total_loans: pool.total_loans,
            paused: pool.paused,
        }
    }

    /// Get borrow amount from receipt
    public fun receipt_borrow_amount<T>(receipt: &FlashLoanReceipt<T>): u64 {
        receipt.borrow_amount
    }

    /// Get repay amount from receipt
    public fun receipt_repay_amount<T>(receipt: &FlashLoanReceipt<T>): u64 {
        receipt.repay_amount
    }

    /// Get max fee in basis points
    public fun max_fee_bps(): u64 {
        MAX_FEE_BPS
    }

    // === Tests ===

    #[test]
    fun test_create_pool() {
        use sui::test_scenario;
        use sui::sui::SUI;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new_default<SUI>(scenario.ctx());

            assert!(liquidity(&pool) == 0, 0);
            assert!(fee_bps(&pool) == 9, 1);
            assert!(total_loans(&pool) == 0, 2);

            transfer::public_share_object(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_add_remove_liquidity() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new_default<SUI>(scenario.ctx());
            transfer::public_share_object(pool);
        };

        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<FlashLoanPool<SUI>>();

            // Add liquidity
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            add_liquidity(&mut pool, tokens, scenario.ctx());

            assert!(liquidity(&pool) == 10000, 0);

            // Remove some liquidity
            let removed = remove_liquidity(&mut pool, 3000, scenario.ctx());
            assert!(coin::value(&removed) == 3000, 1);
            assert!(liquidity(&pool) == 7000, 2);

            coin::burn_for_testing(removed);
            test_scenario::return_shared(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_flash_loan() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new<SUI>(100, scenario.ctx()); // 1% fee
            transfer::public_share_object(pool);
        };

        // Add liquidity
        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<FlashLoanPool<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            add_liquidity(&mut pool, tokens, scenario.ctx());
            test_scenario::return_shared(pool);
        };

        // Flash loan
        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<FlashLoanPool<SUI>>();

            // Borrow 1000
            let (borrowed, receipt) = borrow(&mut pool, 1000, scenario.ctx());

            assert!(coin::value(&borrowed) == 1000, 0);
            assert!(receipt_borrow_amount(&receipt) == 1000, 1);
            assert!(receipt_repay_amount(&receipt) == 1010, 2); // 1000 + 1% fee

            // Simulate doing something with borrowed funds...
            // In real scenario, would do arbitrage, liquidation, etc.

            // Repay with profit (need extra for fee)
            coin::burn_for_testing(borrowed);
            let repayment = coin::mint_for_testing<SUI>(1010, scenario.ctx());
            repay(&mut pool, receipt, repayment, scenario.ctx());

            // Check pool state
            assert!(liquidity(&pool) == 10010, 3); // Original + fee
            assert!(total_fees(&pool) == 10, 4);
            assert!(total_loans(&pool) == 1, 5);

            test_scenario::return_shared(pool);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ELoanNotRepaid)]
    fun test_insufficient_repayment_fails() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new<SUI>(100, scenario.ctx());
            transfer::public_share_object(pool);
        };

        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<FlashLoanPool<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            add_liquidity(&mut pool, tokens, scenario.ctx());
            test_scenario::return_shared(pool);
        };

        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<FlashLoanPool<SUI>>();

            let (borrowed, receipt) = borrow(&mut pool, 1000, scenario.ctx());

            // Try to repay less than required (should fail)
            coin::burn_for_testing(borrowed);
            let repayment = coin::mint_for_testing<SUI>(1000, scenario.ctx()); // Missing fee
            repay(&mut pool, receipt, repayment, scenario.ctx());

            test_scenario::return_shared(pool);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EInsufficientLiquidity)]
    fun test_insufficient_liquidity_fails() {
        use sui::test_scenario;
        use sui::sui::SUI;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new_default<SUI>(scenario.ctx());
            transfer::public_share_object(pool);
        };

        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<FlashLoanPool<SUI>>();

            // Try to borrow from empty pool (should fail)
            let (borrowed, receipt) = borrow(&mut pool, 1000, scenario.ctx());

            // Cleanup (won't reach here)
            coin::burn_for_testing(borrowed);
            let repayment = coin::mint_for_testing<SUI>(1010, scenario.ctx());
            repay(&mut pool, receipt, repayment, scenario.ctx());

            test_scenario::return_shared(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_fee_calculation() {
        use sui::test_scenario;
        use sui::sui::SUI;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new<SUI>(100, scenario.ctx()); // 1% fee

            // 1% of 1000 = 10
            assert!(calculate_fee(&pool, 1000) == 10, 0);

            // 1% of 999 = 10 (rounded up)
            assert!(calculate_fee(&pool, 999) == 10, 1);

            // Total repayment
            assert!(calculate_repay_amount(&pool, 1000) == 1010, 2);

            transfer::public_share_object(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_pause_unpause() {
        use sui::test_scenario;
        use sui::sui::SUI;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut pool = new_default<SUI>(scenario.ctx());

            assert!(!is_paused(&pool), 0);

            pause(&mut pool);
            assert!(is_paused(&pool), 1);

            unpause(&mut pool);
            assert!(!is_paused(&pool), 2);

            transfer::public_share_object(pool);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EPoolPaused)]
    fun test_borrow_paused_fails() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let pool = new_default<SUI>(scenario.ctx());
            transfer::public_share_object(pool);
        };

        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<FlashLoanPool<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            add_liquidity(&mut pool, tokens, scenario.ctx());

            // Pause pool
            pause(&mut pool);

            // Try to borrow (should fail)
            let (borrowed, receipt) = borrow(&mut pool, 1000, scenario.ctx());

            // Cleanup (won't reach here)
            coin::burn_for_testing(borrowed);
            let repayment = coin::mint_for_testing<SUI>(1001, scenario.ctx());
            repay(&mut pool, receipt, repayment, scenario.ctx());

            test_scenario::return_shared(pool);
        };

        scenario.end();
    }
}
