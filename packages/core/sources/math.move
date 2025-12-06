/// @title Math utilities for Sui Move
/// @notice Safe math operations, percentage calculations, fixed-point math, and square root
/// @dev Part of @sui-starters/core package
module sui_starters_core::math {
    // === Constants ===

    /// Basis points denominator (100% = 10000 bps)
    const BPS_DENOMINATOR: u64 = 10000;

    /// Maximum u64 value
    const MAX_U64: u64 = 18446744073709551615;

    /// Maximum u128 value
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    // === Errors ===

    /// Overflow error
    const EOverflow: u64 = 0;

    /// Division by zero error
    const EDivisionByZero: u64 = 1;

    /// Underflow error
    const EUnderflow: u64 = 2;

    /// Invalid basis points (> 10000)
    const EInvalidBps: u64 = 3;

    // === Safe Math Operations ===

    /// Safe addition with overflow check
    public fun safe_add(a: u64, b: u64): u64 {
        let result = a + b;
        assert!(result >= a, EOverflow);
        result
    }

    /// Safe subtraction with underflow check
    public fun safe_sub(a: u64, b: u64): u64 {
        assert!(a >= b, EUnderflow);
        a - b
    }

    /// Safe multiplication with overflow check
    public fun safe_mul(a: u64, b: u64): u64 {
        if (a == 0 || b == 0) {
            return 0
        };
        let result = a * b;
        assert!(result / a == b, EOverflow);
        result
    }

    /// Safe division with zero check
    public fun safe_div(a: u64, b: u64): u64 {
        assert!(b != 0, EDivisionByZero);
        a / b
    }

    /// Safe modulo with zero check
    public fun safe_mod(a: u64, b: u64): u64 {
        assert!(b != 0, EDivisionByZero);
        a % b
    }

    // === u128 Safe Math ===

    /// Safe addition for u128
    public fun safe_add_u128(a: u128, b: u128): u128 {
        let result = a + b;
        assert!(result >= a, EOverflow);
        result
    }

    /// Safe subtraction for u128
    public fun safe_sub_u128(a: u128, b: u128): u128 {
        assert!(a >= b, EUnderflow);
        a - b
    }

    /// Safe multiplication for u128
    public fun safe_mul_u128(a: u128, b: u128): u128 {
        if (a == 0 || b == 0) {
            return 0
        };
        let result = a * b;
        assert!(result / a == b, EOverflow);
        result
    }

    /// Safe division for u128
    public fun safe_div_u128(a: u128, b: u128): u128 {
        assert!(b != 0, EDivisionByZero);
        a / b
    }

    // === Percentage Calculations (Basis Points) ===

    /// Calculate percentage of amount using basis points
    /// @param amount The base amount
    /// @param bps Basis points (100 bps = 1%, 10000 bps = 100%)
    /// @return The calculated percentage amount
    public fun calculate_percentage(amount: u64, bps: u64): u64 {
        assert!(bps <= BPS_DENOMINATOR, EInvalidBps);
        // Use u128 to prevent overflow
        let result = ((amount as u128) * (bps as u128)) / (BPS_DENOMINATOR as u128);
        (result as u64)
    }

    /// Calculate fee and remaining amount
    /// @param amount The total amount
    /// @param fee_bps Fee in basis points
    /// @return (fee_amount, remaining_amount)
    public fun calculate_fee(amount: u64, fee_bps: u64): (u64, u64) {
        let fee = calculate_percentage(amount, fee_bps);
        let remaining = safe_sub(amount, fee);
        (fee, remaining)
    }

    /// Calculate percentage without upper bound check (for values > 100%)
    public fun calculate_percentage_uncapped(amount: u64, bps: u64): u64 {
        let result = ((amount as u128) * (bps as u128)) / (BPS_DENOMINATOR as u128);
        (result as u64)
    }

    // === Fixed Point Math ===

    /// Convert value to fixed point representation
    /// @param value The value to convert
    /// @param decimals Number of decimal places (e.g., 9 for SUI)
    /// @return Fixed point value as u128
    public fun to_fixed(value: u64, decimals: u8): u128 {
        let multiplier = pow_10(decimals);
        (value as u128) * multiplier
    }

    /// Convert fixed point back to regular value (truncates decimals)
    /// @param value The fixed point value
    /// @param decimals Number of decimal places
    /// @return Regular u64 value
    public fun from_fixed(value: u128, decimals: u8): u64 {
        let divisor = pow_10(decimals);
        ((value / divisor) as u64)
    }

    /// Multiply two fixed point numbers
    /// @param a First fixed point number
    /// @param b Second fixed point number
    /// @param decimals Decimal places used
    /// @return Result in fixed point
    public fun mul_fixed(a: u128, b: u128, decimals: u8): u128 {
        let divisor = pow_10(decimals);
        (a * b) / divisor
    }

    /// Divide two fixed point numbers
    /// @param a Numerator in fixed point
    /// @param b Denominator in fixed point
    /// @param decimals Decimal places used
    /// @return Result in fixed point
    public fun div_fixed(a: u128, b: u128, decimals: u8): u128 {
        assert!(b != 0, EDivisionByZero);
        let multiplier = pow_10(decimals);
        (a * multiplier) / b
    }

    // === Square Root ===

    /// Calculate square root using Babylonian method
    /// @param x The value to find square root of
    /// @return Floor of square root
    public fun sqrt(x: u64): u64 {
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

    /// Calculate square root for u128
    public fun sqrt_u128(x: u128): u128 {
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

    // === Helper Functions ===

    /// Calculate 10^decimals
    public fun pow_10(decimals: u8): u128 {
        let mut result: u128 = 1;
        let mut i: u8 = 0;
        while (i < decimals) {
            result = result * 10;
            i = i + 1;
        };
        result
    }

    /// Calculate a^b for u64
    public fun pow(base: u64, exp: u64): u64 {
        if (exp == 0) {
            return 1
        };

        let mut result: u64 = 1;
        let mut b = base;
        let mut e = exp;

        while (e > 0) {
            if (e % 2 == 1) {
                result = safe_mul(result, b);
            };
            e = e / 2;
            if (e > 0) {
                b = safe_mul(b, b);
            };
        };

        result
    }

    /// Get minimum of two values
    public fun min(a: u64, b: u64): u64 {
        if (a < b) { a } else { b }
    }

    /// Get maximum of two values
    public fun max(a: u64, b: u64): u64 {
        if (a > b) { a } else { b }
    }

    /// Clamp value between min and max
    public fun clamp(value: u64, min_val: u64, max_val: u64): u64 {
        if (value < min_val) {
            min_val
        } else if (value > max_val) {
            max_val
        } else {
            value
        }
    }

    /// Check if value is within range [min, max]
    public fun in_range(value: u64, min_val: u64, max_val: u64): bool {
        value >= min_val && value <= max_val
    }

    // === Constants Getters ===

    public fun bps_denominator(): u64 { BPS_DENOMINATOR }
    public fun max_u64(): u64 { MAX_U64 }
    public fun max_u128(): u128 { MAX_U128 }

    // === Tests ===

    #[test]
    fun test_safe_add() {
        assert!(safe_add(1, 2) == 3, 0);
        assert!(safe_add(0, 0) == 0, 1);
        assert!(safe_add(100, 200) == 300, 2);
    }

    #[test]
    #[expected_failure(arithmetic_error, location = sui_starters_core::math)]
    fun test_safe_add_overflow() {
        safe_add(MAX_U64, 1);
    }

    #[test]
    fun test_safe_sub() {
        assert!(safe_sub(5, 3) == 2, 0);
        assert!(safe_sub(100, 100) == 0, 1);
    }

    #[test]
    #[expected_failure(abort_code = EUnderflow)]
    fun test_safe_sub_underflow() {
        safe_sub(3, 5);
    }

    #[test]
    fun test_safe_mul() {
        assert!(safe_mul(3, 4) == 12, 0);
        assert!(safe_mul(0, 100) == 0, 1);
        assert!(safe_mul(100, 0) == 0, 2);
    }

    #[test]
    fun test_safe_div() {
        assert!(safe_div(10, 2) == 5, 0);
        assert!(safe_div(7, 3) == 2, 1);
    }

    #[test]
    #[expected_failure(abort_code = EDivisionByZero)]
    fun test_safe_div_by_zero() {
        safe_div(10, 0);
    }

    #[test]
    fun test_calculate_percentage() {
        // 10% of 1000 = 100
        assert!(calculate_percentage(1000, 1000) == 100, 0);
        // 50% of 1000 = 500
        assert!(calculate_percentage(1000, 5000) == 500, 1);
        // 100% of 1000 = 1000
        assert!(calculate_percentage(1000, 10000) == 1000, 2);
        // 1% of 1000 = 10
        assert!(calculate_percentage(1000, 100) == 10, 3);
    }

    #[test]
    fun test_calculate_fee() {
        // 5% fee on 1000
        let (fee, remaining) = calculate_fee(1000, 500);
        assert!(fee == 50, 0);
        assert!(remaining == 950, 1);
    }

    #[test]
    fun test_sqrt() {
        assert!(sqrt(0) == 0, 0);
        assert!(sqrt(1) == 1, 1);
        assert!(sqrt(4) == 2, 2);
        assert!(sqrt(9) == 3, 3);
        assert!(sqrt(16) == 4, 4);
        assert!(sqrt(10) == 3, 5); // floor(sqrt(10)) = 3
    }

    #[test]
    fun test_pow() {
        assert!(pow(2, 0) == 1, 0);
        assert!(pow(2, 1) == 2, 1);
        assert!(pow(2, 10) == 1024, 2);
        assert!(pow(3, 4) == 81, 3);
    }

    #[test]
    fun test_min_max() {
        assert!(min(5, 10) == 5, 0);
        assert!(max(5, 10) == 10, 1);
        assert!(min(10, 5) == 5, 2);
        assert!(max(10, 5) == 10, 3);
    }

    #[test]
    fun test_clamp() {
        assert!(clamp(5, 0, 10) == 5, 0);
        assert!(clamp(15, 0, 10) == 10, 1);
        assert!(clamp(0, 5, 10) == 5, 2);
    }

    #[test]
    fun test_fixed_point() {
        // Convert 100 to fixed with 9 decimals
        let fixed = to_fixed(100, 9);
        assert!(fixed == 100000000000, 0);

        // Convert back
        let value = from_fixed(fixed, 9);
        assert!(value == 100, 1);
    }
}
