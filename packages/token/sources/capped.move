/// @title Capped Token
/// @notice Token with maximum supply cap
/// @dev Part of @sui-starters/token package
module sui_starters_token::capped {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::balance::{Self, Supply};
    use sui::event;

    // === Errors ===

    /// Would exceed max supply
    const EExceedsMaxSupply: u64 = 0;

    /// Invalid max supply
    const EInvalidMaxSupply: u64 = 1;

    /// Not authorized
    const ENotAuthorized: u64 = 2;

    // === Structs ===

    /// Capped supply wrapper for any coin type
    public struct CappedSupply<phantom T> has key, store {
        id: UID,
        /// Maximum allowed supply
        max_supply: u64,
        /// Current minted amount
        current_supply: u64,
        /// Is minting paused
        paused: bool,
    }

    /// Mint capability for capped tokens
    public struct CappedMintCap<phantom T> has key, store {
        id: UID,
        /// Reference to the capped supply
        supply_id: ID,
    }

    // === Events ===

    /// Emitted when capped supply is created
    public struct CappedSupplyCreated<phantom T> has copy, drop {
        supply_id: ID,
        max_supply: u64,
    }

    /// Emitted when tokens are minted
    public struct CappedMint<phantom T> has copy, drop {
        supply_id: ID,
        amount: u64,
        new_supply: u64,
        recipient: address,
    }

    /// Emitted when supply cap is updated
    public struct MaxSupplyUpdated<phantom T> has copy, drop {
        supply_id: ID,
        old_max: u64,
        new_max: u64,
    }

    // === Create Functions ===

    /// Create a new capped supply tracker
    public fun new<T>(
        max_supply: u64,
        ctx: &mut TxContext,
    ): (CappedSupply<T>, CappedMintCap<T>) {
        assert!(max_supply > 0, EInvalidMaxSupply);

        let supply = CappedSupply<T> {
            id: object::new(ctx),
            max_supply,
            current_supply: 0,
            paused: false,
        };

        let supply_id = object::id(&supply);

        event::emit(CappedSupplyCreated<T> {
            supply_id,
            max_supply,
        });

        let cap = CappedMintCap<T> {
            id: object::new(ctx),
            supply_id,
        };

        (supply, cap)
    }

    // === Mint Functions ===

    /// Mint tokens with cap check
    public fun mint<T>(
        supply: &mut CappedSupply<T>,
        treasury: &mut TreasuryCap<T>,
        _cap: &CappedMintCap<T>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        assert!(!supply.paused, ENotAuthorized);
        assert!(
            supply.current_supply + amount <= supply.max_supply,
            EExceedsMaxSupply,
        );

        supply.current_supply = supply.current_supply + amount;

        let coin = coin::mint(treasury, amount, ctx);

        event::emit(CappedMint<T> {
            supply_id: object::id(supply),
            amount,
            new_supply: supply.current_supply,
            recipient,
        });

        transfer::public_transfer(coin, recipient);
    }

    /// Mint and return coin (for composability)
    public fun mint_coin<T>(
        supply: &mut CappedSupply<T>,
        treasury: &mut TreasuryCap<T>,
        _cap: &CappedMintCap<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(!supply.paused, ENotAuthorized);
        assert!(
            supply.current_supply + amount <= supply.max_supply,
            EExceedsMaxSupply,
        );

        supply.current_supply = supply.current_supply + amount;

        event::emit(CappedMint<T> {
            supply_id: object::id(supply),
            amount,
            new_supply: supply.current_supply,
            recipient: ctx.sender(),
        });

        coin::mint(treasury, amount, ctx)
    }

    /// Check if amount can be minted
    public fun can_mint<T>(supply: &CappedSupply<T>, amount: u64): bool {
        !supply.paused && supply.current_supply + amount <= supply.max_supply
    }

    /// Get remaining mintable amount
    public fun remaining_supply<T>(supply: &CappedSupply<T>): u64 {
        supply.max_supply - supply.current_supply
    }

    // === Admin Functions ===

    /// Update max supply (can only increase)
    public fun increase_max_supply<T>(
        supply: &mut CappedSupply<T>,
        _cap: &CappedMintCap<T>,
        new_max: u64,
    ) {
        assert!(new_max > supply.max_supply, EInvalidMaxSupply);

        let old_max = supply.max_supply;
        supply.max_supply = new_max;

        event::emit(MaxSupplyUpdated<T> {
            supply_id: object::id(supply),
            old_max,
            new_max,
        });
    }

    /// Pause minting
    public fun pause<T>(
        supply: &mut CappedSupply<T>,
        _cap: &CappedMintCap<T>,
    ) {
        supply.paused = true;
    }

    /// Unpause minting
    public fun unpause<T>(
        supply: &mut CappedSupply<T>,
        _cap: &CappedMintCap<T>,
    ) {
        supply.paused = false;
    }

    // === View Functions ===

    /// Get max supply
    public fun max_supply<T>(supply: &CappedSupply<T>): u64 {
        supply.max_supply
    }

    /// Get current supply
    public fun current_supply<T>(supply: &CappedSupply<T>): u64 {
        supply.current_supply
    }

    /// Is minting paused
    public fun is_paused<T>(supply: &CappedSupply<T>): bool {
        supply.paused
    }

    /// Get supply info
    public fun supply_info<T>(supply: &CappedSupply<T>): (u64, u64, u64, bool) {
        (
            supply.max_supply,
            supply.current_supply,
            supply.max_supply - supply.current_supply,
            supply.paused,
        )
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_capped_supply() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let (supply, cap) = new<sui::sui::SUI>(1000000, scenario.ctx());

            assert!(max_supply(&supply) == 1000000, 0);
            assert!(current_supply(&supply) == 0, 1);
            assert!(remaining_supply(&supply) == 1000000, 2);
            assert!(!is_paused(&supply), 3);

            transfer::public_share_object(supply);
            transfer::public_transfer(cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_can_mint() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let (mut supply, cap) = new<sui::sui::SUI>(1000, scenario.ctx());

            assert!(can_mint(&supply, 500), 0);
            assert!(can_mint(&supply, 1000), 1);
            assert!(!can_mint(&supply, 1001), 2);

            // Simulate minting
            supply.current_supply = 800;
            assert!(can_mint(&supply, 200), 3);
            assert!(!can_mint(&supply, 201), 4);

            transfer::public_share_object(supply);
            transfer::public_transfer(cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_pause_unpause() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let (mut supply, cap) = new<sui::sui::SUI>(1000, scenario.ctx());

            assert!(can_mint(&supply, 100), 0);

            pause(&mut supply, &cap);
            assert!(is_paused(&supply), 1);
            assert!(!can_mint(&supply, 100), 2);

            unpause(&mut supply, &cap);
            assert!(!is_paused(&supply), 3);
            assert!(can_mint(&supply, 100), 4);

            transfer::public_share_object(supply);
            transfer::public_transfer(cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_increase_max_supply() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let (mut supply, cap) = new<sui::sui::SUI>(1000, scenario.ctx());

            assert!(max_supply(&supply) == 1000, 0);

            increase_max_supply(&mut supply, &cap, 2000);
            assert!(max_supply(&supply) == 2000, 1);

            transfer::public_share_object(supply);
            transfer::public_transfer(cap, admin);
        };

        scenario.end();
    }
}
