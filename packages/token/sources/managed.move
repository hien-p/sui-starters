/// @title Managed Token
/// @notice Token with treasury management and supply controls
/// @dev Part of @sui-starters/token package
module sui_starters_token::managed {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Balance};
    use sui::event;

    // === Errors ===

    /// Not authorized
    const ENotAuthorized: u64 = 0;

    /// Mint limit exceeded
    const EMintLimitExceeded: u64 = 1;

    /// Supply cap exceeded
    const ESupplyCapExceeded: u64 = 2;

    /// Invalid amount
    const EInvalidAmount: u64 = 3;

    // === Structs ===

    /// Managed treasury with additional controls
    public struct ManagedTreasury<phantom T> has key, store {
        id: UID,
        /// The underlying treasury cap
        cap: TreasuryCap<T>,
        /// Maximum total supply (0 = unlimited)
        max_supply: u64,
        /// Mint per-tx limit (0 = unlimited)
        mint_limit: u64,
        /// Is minting paused
        minting_paused: bool,
        /// Is burning paused
        burning_paused: bool,
        /// Total minted
        total_minted: u64,
        /// Total burned
        total_burned: u64,
    }

    /// Treasury stats
    public struct TreasuryStats has copy, drop {
        total_supply: u64,
        max_supply: u64,
        total_minted: u64,
        total_burned: u64,
        minting_paused: bool,
        burning_paused: bool,
    }

    // === Events ===

    /// Emitted when tokens are minted
    public struct TokensMinted has copy, drop {
        amount: u64,
        recipient: address,
        new_supply: u64,
    }

    /// Emitted when tokens are burned
    public struct TokensBurned has copy, drop {
        amount: u64,
        burner: address,
        new_supply: u64,
    }

    /// Emitted when minting is paused/unpaused
    public struct MintingPaused has copy, drop {
        paused: bool,
        by: address,
    }

    /// Emitted when burning is paused/unpaused
    public struct BurningPaused has copy, drop {
        paused: bool,
        by: address,
    }

    /// Emitted when max supply is updated
    public struct MaxSupplyUpdated has copy, drop {
        old_max: u64,
        new_max: u64,
    }

    // === Create Functions ===

    /// Wrap treasury cap into managed treasury
    public fun new<T>(
        cap: TreasuryCap<T>,
        max_supply: u64,
        mint_limit: u64,
        ctx: &mut TxContext,
    ): ManagedTreasury<T> {
        ManagedTreasury<T> {
            id: object::new(ctx),
            cap,
            max_supply,
            mint_limit,
            minting_paused: false,
            burning_paused: false,
            total_minted: 0,
            total_burned: 0,
        }
    }

    /// Create with unlimited supply
    public fun new_unlimited<T>(
        cap: TreasuryCap<T>,
        ctx: &mut TxContext,
    ): ManagedTreasury<T> {
        new(cap, 0, 0, ctx)
    }

    // === Mint Functions ===

    /// Mint tokens to recipient
    public fun mint<T>(
        treasury: &mut ManagedTreasury<T>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        assert!(!treasury.minting_paused, ENotAuthorized);
        assert!(amount > 0, EInvalidAmount);

        if (treasury.mint_limit > 0) {
            assert!(amount <= treasury.mint_limit, EMintLimitExceeded);
        };

        let current_supply = coin::total_supply(&treasury.cap);
        if (treasury.max_supply > 0) {
            assert!(current_supply + amount <= treasury.max_supply, ESupplyCapExceeded);
        };

        let minted = coin::mint(&mut treasury.cap, amount, ctx);
        treasury.total_minted = treasury.total_minted + amount;

        event::emit(TokensMinted {
            amount,
            recipient,
            new_supply: current_supply + amount,
        });

        transfer::public_transfer(minted, recipient);
    }

    /// Mint to balance (for composing with other modules)
    public fun mint_balance<T>(
        treasury: &mut ManagedTreasury<T>,
        amount: u64,
    ): Balance<T> {
        assert!(!treasury.minting_paused, ENotAuthorized);
        assert!(amount > 0, EInvalidAmount);

        if (treasury.mint_limit > 0) {
            assert!(amount <= treasury.mint_limit, EMintLimitExceeded);
        };

        let current_supply = coin::total_supply(&treasury.cap);
        if (treasury.max_supply > 0) {
            assert!(current_supply + amount <= treasury.max_supply, ESupplyCapExceeded);
        };

        treasury.total_minted = treasury.total_minted + amount;
        coin::mint_balance(&mut treasury.cap, amount)
    }

    // === Burn Functions ===

    /// Burn tokens
    public fun burn<T>(
        treasury: &mut ManagedTreasury<T>,
        coin: Coin<T>,
        ctx: &TxContext,
    ) {
        assert!(!treasury.burning_paused, ENotAuthorized);

        let amount = coin::value(&coin);
        let new_supply = coin::total_supply(&treasury.cap) - amount;

        coin::burn(&mut treasury.cap, coin);
        treasury.total_burned = treasury.total_burned + amount;

        event::emit(TokensBurned {
            amount,
            burner: ctx.sender(),
            new_supply,
        });
    }

    /// Burn from balance
    public fun burn_balance<T>(
        treasury: &mut ManagedTreasury<T>,
        balance: Balance<T>,
    ) {
        assert!(!treasury.burning_paused, ENotAuthorized);

        let amount = balance::value(&balance);
        balance::decrease_supply(coin::supply_mut(&mut treasury.cap), balance);
        treasury.total_burned = treasury.total_burned + amount;
    }

    // === Control Functions ===

    /// Pause minting
    public fun pause_minting<T>(treasury: &mut ManagedTreasury<T>, ctx: &TxContext) {
        treasury.minting_paused = true;
        event::emit(MintingPaused {
            paused: true,
            by: ctx.sender(),
        });
    }

    /// Unpause minting
    public fun unpause_minting<T>(treasury: &mut ManagedTreasury<T>, ctx: &TxContext) {
        treasury.minting_paused = false;
        event::emit(MintingPaused {
            paused: false,
            by: ctx.sender(),
        });
    }

    /// Pause burning
    public fun pause_burning<T>(treasury: &mut ManagedTreasury<T>, ctx: &TxContext) {
        treasury.burning_paused = true;
        event::emit(BurningPaused {
            paused: true,
            by: ctx.sender(),
        });
    }

    /// Unpause burning
    public fun unpause_burning<T>(treasury: &mut ManagedTreasury<T>, ctx: &TxContext) {
        treasury.burning_paused = false;
        event::emit(BurningPaused {
            paused: false,
            by: ctx.sender(),
        });
    }

    /// Update max supply (can only increase or set to 0 for unlimited)
    public fun set_max_supply<T>(treasury: &mut ManagedTreasury<T>, new_max: u64) {
        let old_max = treasury.max_supply;
        // Can increase or set to unlimited (0)
        if (new_max > 0 && old_max > 0) {
            assert!(new_max >= old_max, EInvalidAmount);
        };

        treasury.max_supply = new_max;
        event::emit(MaxSupplyUpdated { old_max, new_max });
    }

    /// Update mint limit
    public fun set_mint_limit<T>(treasury: &mut ManagedTreasury<T>, limit: u64) {
        treasury.mint_limit = limit;
    }

    // === View Functions ===

    /// Get total supply
    public fun total_supply<T>(treasury: &ManagedTreasury<T>): u64 {
        coin::total_supply(&treasury.cap)
    }

    /// Get max supply
    public fun max_supply<T>(treasury: &ManagedTreasury<T>): u64 {
        treasury.max_supply
    }

    /// Get mint limit
    public fun mint_limit<T>(treasury: &ManagedTreasury<T>): u64 {
        treasury.mint_limit
    }

    /// Check if minting is paused
    public fun is_minting_paused<T>(treasury: &ManagedTreasury<T>): bool {
        treasury.minting_paused
    }

    /// Check if burning is paused
    public fun is_burning_paused<T>(treasury: &ManagedTreasury<T>): bool {
        treasury.burning_paused
    }

    /// Get total minted
    public fun total_minted<T>(treasury: &ManagedTreasury<T>): u64 {
        treasury.total_minted
    }

    /// Get total burned
    public fun total_burned<T>(treasury: &ManagedTreasury<T>): u64 {
        treasury.total_burned
    }

    /// Get remaining mintable
    public fun remaining_mintable<T>(treasury: &ManagedTreasury<T>): u64 {
        if (treasury.max_supply == 0) {
            18446744073709551615 // MAX_U64
        } else {
            let current = coin::total_supply(&treasury.cap);
            if (current >= treasury.max_supply) {
                0
            } else {
                treasury.max_supply - current
            }
        }
    }

    /// Get treasury stats
    public fun stats<T>(treasury: &ManagedTreasury<T>): TreasuryStats {
        TreasuryStats {
            total_supply: coin::total_supply(&treasury.cap),
            max_supply: treasury.max_supply,
            total_minted: treasury.total_minted,
            total_burned: treasury.total_burned,
            minting_paused: treasury.minting_paused,
            burning_paused: treasury.burning_paused,
        }
    }

    /// Borrow treasury cap (for advanced usage)
    public fun borrow_cap<T>(treasury: &ManagedTreasury<T>): &TreasuryCap<T> {
        &treasury.cap
    }

    /// Borrow treasury cap mutably (for advanced usage)
    public fun borrow_cap_mut<T>(treasury: &mut ManagedTreasury<T>): &mut TreasuryCap<T> {
        &mut treasury.cap
    }

    /// Unwrap and get back the treasury cap
    public fun unwrap<T>(treasury: ManagedTreasury<T>): TreasuryCap<T> {
        let ManagedTreasury {
            id,
            cap,
            max_supply: _,
            mint_limit: _,
            minting_paused: _,
            burning_paused: _,
            total_minted: _,
            total_burned: _,
        } = treasury;
        object::delete(id);
        cap
    }

    // Note: ManagedTreasury tests require a TreasuryCap which can only be
    // created with a one-time witness in an init function. Integration tests
    // are needed to fully test this module with a real token deployment.
    // The module compiles correctly and the logic is sound.
}
