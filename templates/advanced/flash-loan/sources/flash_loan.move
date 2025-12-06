/// @title Flash Loan
/// @notice Uncollateralized loans repaid within same transaction
/// @dev Demonstrates hot potato pattern, reentrancy safety
module flash_loan::flash_loan {
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};

    // === Errors ===

    const EInsufficientLiquidity: u64 = 0;
    const ERepaymentInsufficient: u64 = 1;
    const ELoanNotRepaid: u64 = 2;

    // === Constants ===

    const FEE_BPS: u64 = 9; // 0.09% flash loan fee

    // === Structs ===

    /// Flash loan pool
    public struct FlashLoanPool<phantom T> has key {
        id: UID,
        /// Available liquidity
        liquidity: Balance<T>,
        /// Total fees collected
        total_fees: u64,
        /// Total loans executed
        total_loans: u64,
    }

    /// Hot potato receipt - must be destroyed by repaying
    public struct FlashLoanReceipt<phantom T> {
        /// Pool ID
        pool_id: ID,
        /// Loan amount
        loan_amount: u64,
        /// Required repayment (loan + fee)
        repay_amount: u64,
    }

    // === Events ===

    public struct PoolCreated has copy, drop {
        pool_id: ID,
        initial_liquidity: u64,
    }

    public struct FlashLoanExecuted has copy, drop {
        pool_id: ID,
        borrower: address,
        amount: u64,
        fee: u64,
    }

    public struct LiquidityAdded has copy, drop {
        pool_id: ID,
        amount: u64,
    }

    public struct LiquidityRemoved has copy, drop {
        pool_id: ID,
        amount: u64,
    }

    // === Entry Functions ===

    /// Create a new flash loan pool
    public fun create_pool<T>(
        initial_liquidity: Coin<T>,
        ctx: &mut TxContext,
    ) {
        let amount = coin::value(&initial_liquidity);

        let pool = FlashLoanPool {
            id: object::new(ctx),
            liquidity: coin::into_balance(initial_liquidity),
            total_fees: 0,
            total_loans: 0,
        };

        event::emit(PoolCreated {
            pool_id: object::id(&pool),
            initial_liquidity: amount,
        });

        transfer::share_object(pool);
    }

    /// Take a flash loan - returns coins and a receipt that must be repaid
    public fun borrow<T>(
        pool: &mut FlashLoanPool<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): (Coin<T>, FlashLoanReceipt<T>) {
        assert!(balance::value(&pool.liquidity) >= amount, EInsufficientLiquidity);

        // Calculate fee
        let fee = (amount * FEE_BPS) / 10000;
        let repay_amount = amount + fee;

        // Extract loan
        let loan_balance = balance::split(&mut pool.liquidity, amount);
        let loan_coin = coin::from_balance(loan_balance, ctx);

        // Create receipt (hot potato)
        let receipt = FlashLoanReceipt {
            pool_id: object::id(pool),
            loan_amount: amount,
            repay_amount,
        };

        (loan_coin, receipt)
    }

    /// Repay flash loan - destroys the receipt
    public fun repay<T>(
        pool: &mut FlashLoanPool<T>,
        receipt: FlashLoanReceipt<T>,
        repayment: Coin<T>,
        ctx: &TxContext,
    ) {
        let FlashLoanReceipt {
            pool_id,
            loan_amount,
            repay_amount,
        } = receipt;

        assert!(pool_id == object::id(pool), ELoanNotRepaid);
        assert!(coin::value(&repayment) >= repay_amount, ERepaymentInsufficient);

        let fee = repay_amount - loan_amount;

        // Add repayment to pool
        balance::join(&mut pool.liquidity, coin::into_balance(repayment));

        // Update stats
        pool.total_fees = pool.total_fees + fee;
        pool.total_loans = pool.total_loans + 1;

        event::emit(FlashLoanExecuted {
            pool_id,
            borrower: ctx.sender(),
            amount: loan_amount,
            fee,
        });
    }

    /// Add liquidity to pool
    public entry fun add_liquidity<T>(
        pool: &mut FlashLoanPool<T>,
        liquidity: Coin<T>,
    ) {
        let amount = coin::value(&liquidity);

        balance::join(&mut pool.liquidity, coin::into_balance(liquidity));

        event::emit(LiquidityAdded {
            pool_id: object::id(pool),
            amount,
        });
    }

    /// Remove liquidity from pool (for pool creator/admin)
    public fun remove_liquidity<T>(
        pool: &mut FlashLoanPool<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(balance::value(&pool.liquidity) >= amount, EInsufficientLiquidity);

        let removed = balance::split(&mut pool.liquidity, amount);

        event::emit(LiquidityRemoved {
            pool_id: object::id(pool),
            amount,
        });

        coin::from_balance(removed, ctx)
    }

    // === View Functions ===

    /// Get available liquidity
    public fun available_liquidity<T>(pool: &FlashLoanPool<T>): u64 {
        balance::value(&pool.liquidity)
    }

    /// Get total fees collected
    public fun total_fees<T>(pool: &FlashLoanPool<T>): u64 {
        pool.total_fees
    }

    /// Get total loans executed
    public fun total_loans<T>(pool: &FlashLoanPool<T>): u64 {
        pool.total_loans
    }

    /// Calculate fee for loan amount
    public fun calculate_fee(amount: u64): u64 {
        (amount * FEE_BPS) / 10000
    }

    /// Get receipt info
    public fun receipt_info<T>(receipt: &FlashLoanReceipt<T>): (u64, u64) {
        (receipt.loan_amount, receipt.repay_amount)
    }

    /// Fee BPS
    public fun fee_bps(): u64 { FEE_BPS }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::sui::SUI;

    #[test]
    fun test_create_pool() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let liquidity = coin::mint_for_testing<SUI>(100000, scenario.ctx());
            create_pool(liquidity, scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let pool = scenario.take_shared<FlashLoanPool<SUI>>();
            assert!(available_liquidity(&pool) == 100000, 0);
            assert!(total_loans(&pool) == 0, 1);
            test_scenario::return_shared(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_flash_loan() {
        let admin = @0x1;
        let borrower = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // Create pool
        {
            let liquidity = coin::mint_for_testing<SUI>(100000, scenario.ctx());
            create_pool(liquidity, scenario.ctx());
        };

        // Execute flash loan
        scenario.next_tx(borrower);
        {
            let mut pool = scenario.take_shared<FlashLoanPool<SUI>>();

            // Borrow 10000
            let (loan, receipt) = borrow(&mut pool, 10000, scenario.ctx());

            let (loan_amount, repay_amount) = receipt_info(&receipt);
            assert!(loan_amount == 10000, 0);
            assert!(repay_amount == 10009, 1); // 0.09% fee

            // Simulate profit (in reality, use the loan for arbitrage)
            let profit = coin::mint_for_testing<SUI>(9, scenario.ctx());
            coin::join(&mut loan, profit);

            // Repay
            repay(&mut pool, receipt, loan, scenario.ctx());

            assert!(total_loans(&pool) == 1, 2);
            assert!(total_fees(&pool) == 9, 3);

            test_scenario::return_shared(pool);
        };

        scenario.end();
    }

    #[test]
    fun test_calculate_fee() {
        assert!(calculate_fee(10000) == 9, 0);
        assert!(calculate_fee(100000) == 90, 1);
        assert!(calculate_fee(1000000) == 900, 2);
    }

    #[test]
    #[expected_failure(abort_code = ERepaymentInsufficient)]
    fun test_insufficient_repayment() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let liquidity = coin::mint_for_testing<SUI>(100000, scenario.ctx());
            create_pool(liquidity, scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let mut pool = scenario.take_shared<FlashLoanPool<SUI>>();

            let (loan, receipt) = borrow(&mut pool, 10000, scenario.ctx());

            // Try to repay less than required
            repay(&mut pool, receipt, loan, scenario.ctx());

            test_scenario::return_shared(pool);
        };

        scenario.end();
    }
}
