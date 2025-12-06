/// @title AMM Pool
/// @notice Constant product AMM (x*y=k) for token swaps
/// @dev Demonstrates DeFi primitives, LP tokens, and math
module amm_pool::amm_pool {
    use sui::event;
    use sui::balance::{Self, Balance, Supply};
    use sui::coin::{Self, Coin};

    // === Errors ===

    const EZeroAmount: u64 = 0;
    const EInsufficientLiquidity: u64 = 1;
    const ESlippageExceeded: u64 = 2;
    const EInvalidRatio: u64 = 3;

    // === Constants ===

    const FEE_BPS: u64 = 30; // 0.3% swap fee
    const BPS_BASE: u64 = 10000;
    const MIN_LIQUIDITY: u64 = 1000;

    // === Structs ===

    /// LP Token type
    public struct LP<phantom X, phantom Y> has drop {}

    /// AMM Pool
    public struct Pool<phantom X, phantom Y> has key {
        id: UID,
        /// Reserve of token X
        reserve_x: Balance<X>,
        /// Reserve of token Y
        reserve_y: Balance<Y>,
        /// LP token supply
        lp_supply: Supply<LP<X, Y>>,
        /// Fee recipient
        fee_recipient: address,
        /// Accumulated fees in X
        fees_x: Balance<X>,
        /// Accumulated fees in Y
        fees_y: Balance<Y>,
    }

    // === Events ===

    public struct PoolCreated has copy, drop {
        pool_id: ID,
    }

    public struct LiquidityAdded has copy, drop {
        pool_id: ID,
        provider: address,
        amount_x: u64,
        amount_y: u64,
        lp_minted: u64,
    }

    public struct LiquidityRemoved has copy, drop {
        pool_id: ID,
        provider: address,
        amount_x: u64,
        amount_y: u64,
        lp_burned: u64,
    }

    public struct Swapped has copy, drop {
        pool_id: ID,
        trader: address,
        amount_in: u64,
        amount_out: u64,
        is_x_to_y: bool,
    }

    // === Create Functions ===

    /// Create a new pool with initial liquidity
    public fun create_pool<X, Y>(
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        fee_recipient: address,
        ctx: &mut TxContext,
    ): Coin<LP<X, Y>> {
        let amount_x = coin::value(&coin_x);
        let amount_y = coin::value(&coin_y);

        assert!(amount_x > 0 && amount_y > 0, EZeroAmount);

        // Calculate initial LP tokens (geometric mean)
        let lp_amount = sqrt(amount_x * amount_y);
        assert!(lp_amount > MIN_LIQUIDITY, EInsufficientLiquidity);

        let mut lp_supply = balance::create_supply(LP<X, Y> {});
        let lp_balance = balance::increase_supply(&mut lp_supply, lp_amount);

        let pool = Pool {
            id: object::new(ctx),
            reserve_x: coin::into_balance(coin_x),
            reserve_y: coin::into_balance(coin_y),
            lp_supply,
            fee_recipient,
            fees_x: balance::zero(),
            fees_y: balance::zero(),
        };

        event::emit(PoolCreated {
            pool_id: object::id(&pool),
        });

        event::emit(LiquidityAdded {
            pool_id: object::id(&pool),
            provider: ctx.sender(),
            amount_x,
            amount_y,
            lp_minted: lp_amount,
        });

        transfer::share_object(pool);

        coin::from_balance(lp_balance, ctx)
    }

    // === Core Functions ===

    /// Add liquidity to pool
    public fun add_liquidity<X, Y>(
        pool: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        coin_y: Coin<Y>,
        ctx: &mut TxContext,
    ): Coin<LP<X, Y>> {
        let amount_x = coin::value(&coin_x);
        let amount_y = coin::value(&coin_y);

        assert!(amount_x > 0 && amount_y > 0, EZeroAmount);

        let reserve_x = balance::value(&pool.reserve_x);
        let reserve_y = balance::value(&pool.reserve_y);
        let lp_total = balance::supply_value(&pool.lp_supply);

        // Calculate optimal amounts based on current ratio
        let optimal_y = (amount_x * reserve_y) / reserve_x;
        let (actual_x, actual_y) = if (optimal_y <= amount_y) {
            (amount_x, optimal_y)
        } else {
            let optimal_x = (amount_y * reserve_x) / reserve_y;
            (optimal_x, amount_y)
        };

        // Calculate LP tokens to mint
        let lp_amount = min(
            (actual_x * lp_total) / reserve_x,
            (actual_y * lp_total) / reserve_y,
        );

        assert!(lp_amount > 0, EInsufficientLiquidity);

        // Add liquidity
        let mut balance_x = coin::into_balance(coin_x);
        let mut balance_y = coin::into_balance(coin_y);

        // Take only what we need
        let add_x = balance::split(&mut balance_x, actual_x);
        let add_y = balance::split(&mut balance_y, actual_y);

        balance::join(&mut pool.reserve_x, add_x);
        balance::join(&mut pool.reserve_y, add_y);

        // Return excess
        if (balance::value(&balance_x) > 0) {
            transfer::public_transfer(coin::from_balance(balance_x, ctx), ctx.sender());
        } else {
            balance::destroy_zero(balance_x);
        };

        if (balance::value(&balance_y) > 0) {
            transfer::public_transfer(coin::from_balance(balance_y, ctx), ctx.sender());
        } else {
            balance::destroy_zero(balance_y);
        };

        // Mint LP tokens
        let lp_balance = balance::increase_supply(&mut pool.lp_supply, lp_amount);

        event::emit(LiquidityAdded {
            pool_id: object::id(pool),
            provider: ctx.sender(),
            amount_x: actual_x,
            amount_y: actual_y,
            lp_minted: lp_amount,
        });

        coin::from_balance(lp_balance, ctx)
    }

    /// Remove liquidity from pool
    public fun remove_liquidity<X, Y>(
        pool: &mut Pool<X, Y>,
        lp_coin: Coin<LP<X, Y>>,
        ctx: &mut TxContext,
    ): (Coin<X>, Coin<Y>) {
        let lp_amount = coin::value(&lp_coin);
        assert!(lp_amount > 0, EZeroAmount);

        let reserve_x = balance::value(&pool.reserve_x);
        let reserve_y = balance::value(&pool.reserve_y);
        let lp_total = balance::supply_value(&pool.lp_supply);

        // Calculate amounts to return
        let amount_x = (lp_amount * reserve_x) / lp_total;
        let amount_y = (lp_amount * reserve_y) / lp_total;

        // Burn LP tokens
        balance::decrease_supply(&mut pool.lp_supply, coin::into_balance(lp_coin));

        // Remove liquidity
        let coin_x = coin::from_balance(
            balance::split(&mut pool.reserve_x, amount_x),
            ctx,
        );
        let coin_y = coin::from_balance(
            balance::split(&mut pool.reserve_y, amount_y),
            ctx,
        );

        event::emit(LiquidityRemoved {
            pool_id: object::id(pool),
            provider: ctx.sender(),
            amount_x,
            amount_y,
            lp_burned: lp_amount,
        });

        (coin_x, coin_y)
    }

    /// Swap X for Y
    public fun swap_x_for_y<X, Y>(
        pool: &mut Pool<X, Y>,
        coin_x: Coin<X>,
        min_out: u64,
        ctx: &mut TxContext,
    ): Coin<Y> {
        let amount_in = coin::value(&coin_x);
        assert!(amount_in > 0, EZeroAmount);

        let reserve_x = balance::value(&pool.reserve_x);
        let reserve_y = balance::value(&pool.reserve_y);

        // Calculate output with fee
        let amount_out = get_amount_out(amount_in, reserve_x, reserve_y);
        assert!(amount_out >= min_out, ESlippageExceeded);
        assert!(amount_out < reserve_y, EInsufficientLiquidity);

        // Add input to reserves
        balance::join(&mut pool.reserve_x, coin::into_balance(coin_x));

        // Remove output from reserves
        let out_balance = balance::split(&mut pool.reserve_y, amount_out);

        event::emit(Swapped {
            pool_id: object::id(pool),
            trader: ctx.sender(),
            amount_in,
            amount_out,
            is_x_to_y: true,
        });

        coin::from_balance(out_balance, ctx)
    }

    /// Swap Y for X
    public fun swap_y_for_x<X, Y>(
        pool: &mut Pool<X, Y>,
        coin_y: Coin<Y>,
        min_out: u64,
        ctx: &mut TxContext,
    ): Coin<X> {
        let amount_in = coin::value(&coin_y);
        assert!(amount_in > 0, EZeroAmount);

        let reserve_x = balance::value(&pool.reserve_x);
        let reserve_y = balance::value(&pool.reserve_y);

        // Calculate output with fee
        let amount_out = get_amount_out(amount_in, reserve_y, reserve_x);
        assert!(amount_out >= min_out, ESlippageExceeded);
        assert!(amount_out < reserve_x, EInsufficientLiquidity);

        // Add input to reserves
        balance::join(&mut pool.reserve_y, coin::into_balance(coin_y));

        // Remove output from reserves
        let out_balance = balance::split(&mut pool.reserve_x, amount_out);

        event::emit(Swapped {
            pool_id: object::id(pool),
            trader: ctx.sender(),
            amount_in,
            amount_out,
            is_x_to_y: false,
        });

        coin::from_balance(out_balance, ctx)
    }

    // === Math Functions ===

    /// Calculate output amount with fee
    public fun get_amount_out(
        amount_in: u64,
        reserve_in: u64,
        reserve_out: u64,
    ): u64 {
        let amount_in_with_fee = (amount_in as u128) * ((BPS_BASE - FEE_BPS) as u128);
        let numerator = amount_in_with_fee * (reserve_out as u128);
        let denominator = (reserve_in as u128) * (BPS_BASE as u128) + amount_in_with_fee;

        ((numerator / denominator) as u64)
    }

    /// Integer square root
    fun sqrt(x: u64): u64 {
        if (x == 0) return 0;

        let mut z = (x + 1) / 2;
        let mut y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        };

        y
    }

    /// Minimum of two values
    fun min(a: u64, b: u64): u64 {
        if (a < b) a else b
    }

    // === View Functions ===

    /// Get pool reserves
    public fun reserves<X, Y>(pool: &Pool<X, Y>): (u64, u64) {
        (balance::value(&pool.reserve_x), balance::value(&pool.reserve_y))
    }

    /// Get LP supply
    public fun lp_supply<X, Y>(pool: &Pool<X, Y>): u64 {
        balance::supply_value(&pool.lp_supply)
    }

    /// Get price (Y per X, scaled by 1e9)
    public fun price<X, Y>(pool: &Pool<X, Y>): u64 {
        let (reserve_x, reserve_y) = reserves(pool);
        if (reserve_x == 0) return 0;
        ((reserve_y as u128) * 1000000000 / (reserve_x as u128)) as u64
    }

    /// Quote swap amount
    public fun quote<X, Y>(pool: &Pool<X, Y>, amount_in: u64, is_x_to_y: bool): u64 {
        let (reserve_x, reserve_y) = reserves(pool);
        if (is_x_to_y) {
            get_amount_out(amount_in, reserve_x, reserve_y)
        } else {
            get_amount_out(amount_in, reserve_y, reserve_x)
        }
    }

    /// Fee BPS
    public fun fee_bps(): u64 { FEE_BPS }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use sui::test_utils;

    #[test_only]
    public struct USDC has drop {}

    #[test]
    fun test_sqrt() {
        assert!(sqrt(0) == 0, 0);
        assert!(sqrt(1) == 1, 1);
        assert!(sqrt(4) == 2, 2);
        assert!(sqrt(9) == 3, 3);
        assert!(sqrt(10) == 3, 4);
        assert!(sqrt(1000000) == 1000, 5);
    }

    #[test]
    fun test_get_amount_out() {
        // 1000 in, 10000/10000 reserves
        // With 0.3% fee: 1000 * 0.997 = 997 effective input
        // Output = 997 * 10000 / (10000 + 997) = ~906
        let out = get_amount_out(1000, 10000, 10000);
        assert!(out > 900 && out < 1000, 0);
    }

    #[test]
    fun test_create_pool() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let coin_x = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            let coin_y = coin::mint_for_testing<SUI>(10000, scenario.ctx());

            let lp = create_pool(coin_x, coin_y, admin, scenario.ctx());

            // LP should be sqrt(10000 * 10000) = 10000
            assert!(coin::value(&lp) == 10000, 0);

            transfer::public_transfer(lp, admin);
        };

        scenario.next_tx(admin);
        {
            let pool = scenario.take_shared<Pool<SUI, SUI>>();
            let (rx, ry) = reserves(&pool);

            assert!(rx == 10000, 1);
            assert!(ry == 10000, 2);

            test_scenario::return_shared(pool);
        };

        scenario.end();
    }
}
