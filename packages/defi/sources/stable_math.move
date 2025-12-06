/// @title Stable Math
/// @notice StableSwap curve mathematics (Curve-style)
/// @dev Part of @sui-starters/defi package
module sui_starters_defi::stable_math {
    // === Errors ===

    /// Convergence failed
    const EConvergenceFailed: u64 = 0;

    /// Zero amount
    const EZeroAmount: u64 = 1;

    /// Invalid amplification
    const EInvalidAmplification: u64 = 2;

    // === Constants ===

    /// Precision for calculations
    const PRECISION: u128 = 1_000_000_000_000_000_000; // 10^18

    /// Maximum iterations for Newton's method
    const MAX_ITERATIONS: u64 = 255;

    /// Convergence threshold
    const CONVERGENCE_THRESHOLD: u128 = 1;

    /// Number of coins (for 2-pool)
    const N_COINS: u128 = 2;

    // === StableSwap Functions ===

    /// Calculate D (invariant) for a 2-pool
    /// D satisfies: A * n^n * sum(x_i) + D = A * D * n^n + D^(n+1) / (n^n * prod(x_i))
    public fun get_d(
        x0: u64,
        x1: u64,
        amp: u64,
    ): u64 {
        let x0_128 = (x0 as u128);
        let x1_128 = (x1 as u128);
        let sum = x0_128 + x1_128;

        if (sum == 0) {
            return 0
        };

        let ann = (amp as u128) * N_COINS; // A * n

        let mut d = sum;
        let mut d_prev: u128;

        let mut i = 0;
        while (i < MAX_ITERATIONS) {
            // D_P = D^(n+1) / (n^n * prod(x_i))
            let mut d_p = d;
            d_p = d_p * d / (x0_128 * N_COINS);
            d_p = d_p * d / (x1_128 * N_COINS);

            d_prev = d;

            // D = (A*n*sum + D_P*n) * D / ((A*n - 1) * D + (n+1) * D_P)
            let numerator = (ann * sum + d_p * N_COINS) * d;
            let denominator = (ann - 1) * d + (N_COINS + 1) * d_p;

            d = numerator / denominator;

            // Check convergence
            if (d > d_prev) {
                if (d - d_prev <= CONVERGENCE_THRESHOLD) {
                    return (d as u64)
                };
            } else {
                if (d_prev - d <= CONVERGENCE_THRESHOLD) {
                    return (d as u64)
                };
            };

            i = i + 1;
        };

        // Should not reach here
        (d as u64)
    }

    /// Calculate output amount for a swap
    /// Given x (input), calculate y (output) such that the invariant D is preserved
    public fun get_y(
        x_in: u64,      // New balance of input token after adding
        d: u64,         // Invariant
        amp: u64,       // Amplification coefficient
    ): u64 {
        assert!(d > 0, EZeroAmount);

        let x_128 = (x_in as u128);
        let d_128 = (d as u128);
        let ann = (amp as u128) * N_COINS;

        // c = D^(n+1) / (n^n * A * n * x)
        let c = d_128 * d_128 / (x_128 * N_COINS);
        let c = c * d_128 / (ann * N_COINS);

        // b = x + D / (A * n)
        let b = x_128 + d_128 / ann;

        let mut y = d_128;
        let mut y_prev: u128;

        let mut i = 0;
        while (i < MAX_ITERATIONS) {
            y_prev = y;

            // y = (y^2 + c) / (2*y + b - D)
            y = (y * y + c) / (2 * y + b - d_128);

            // Check convergence
            if (y > y_prev) {
                if (y - y_prev <= CONVERGENCE_THRESHOLD) {
                    return (y as u64)
                };
            } else {
                if (y_prev - y <= CONVERGENCE_THRESHOLD) {
                    return (y as u64)
                };
            };

            i = i + 1;
        };

        (y as u64)
    }

    /// Calculate swap output amount
    public fun calc_swap_output(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
        amp: u64,
        fee_bps: u64,
    ): u64 {
        assert!(amount_in > 0, EZeroAmount);
        assert!(amp > 0, EInvalidAmplification);

        // Calculate current D
        let d = get_d(reserve_in, reserve_out, amp);

        // New input reserve
        let new_reserve_in = reserve_in + amount_in;

        // Calculate new output reserve
        let new_reserve_out = get_y(new_reserve_in, d, amp);

        // Output amount (before fee)
        let output_raw = reserve_out - new_reserve_out;

        // Apply fee
        let fee = (output_raw * (fee_bps as u64)) / 10000;
        output_raw - fee
    }

    /// Calculate amount needed for desired output
    public fun calc_swap_input(
        amount_out: u64,
        reserve_in: u64,
        reserve_out: u64,
        amp: u64,
        fee_bps: u64,
    ): u64 {
        assert!(amount_out > 0, EZeroAmount);
        assert!(amount_out < reserve_out, EZeroAmount);
        assert!(amp > 0, EInvalidAmplification);

        // Account for fee (need more input to cover fee)
        let amount_out_with_fee = (amount_out * 10000) / (10000 - (fee_bps as u64));

        // Calculate current D
        let d = get_d(reserve_in, reserve_out, amp);

        // New output reserve
        let new_reserve_out = reserve_out - amount_out_with_fee;

        // Calculate new input reserve
        let new_reserve_in = get_y(new_reserve_out, d, amp);

        // Input amount needed
        new_reserve_in - reserve_in
    }

    /// Calculate LP tokens to mint for deposit
    public fun calc_deposit(
        amount0: u64,
        amount1: u64,
        reserve0: u64,
        reserve1: u64,
        total_supply: u64,
        amp: u64,
    ): u64 {
        if (total_supply == 0) {
            // Initial deposit
            let d = get_d(amount0, amount1, amp);
            return d
        };

        // Current D
        let d0 = get_d(reserve0, reserve1, amp);

        // New D after deposit
        let d1 = get_d(reserve0 + amount0, reserve1 + amount1, amp);

        // LP tokens proportional to D increase
        let d_increase = d1 - d0;
        ((d_increase as u128) * (total_supply as u128) / (d0 as u128)) as u64
    }

    /// Calculate amounts to withdraw for LP tokens
    public fun calc_withdraw(
        lp_amount: u64,
        reserve0: u64,
        reserve1: u64,
        total_supply: u64,
    ): (u64, u64) {
        let share = (lp_amount as u128) * PRECISION / (total_supply as u128);
        let amount0 = ((reserve0 as u128) * share / PRECISION) as u64;
        let amount1 = ((reserve1 as u128) * share / PRECISION) as u64;
        (amount0, amount1)
    }

    /// Calculate virtual price (for LP valuation)
    public fun get_virtual_price(
        reserve0: u64,
        reserve1: u64,
        total_supply: u64,
        amp: u64,
    ): u64 {
        if (total_supply == 0) {
            return 0
        };

        let d = get_d(reserve0, reserve1, amp);
        // Virtual price = D / total_supply (scaled by PRECISION)
        (((d as u128) * PRECISION / (total_supply as u128)) as u64)
    }

    // === Tests ===

    #[test]
    fun test_get_d_equal_reserves() {
        // Equal reserves should give D = 2 * reserve (for 2-pool)
        let d = get_d(1000000, 1000000, 100);
        // D should be approximately 2000000
        assert!(d >= 1999000 && d <= 2001000, 0);
    }

    #[test]
    fun test_get_d_different_reserves() {
        let d = get_d(1000000, 2000000, 100);
        // D should be between sum and geometric mean
        assert!(d > 2000000 && d < 3000000, 0);
    }

    #[test]
    fun test_calc_swap_output() {
        let output = calc_swap_output(
            10000,      // amount_in
            1000000,    // reserve_in
            1000000,    // reserve_out
            100,        // amp
            30,         // 0.3% fee
        );
        // Output should be close to input for stableswap with equal reserves
        assert!(output > 9900 && output < 10000, 0);
    }

    #[test]
    fun test_calc_deposit() {
        // Initial deposit
        let lp = calc_deposit(
            1000000,    // amount0
            1000000,    // amount1
            0,          // reserve0
            0,          // reserve1
            0,          // total_supply
            100,        // amp
        );
        // Should get D as initial LP
        assert!(lp > 1900000 && lp < 2100000, 0);

        // Subsequent deposit
        let lp2 = calc_deposit(
            100000,     // amount0
            100000,     // amount1
            1000000,    // reserve0
            1000000,    // reserve1
            2000000,    // total_supply
            100,        // amp
        );
        // Should get proportional LP
        assert!(lp2 > 180000 && lp2 < 220000, 1);
    }

    #[test]
    fun test_calc_withdraw() {
        let (amount0, amount1) = calc_withdraw(
            200000,     // lp_amount (10% of total)
            1000000,    // reserve0
            1000000,    // reserve1
            2000000,    // total_supply
        );
        // Should get 10% of each reserve
        assert!(amount0 == 100000, 0);
        assert!(amount1 == 100000, 1);
    }

    #[test]
    fun test_virtual_price() {
        let vp = get_virtual_price(
            1000000,
            1000000,
            2000000,
            100,
        );
        // Virtual price should be close to 1 (scaled)
        assert!(vp > 900000000000000000 && vp < 1100000000000000000, 0);
    }
}
