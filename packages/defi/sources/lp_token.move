/// @title LP Token
/// @notice Liquidity provider token management
/// @dev Part of @sui-starters/defi package
module sui_starters_defi::lp_token {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Balance, Supply};
    use sui::event;

    // === Errors ===

    /// Insufficient LP balance
    const EInsufficientBalance: u64 = 0;

    /// Invalid amount
    const EInvalidAmount: u64 = 1;

    /// Pool is locked
    const EPoolLocked: u64 = 2;

    /// Zero total supply
    const EZeroSupply: u64 = 3;

    // === Structs ===

    /// LP token supply manager (wraps Coin's Supply)
    public struct LPSupply<phantom LP> has store {
        /// The underlying supply
        supply: Supply<LP>,
        /// Total minted ever
        total_minted: u64,
        /// Total burned ever
        total_burned: u64,
    }

    /// LP position with metadata
    public struct LPPosition<phantom LP> has key, store {
        id: UID,
        /// LP token balance
        balance: Balance<LP>,
        /// Initial deposit value (for tracking IL)
        initial_value_a: u64,
        initial_value_b: u64,
        /// Deposit timestamp
        deposit_time: u64,
    }

    /// LP stats
    public struct LPStats has copy, drop {
        total_supply: u64,
        total_minted: u64,
        total_burned: u64,
    }

    // === Events ===

    /// Emitted when LP tokens are minted
    public struct LPMinted has copy, drop {
        amount: u64,
        recipient: address,
        total_supply: u64,
    }

    /// Emitted when LP tokens are burned
    public struct LPBurned has copy, drop {
        amount: u64,
        burner: address,
        total_supply: u64,
    }

    // === Create Functions ===

    /// Create LP supply from treasury cap
    /// Consumes the treasury cap - LP tokens can only be minted through this module
    public fun new_supply<LP>(cap: TreasuryCap<LP>): LPSupply<LP> {
        LPSupply<LP> {
            supply: coin::treasury_into_supply(cap),
            total_minted: 0,
            total_burned: 0,
        }
    }

    /// Create empty LP position
    public fun new_position<LP>(
        deposit_time: u64,
        initial_value_a: u64,
        initial_value_b: u64,
        ctx: &mut TxContext,
    ): LPPosition<LP> {
        LPPosition<LP> {
            id: object::new(ctx),
            balance: balance::zero(),
            initial_value_a,
            initial_value_b,
            deposit_time,
        }
    }

    // === Mint/Burn Functions ===

    /// Mint LP tokens
    public fun mint<LP>(
        supply: &mut LPSupply<LP>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<LP> {
        assert!(amount > 0, EInvalidAmount);

        supply.total_minted = supply.total_minted + amount;
        let new_supply = balance::supply_value(&supply.supply) + amount;

        event::emit(LPMinted {
            amount,
            recipient: ctx.sender(),
            total_supply: new_supply,
        });

        coin::from_balance(balance::increase_supply(&mut supply.supply, amount), ctx)
    }

    /// Mint LP tokens to balance
    public fun mint_balance<LP>(
        supply: &mut LPSupply<LP>,
        amount: u64,
    ): Balance<LP> {
        assert!(amount > 0, EInvalidAmount);

        supply.total_minted = supply.total_minted + amount;
        balance::increase_supply(&mut supply.supply, amount)
    }

    /// Burn LP tokens
    public fun burn<LP>(
        supply: &mut LPSupply<LP>,
        tokens: Coin<LP>,
        ctx: &TxContext,
    ) {
        let amount = coin::value(&tokens);
        let new_supply = balance::supply_value(&supply.supply) - amount;

        supply.total_burned = supply.total_burned + amount;

        event::emit(LPBurned {
            amount,
            burner: ctx.sender(),
            total_supply: new_supply,
        });

        balance::decrease_supply(&mut supply.supply, coin::into_balance(tokens));
    }

    /// Burn LP tokens from balance
    public fun burn_balance<LP>(
        supply: &mut LPSupply<LP>,
        tokens: Balance<LP>,
    ) {
        let amount = balance::value(&tokens);
        supply.total_burned = supply.total_burned + amount;
        balance::decrease_supply(&mut supply.supply, tokens);
    }

    // === Position Functions ===

    /// Add LP tokens to position
    public fun deposit_to_position<LP>(
        position: &mut LPPosition<LP>,
        tokens: Coin<LP>,
    ) {
        balance::join(&mut position.balance, coin::into_balance(tokens));
    }

    /// Withdraw LP tokens from position
    public fun withdraw_from_position<LP>(
        position: &mut LPPosition<LP>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<LP> {
        assert!(balance::value(&position.balance) >= amount, EInsufficientBalance);
        coin::from_balance(balance::split(&mut position.balance, amount), ctx)
    }

    /// Withdraw all LP tokens and destroy position
    public fun close_position<LP>(
        position: LPPosition<LP>,
        ctx: &mut TxContext,
    ): Coin<LP> {
        let LPPosition {
            id,
            balance,
            initial_value_a: _,
            initial_value_b: _,
            deposit_time: _,
        } = position;
        object::delete(id);

        coin::from_balance(balance, ctx)
    }

    /// Merge two positions
    public fun merge_positions<LP>(
        position: &mut LPPosition<LP>,
        other: LPPosition<LP>,
    ) {
        let LPPosition {
            id,
            balance: other_balance,
            initial_value_a,
            initial_value_b,
            deposit_time: _,
        } = other;
        object::delete(id);

        // Update initial values (weighted average based on amounts would be more accurate)
        position.initial_value_a = position.initial_value_a + initial_value_a;
        position.initial_value_b = position.initial_value_b + initial_value_b;

        balance::join(&mut position.balance, other_balance);
    }

    // === Calculation Functions ===

    /// Calculate share of pool for given LP amount
    public fun calculate_share<LP>(
        supply: &LPSupply<LP>,
        lp_amount: u64,
    ): (u128, u128) {
        let total_supply = balance::supply_value(&supply.supply);
        if (total_supply == 0) {
            return (0, 0)
        };

        // Return (numerator, denominator) for precision
        ((lp_amount as u128), (total_supply as u128))
    }

    /// Calculate withdrawal amounts given LP tokens and pool reserves
    public fun calculate_withdrawal<LP>(
        supply: &LPSupply<LP>,
        lp_amount: u64,
        reserve_a: u64,
        reserve_b: u64,
    ): (u64, u64) {
        let total_supply = balance::supply_value(&supply.supply);
        assert!(total_supply > 0, EZeroSupply);

        let amount_a = ((lp_amount as u128) * (reserve_a as u128) / (total_supply as u128)) as u64;
        let amount_b = ((lp_amount as u128) * (reserve_b as u128) / (total_supply as u128)) as u64;

        (amount_a, amount_b)
    }

    /// Calculate impermanent loss/gain
    /// Returns (change_bps, is_gain) - change in basis points and whether it's a gain
    public fun calculate_il<LP>(
        position: &LPPosition<LP>,
        current_value_a: u64,
        current_value_b: u64,
    ): (u64, bool) {
        let initial_total = position.initial_value_a + position.initial_value_b;
        if (initial_total == 0) {
            return (0, true)
        };

        let current_total = current_value_a + current_value_b;

        // IL = |current - initial| / initial * 10000 (in bps)
        if (current_total >= initial_total) {
            let change = (((current_total - initial_total) as u128) * 10000 / (initial_total as u128)) as u64;
            (change, true) // Gain
        } else {
            let change = (((initial_total - current_total) as u128) * 10000 / (initial_total as u128)) as u64;
            (change, false) // Loss
        }
    }

    // === View Functions ===

    /// Get total supply
    public fun total_supply<LP>(supply: &LPSupply<LP>): u64 {
        balance::supply_value(&supply.supply)
    }

    /// Get total minted
    public fun total_minted<LP>(supply: &LPSupply<LP>): u64 {
        supply.total_minted
    }

    /// Get total burned
    public fun total_burned<LP>(supply: &LPSupply<LP>): u64 {
        supply.total_burned
    }

    /// Get LP stats
    public fun get_stats<LP>(supply: &LPSupply<LP>): LPStats {
        LPStats {
            total_supply: balance::supply_value(&supply.supply),
            total_minted: supply.total_minted,
            total_burned: supply.total_burned,
        }
    }

    /// Get position balance
    public fun position_balance<LP>(position: &LPPosition<LP>): u64 {
        balance::value(&position.balance)
    }

    /// Get position initial values
    public fun position_initial_values<LP>(position: &LPPosition<LP>): (u64, u64) {
        (position.initial_value_a, position.initial_value_b)
    }

    /// Get position deposit time
    public fun position_deposit_time<LP>(position: &LPPosition<LP>): u64 {
        position.deposit_time
    }

    /// Borrow supply reference (for advanced usage)
    public fun borrow_supply<LP>(lp_supply: &LPSupply<LP>): &Supply<LP> {
        &lp_supply.supply
    }

    /// Borrow supply mutably (for advanced usage)
    public fun borrow_supply_mut<LP>(lp_supply: &mut LPSupply<LP>): &mut Supply<LP> {
        &mut lp_supply.supply
    }

    // Note: LPSupply tests require a TreasuryCap which can only be
    // created with a one-time witness in an init function. Integration tests
    // are needed to fully test this module with a real LP token deployment.

    #[test]
    fun test_position_create() {
        use sui::test_scenario;
        use sui::sui::SUI;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let position = new_position<SUI>(
                1000,  // deposit_time
                500,   // initial_value_a
                500,   // initial_value_b
                scenario.ctx(),
            );

            assert!(position_balance(&position) == 0, 0);
            let (a, b) = position_initial_values(&position);
            assert!(a == 500 && b == 500, 1);
            assert!(position_deposit_time(&position) == 1000, 2);

            transfer::public_transfer(position, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_il_calculation() {
        use sui::test_scenario;
        use sui::sui::SUI;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let position = new_position<SUI>(
                1000,
                1000,  // initial_value_a
                1000,  // initial_value_b (total = 2000)
                scenario.ctx(),
            );

            // Current value same (no IL)
            let (change, is_gain) = calculate_il(&position, 1000, 1000);
            assert!(change == 0, 0);
            assert!(is_gain, 1);

            // Current value higher (gain)
            let (gain_change, gain_is_gain) = calculate_il(&position, 1200, 1200);
            assert!(gain_change == 2000, 2); // 20% gain = 2000 bps
            assert!(gain_is_gain, 3);

            // Current value lower (loss)
            let (loss_change, loss_is_gain) = calculate_il(&position, 800, 800);
            assert!(loss_change == 2000, 4); // 20% loss = 2000 bps
            assert!(!loss_is_gain, 5); // is_gain should be false

            transfer::public_transfer(position, admin);
        };

        scenario.end();
    }
}
