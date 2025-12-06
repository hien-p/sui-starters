/// @title Wrapped Token
/// @notice Wrap tokens with additional metadata or restrictions
/// @dev Part of @sui-starters/token package
module sui_starters_token::wrapped {
    use std::string::String;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;

    // === Errors ===

    /// Insufficient wrapped balance
    const EInsufficientBalance: u64 = 0;

    /// Token is locked
    const ETokenLocked: u64 = 1;

    /// Invalid amount
    const EInvalidAmount: u64 = 2;

    /// Wrapper is paused
    const EWrapperPaused: u64 = 3;

    // === Structs ===

    /// Wrapped token with lock capability
    public struct WrappedToken<phantom T> has key, store {
        id: UID,
        /// Underlying balance
        balance: Balance<T>,
        /// Lock timestamp (0 = unlocked)
        locked_until: u64,
        /// Wrapper name/identifier
        wrapper_name: String,
    }

    /// Token wrapper (factory)
    public struct TokenWrapper<phantom T> has key, store {
        id: UID,
        /// Wrapper name
        name: String,
        /// Total wrapped
        total_wrapped: u64,
        /// Is paused
        paused: bool,
        /// Wrap fee in basis points
        wrap_fee_bps: u64,
        /// Unwrap fee in basis points
        unwrap_fee_bps: u64,
        /// Fee recipient
        fee_recipient: address,
        /// Collected fees
        fees: Balance<T>,
    }

    /// Receipt for wrapped tokens (for tracking)
    public struct WrapReceipt has copy, drop {
        wrapper_id: ID,
        wrapped_id: ID,
        amount: u64,
        timestamp: u64,
    }

    // === Events ===

    /// Emitted when tokens are wrapped
    public struct TokensWrapped has copy, drop {
        wrapper_id: ID,
        wrapped_id: ID,
        amount: u64,
        fee: u64,
    }

    /// Emitted when tokens are unwrapped
    public struct TokensUnwrapped has copy, drop {
        wrapper_id: ID,
        wrapped_id: ID,
        amount: u64,
        fee: u64,
    }

    /// Emitted when wrapped token is locked
    public struct TokenLocked has copy, drop {
        wrapped_id: ID,
        locked_until: u64,
    }

    // === TokenWrapper Functions ===

    /// Create new token wrapper
    public fun new_wrapper<T>(
        name: String,
        wrap_fee_bps: u64,
        unwrap_fee_bps: u64,
        fee_recipient: address,
        ctx: &mut TxContext,
    ): TokenWrapper<T> {
        TokenWrapper<T> {
            id: object::new(ctx),
            name,
            total_wrapped: 0,
            paused: false,
            wrap_fee_bps,
            unwrap_fee_bps,
            fee_recipient,
            fees: balance::zero(),
        }
    }

    /// Create wrapper with no fees
    public fun new_wrapper_no_fee<T>(
        name: String,
        ctx: &mut TxContext,
    ): TokenWrapper<T> {
        new_wrapper(name, 0, 0, @0x0, ctx)
    }

    /// Wrap tokens
    public fun wrap<T>(
        wrapper: &mut TokenWrapper<T>,
        tokens: Coin<T>,
        locked_until: u64,
        ctx: &mut TxContext,
    ): WrappedToken<T> {
        assert!(!wrapper.paused, EWrapperPaused);

        let amount = coin::value(&tokens);
        assert!(amount > 0, EInvalidAmount);

        let mut token_balance = coin::into_balance(tokens);

        // Calculate and collect fee
        let fee_amount = if (wrapper.wrap_fee_bps > 0) {
            (amount * wrapper.wrap_fee_bps / 10000)
        } else {
            0
        };

        if (fee_amount > 0) {
            let fee = balance::split(&mut token_balance, fee_amount);
            balance::join(&mut wrapper.fees, fee);
        };

        let wrapped_amount = balance::value(&token_balance);
        wrapper.total_wrapped = wrapper.total_wrapped + wrapped_amount;

        let wrapped = WrappedToken<T> {
            id: object::new(ctx),
            balance: token_balance,
            locked_until,
            wrapper_name: wrapper.name,
        };

        event::emit(TokensWrapped {
            wrapper_id: object::id(wrapper),
            wrapped_id: object::id(&wrapped),
            amount: wrapped_amount,
            fee: fee_amount,
        });

        wrapped
    }

    /// Wrap without lock
    public fun wrap_unlocked<T>(
        wrapper: &mut TokenWrapper<T>,
        tokens: Coin<T>,
        ctx: &mut TxContext,
    ): WrappedToken<T> {
        wrap(wrapper, tokens, 0, ctx)
    }

    /// Unwrap tokens
    public fun unwrap<T>(
        wrapper: &mut TokenWrapper<T>,
        wrapped: WrappedToken<T>,
        current_time: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(!wrapper.paused, EWrapperPaused);
        assert!(wrapped.locked_until == 0 || current_time >= wrapped.locked_until, ETokenLocked);

        let wrapped_id = object::id(&wrapped);
        let WrappedToken { id, mut balance, locked_until: _, wrapper_name: _ } = wrapped;
        object::delete(id);

        let amount = balance::value(&balance);

        // Calculate and collect fee
        let fee_amount = if (wrapper.unwrap_fee_bps > 0) {
            (amount * wrapper.unwrap_fee_bps / 10000)
        } else {
            0
        };

        if (fee_amount > 0) {
            let fee = balance::split(&mut balance, fee_amount);
            balance::join(&mut wrapper.fees, fee);
        };

        let unwrap_amount = balance::value(&balance);
        wrapper.total_wrapped = wrapper.total_wrapped - amount;

        event::emit(TokensUnwrapped {
            wrapper_id: object::id(wrapper),
            wrapped_id,
            amount: unwrap_amount,
            fee: fee_amount,
        });

        coin::from_balance(balance, ctx)
    }

    /// Pause wrapper
    public fun pause<T>(wrapper: &mut TokenWrapper<T>) {
        wrapper.paused = true;
    }

    /// Unpause wrapper
    public fun unpause<T>(wrapper: &mut TokenWrapper<T>) {
        wrapper.paused = false;
    }

    /// Set fees
    public fun set_fees<T>(
        wrapper: &mut TokenWrapper<T>,
        wrap_fee_bps: u64,
        unwrap_fee_bps: u64,
    ) {
        wrapper.wrap_fee_bps = wrap_fee_bps;
        wrapper.unwrap_fee_bps = unwrap_fee_bps;
    }

    /// Set fee recipient
    public fun set_fee_recipient<T>(wrapper: &mut TokenWrapper<T>, recipient: address) {
        wrapper.fee_recipient = recipient;
    }

    /// Withdraw collected fees
    public fun withdraw_fees<T>(
        wrapper: &mut TokenWrapper<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        let amount = balance::value(&wrapper.fees);
        coin::from_balance(balance::split(&mut wrapper.fees, amount), ctx)
    }

    /// Get wrapper name
    public fun wrapper_name<T>(wrapper: &TokenWrapper<T>): String {
        wrapper.name
    }

    /// Get total wrapped
    public fun total_wrapped<T>(wrapper: &TokenWrapper<T>): u64 {
        wrapper.total_wrapped
    }

    /// Get collected fees
    public fun collected_fees<T>(wrapper: &TokenWrapper<T>): u64 {
        balance::value(&wrapper.fees)
    }

    /// Check if wrapper is paused
    public fun is_paused<T>(wrapper: &TokenWrapper<T>): bool {
        wrapper.paused
    }

    // === WrappedToken Functions ===

    /// Get wrapped token balance
    public fun balance<T>(wrapped: &WrappedToken<T>): u64 {
        balance::value(&wrapped.balance)
    }

    /// Check if locked
    public fun is_locked<T>(wrapped: &WrappedToken<T>, current_time: u64): bool {
        wrapped.locked_until > 0 && current_time < wrapped.locked_until
    }

    /// Get lock time
    public fun locked_until<T>(wrapped: &WrappedToken<T>): u64 {
        wrapped.locked_until
    }

    /// Get wrapper name
    public fun wrapped_name<T>(wrapped: &WrappedToken<T>): String {
        wrapped.wrapper_name
    }

    /// Extend lock (only increase, never decrease)
    public fun extend_lock<T>(wrapped: &mut WrappedToken<T>, new_lock_until: u64) {
        if (new_lock_until > wrapped.locked_until) {
            wrapped.locked_until = new_lock_until;

            event::emit(TokenLocked {
                wrapped_id: object::id(wrapped),
                locked_until: new_lock_until,
            });
        };
    }

    /// Split wrapped token
    public fun split<T>(
        wrapped: &mut WrappedToken<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): WrappedToken<T> {
        assert!(balance::value(&wrapped.balance) >= amount, EInsufficientBalance);

        WrappedToken<T> {
            id: object::new(ctx),
            balance: balance::split(&mut wrapped.balance, amount),
            locked_until: wrapped.locked_until, // Same lock time
            wrapper_name: wrapped.wrapper_name,
        }
    }

    /// Merge wrapped tokens (must have same lock time or both unlocked)
    public fun merge<T>(wrapped: &mut WrappedToken<T>, other: WrappedToken<T>) {
        let WrappedToken { id, balance: other_balance, locked_until: _, wrapper_name: _ } = other;
        object::delete(id);

        balance::join(&mut wrapped.balance, other_balance);
    }

    // === Tests ===

    #[test]
    fun test_wrap_unwrap() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        use std::string;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        // Create wrapper
        {
            let wrapper = new_wrapper_no_fee<SUI>(
                string::utf8(b"Wrapped SUI"),
                scenario.ctx(),
            );
            transfer::public_share_object(wrapper);
        };

        // Wrap tokens
        scenario.next_tx(admin);
        {
            let mut wrapper = scenario.take_shared<TokenWrapper<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());

            let wrapped = wrap_unlocked(&mut wrapper, tokens, scenario.ctx());

            assert!(balance(&wrapped) == 1000, 0);
            assert!(total_wrapped(&wrapper) == 1000, 1);

            transfer::public_transfer(wrapped, admin);
            test_scenario::return_shared(wrapper);
        };

        // Unwrap tokens
        scenario.next_tx(admin);
        {
            let mut wrapper = scenario.take_shared<TokenWrapper<SUI>>();
            let wrapped = scenario.take_from_sender<WrappedToken<SUI>>();

            let tokens = unwrap(&mut wrapper, wrapped, 0, scenario.ctx());

            assert!(coin::value(&tokens) == 1000, 2);
            assert!(total_wrapped(&wrapper) == 0, 3);

            transfer::public_transfer(tokens, admin);
            test_scenario::return_shared(wrapper);
        };

        scenario.end();
    }

    #[test]
    fun test_wrap_with_fee() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        use std::string;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let wrapper = new_wrapper<SUI>(
                string::utf8(b"Fee Wrapper"),
                100, // 1% wrap fee
                200, // 2% unwrap fee
                admin,
                scenario.ctx(),
            );
            transfer::public_share_object(wrapper);
        };

        scenario.next_tx(admin);
        {
            let mut wrapper = scenario.take_shared<TokenWrapper<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());

            let wrapped = wrap_unlocked(&mut wrapper, tokens, scenario.ctx());

            // 1% fee = 10 tokens
            assert!(balance(&wrapped) == 990, 0);
            assert!(collected_fees(&wrapper) == 10, 1);

            transfer::public_transfer(wrapped, admin);
            test_scenario::return_shared(wrapper);
        };

        scenario.end();
    }

    #[test]
    fun test_locked_wrap() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        use std::string;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let wrapper = new_wrapper_no_fee<SUI>(
                string::utf8(b"Locked Wrapper"),
                scenario.ctx(),
            );
            transfer::public_share_object(wrapper);
        };

        scenario.next_tx(admin);
        {
            let mut wrapper = scenario.take_shared<TokenWrapper<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());

            let wrapped = wrap(&mut wrapper, tokens, 5000, scenario.ctx()); // Lock until 5000

            assert!(is_locked(&wrapped, 3000), 0); // Locked at time 3000
            assert!(!is_locked(&wrapped, 6000), 1); // Unlocked at time 6000
            assert!(locked_until(&wrapped) == 5000, 2);

            transfer::public_transfer(wrapped, admin);
            test_scenario::return_shared(wrapper);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ETokenLocked)]
    fun test_unwrap_locked_fails() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        use std::string;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let wrapper = new_wrapper_no_fee<SUI>(
                string::utf8(b"Wrapper"),
                scenario.ctx(),
            );
            transfer::public_share_object(wrapper);
        };

        scenario.next_tx(admin);
        {
            let mut wrapper = scenario.take_shared<TokenWrapper<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let wrapped = wrap(&mut wrapper, tokens, 10000, scenario.ctx());
            transfer::public_transfer(wrapped, admin);
            test_scenario::return_shared(wrapper);
        };

        scenario.next_tx(admin);
        {
            let mut wrapper = scenario.take_shared<TokenWrapper<SUI>>();
            let wrapped = scenario.take_from_sender<WrappedToken<SUI>>();

            // Try to unwrap at time 5000 (before lock ends at 10000)
            let tokens = unwrap(&mut wrapper, wrapped, 5000, scenario.ctx()); // Should fail

            transfer::public_transfer(tokens, admin);
            test_scenario::return_shared(wrapper);
        };

        scenario.end();
    }

    #[test]
    fun test_split_merge() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        use std::string;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let wrapper = new_wrapper_no_fee<SUI>(
                string::utf8(b"Wrapper"),
                scenario.ctx(),
            );
            transfer::public_share_object(wrapper);
        };

        scenario.next_tx(admin);
        {
            let mut wrapper = scenario.take_shared<TokenWrapper<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());

            let mut wrapped = wrap_unlocked(&mut wrapper, tokens, scenario.ctx());

            // Split 400 from 1000
            let split_wrapped = split(&mut wrapped, 400, scenario.ctx());
            assert!(balance(&wrapped) == 600, 0);
            assert!(balance(&split_wrapped) == 400, 1);

            // Merge back
            merge(&mut wrapped, split_wrapped);
            assert!(balance(&wrapped) == 1000, 2);

            transfer::public_transfer(wrapped, admin);
            test_scenario::return_shared(wrapper);
        };

        scenario.end();
    }

    #[test]
    fun test_extend_lock() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        use std::string;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let wrapper = new_wrapper_no_fee<SUI>(
                string::utf8(b"Wrapper"),
                scenario.ctx(),
            );
            transfer::public_share_object(wrapper);
        };

        scenario.next_tx(admin);
        {
            let mut wrapper = scenario.take_shared<TokenWrapper<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());

            let mut wrapped = wrap(&mut wrapper, tokens, 5000, scenario.ctx());
            assert!(locked_until(&wrapped) == 5000, 0);

            // Extend lock
            extend_lock(&mut wrapped, 10000);
            assert!(locked_until(&wrapped) == 10000, 1);

            // Try to decrease lock (should not change)
            extend_lock(&mut wrapped, 3000);
            assert!(locked_until(&wrapped) == 10000, 2); // Still 10000

            transfer::public_transfer(wrapped, admin);
            test_scenario::return_shared(wrapper);
        };

        scenario.end();
    }
}
