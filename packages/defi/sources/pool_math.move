/// @title Pool Math
/// @notice AMM math functions for constant product pools
/// @dev Part of @sui-starters/defi package
module sui_starters_defi::pool_math {
    // === Errors ===

    /// Zero input
    const EZeroInput: u64 = 0;

    /// Zero liquidity
    const EZeroLiquidity: u64 = 1;

    /// Slippage exceeded
    const ESlippageExceeded: u64 = 2;

    /// Insufficient output
    const EInsufficientOutput: u64 = 3;

    /// Math overflow
    const EOverflow: u64 = 4;

    // === Constants ===

    /// Basis points denominator (10000 = 100%)
    const BPS_DENOMINATOR: u64 = 10000;

    /// Default fee in basis points (30 = 0.3%)
    const DEFAULT_FEE_BPS: u64 = 30;

    /// Minimum liquidity (burned on first deposit)
    const MINIMUM_LIQUIDITY: u64 = 1000;

    // === Constant Product Functions ===

    /// Calculate output amount for constant product AMM (x * y = k)
    /// Formula: dy = y * dx / (x + dx) * (1 - fee)
    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        fee_bps: u64,
    ): u64 {
        assert!(amount_in > 0, EZeroInput);
        assert!(reserve_in > 0 && reserve_out > 0, EZeroLiquidity);

        // Apply fee: amount_in_with_fee = amount_in * (10000 - fee_bps)
        let amount_in_with_fee = (amount_in as u128) * ((BPS_DENOMINATOR - fee_bps) as u128);
        let numerator = amount_in_with_fee * (reserve_out as u128);
        let denominator = (reserve_in as u128) * (BPS_DENOMINATOR as u128) + amount_in_with_fee;

        (numerator / denominator) as u64
    }

    /// Calculate input amount required for desired output
    /// Formula: dx = x * dy / ((y - dy) * (1 - fee))
    public fun get_amount_in(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64,
        fee_bps: u64,
    ): u64 {
        assert!(amount_out > 0, EZeroInput);
        assert!(reserve_in > 0 && reserve_out > 0, EZeroLiquidity);
        assert!(amount_out < reserve_out, EInsufficientOutput);

        let numerator = (reserve_in as u128) * (amount_out as u128) * (BPS_DENOMINATOR as u128);
        let denominator = ((reserve_out - amount_out) as u128) * ((BPS_DENOMINATOR - fee_bps) as u128);

        ((numerator / denominator) + 1) as u64 // Round up
    }

    /// Calculate optimal liquidity provision amounts
    /// Returns (optimal_a, optimal_b)
    public fun get_optimal_amounts(
        amount_a_desired: u64,
        amount_b_desired: u64,
        reserve_a: u64,
        reserve_b: u64,
    ): (u64, u64) {
        if (reserve_a == 0 && reserve_b == 0) {
            return (amount_a_desired, amount_b_desired)
        };

        // Calculate optimal B for given A
        let optimal_b = quote(amount_a_desired, reserve_a, reserve_b);

        if (optimal_b <= amount_b_desired) {
            return (amount_a_desired, optimal_b)
        };

        // Calculate optimal A for given B
        let optimal_a = quote(amount_b_desired, reserve_b, reserve_a);
        assert!(optimal_a <= amount_a_desired, ESlippageExceeded);

        (optimal_a, amount_b_desired)
    }

    /// Simple price quote without fees
    /// Formula: amount_out = amount_in * reserve_out / reserve_in
    public fun quote(amount_in: u64, reserve_in: u64, reserve_out: u64): u64 {
        assert!(amount_in > 0, EZeroInput);
        assert!(reserve_in > 0 && reserve_out > 0, EZeroLiquidity);

        ((amount_in as u128) * (reserve_out as u128) / (reserve_in as u128)) as u64
    }

    // === Liquidity Math ===

    /// Calculate LP tokens for initial deposit
    /// Formula: sqrt(amount_a * amount_b) - MINIMUM_LIQUIDITY
    public fun calculate_initial_liquidity(amount_a: u64, amount_b: u64): u64 {
        let liquidity = sqrt((amount_a as u128) * (amount_b as u128));
        assert!(liquidity > (MINIMUM_LIQUIDITY as u128), EZeroLiquidity);

        (liquidity as u64) - MINIMUM_LIQUIDITY
    }

    /// Calculate LP tokens for subsequent deposits
    /// Formula: min(amount_a * total_supply / reserve_a, amount_b * total_supply / reserve_b)
    public fun calculate_liquidity(
        amount_a: u64,
        amount_b: u64,
        reserve_a: u64,
        reserve_b: u64,
        total_supply: u64,
    ): u64 {
        let liquidity_a = (amount_a as u128) * (total_supply as u128) / (reserve_a as u128);
        let liquidity_b = (amount_b as u128) * (total_supply as u128) / (reserve_b as u128);

        (if (liquidity_a < liquidity_b) { liquidity_a } else { liquidity_b }) as u64
    }

    /// Calculate token amounts for LP withdrawal
    /// Returns (amount_a, amount_b)
    public fun calculate_withdrawal(
        liquidity: u64,
        reserve_a: u64,
        reserve_b: u64,
        total_supply: u64,
    ): (u64, u64) {
        assert!(liquidity > 0, EZeroInput);
        assert!(total_supply > 0, EZeroLiquidity);

        let amount_a = ((liquidity as u128) * (reserve_a as u128) / (total_supply as u128)) as u64;
        let amount_b = ((liquidity as u128) * (reserve_b as u128) / (total_supply as u128)) as u64;

        (amount_a, amount_b)
    }

    // === Price Functions ===

    /// Calculate spot price of token A in terms of token B
    /// Returns price with precision (multiply by 10^precision)
    public fun get_spot_price(reserve_a: u64, reserve_b: u64, precision: u64): u64 {
        assert!(reserve_a > 0, EZeroLiquidity);

        ((reserve_b as u128) * (precision as u128) / (reserve_a as u128)) as u64
    }

    /// Calculate price impact percentage in basis points
    public fun calculate_price_impact(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        fee_bps: u64,
    ): u64 {
        let amount_out = get_amount_out(amount_in, reserve_in, reserve_out, fee_bps);
        let ideal_out = quote(amount_in, reserve_in, reserve_out);

        if (ideal_out == 0) {
            return 0
        };

        let impact = ((ideal_out - amount_out) as u128) * (BPS_DENOMINATOR as u128) / (ideal_out as u128);
        (impact as u64)
    }

    // === Fee Functions ===

    /// Calculate fee amount from input
    public fun calculate_fee(amount: u64, fee_bps: u64): u64 {
        ((amount as u128) * (fee_bps as u128) / (BPS_DENOMINATOR as u128)) as u64
    }

    /// Split amount into fee and remaining
    public fun split_fee(amount: u64, fee_bps: u64): (u64, u64) {
        let fee = calculate_fee(amount, fee_bps);
        (fee, amount - fee)
    }

    /// Get default fee
    public fun default_fee_bps(): u64 {
        DEFAULT_FEE_BPS
    }

    /// Get minimum liquidity
    public fun minimum_liquidity(): u64 {
        MINIMUM_LIQUIDITY
    }

    // === Helper Functions ===

    /// Integer square root (Babylonian method)
    public fun sqrt(x: u128): u128 {
        if (x == 0) {
            return 0
        };

        let mut z = (x + 1) / 2;
        let mut y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        };

        y
    }

    /// Safe multiply with overflow check
    public fun safe_mul(a: u64, b: u64): u128 {
        (a as u128) * (b as u128)
    }

    /// Safe divide with zero check
    public fun safe_div(a: u128, b: u128): u128 {
        assert!(b > 0, EZeroInput);
        a / b
    }

    // === Tests ===

    #[test]
    fun test_get_amount_out() {
        // Pool with 1000:1000 reserves
        let reserve_in = 1000;
        let reserve_out = 1000;
        let fee_bps = 30; // 0.3%

        // Swap 100 in
        let amount_out = get_amount_out(100, reserve_in, reserve_out, fee_bps);

        // Expected: ~90.66 (due to price impact and fee)
        assert!(amount_out > 0, 0);
        assert!(amount_out < 100, 1); // Should be less due to fee and impact
    }

    #[test]
    fun test_get_amount_in() {
        let reserve_in = 1000;
        let reserve_out = 1000;
        let fee_bps = 30;

        // Get 50 out
        let amount_in = get_amount_in(50, reserve_in, reserve_out, fee_bps);

        // Should need more than 50 input
        assert!(amount_in > 50, 0);
    }

    #[test]
    fun test_quote() {
        // 1:1 pool
        assert!(quote(100, 1000, 1000) == 100, 0);

        // 1:2 pool
        assert!(quote(100, 1000, 2000) == 200, 1);

        // 2:1 pool
        assert!(quote(100, 2000, 1000) == 50, 2);
    }

    #[test]
    fun test_initial_liquidity() {
        // 1000 * 1000 = 1,000,000
        // sqrt(1,000,000) = 1000
        // 1000 - 1000 (min) = 0 - would fail

        // With larger amounts
        let liq = calculate_initial_liquidity(10000, 10000);
        assert!(liq == 10000 - MINIMUM_LIQUIDITY, 0);
    }

    #[test]
    fun test_calculate_liquidity() {
        let reserve_a = 10000;
        let reserve_b = 10000;
        let total_supply = 9000; // After min liquidity burned

        // Adding same ratio
        let liq = calculate_liquidity(1000, 1000, reserve_a, reserve_b, total_supply);
        assert!(liq == 900, 0); // 1000 * 9000 / 10000 = 900
    }

    #[test]
    fun test_calculate_withdrawal() {
        let reserve_a = 10000;
        let reserve_b = 20000;
        let total_supply = 10000;

        // Withdraw 10% (1000 LP)
        let (a, b) = calculate_withdrawal(1000, reserve_a, reserve_b, total_supply);
        assert!(a == 1000, 0);
        assert!(b == 2000, 1);
    }

    #[test]
    fun test_optimal_amounts() {
        let reserve_a = 1000;
        let reserve_b = 2000;

        // Want to add 500 A, 1200 B
        let (opt_a, opt_b) = get_optimal_amounts(500, 1200, reserve_a, reserve_b);

        // Optimal should be 500:1000 (maintaining ratio)
        assert!(opt_a == 500, 0);
        assert!(opt_b == 1000, 1);
    }

    #[test]
    fun test_spot_price() {
        // 1:2 pool, precision 1000000
        let price = get_spot_price(1000, 2000, 1000000);
        assert!(price == 2000000, 0); // 2.0 * 10^6
    }

    #[test]
    fun test_price_impact() {
        let reserve_in = 10000;
        let reserve_out = 10000;
        let fee_bps = 30;

        // Small swap - low impact
        let small_impact = calculate_price_impact(100, reserve_in, reserve_out, fee_bps);

        // Large swap - higher impact
        let large_impact = calculate_price_impact(5000, reserve_in, reserve_out, fee_bps);

        assert!(large_impact > small_impact, 0);
    }

    #[test]
    fun test_calculate_fee() {
        // 0.3% of 1000 = 3
        assert!(calculate_fee(1000, 30) == 3, 0);

        // 1% of 10000 = 100
        assert!(calculate_fee(10000, 100) == 100, 1);
    }

    #[test]
    fun test_split_fee() {
        let (fee, remaining) = split_fee(1000, 30);
        assert!(fee == 3, 0);
        assert!(remaining == 997, 1);
    }

    #[test]
    fun test_sqrt() {
        assert!(sqrt(0) == 0, 0);
        assert!(sqrt(1) == 1, 1);
        assert!(sqrt(4) == 2, 2);
        assert!(sqrt(100) == 10, 3);
        assert!(sqrt(1000000) == 1000, 4);
    }
}
