/// @title Game Currency
/// @notice Closed-loop game currency system
/// @dev Part of @sui-starters/gaming package
module sui_starters_gaming::currency {
    use std::string::String;
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin, TreasuryCap};

    // === Errors ===

    const EInsufficientBalance: u64 = 0;
    const EExceedsMaxSupply: u64 = 1;
    const EPaused: u64 = 2;
    const ENotAuthorized: u64 = 3;
    const EInvalidAmount: u64 = 4;

    // === Structs ===

    /// Game currency manager
    public struct CurrencyManager<phantom T> has key, store {
        id: UID,
        name: String,
        /// Treasury cap for minting
        treasury_cap: TreasuryCap<T>,
        /// Max supply (0 = unlimited)
        max_supply: u64,
        /// Current circulating supply
        circulating_supply: u64,
        /// Total ever minted
        total_minted: u64,
        /// Total burned
        total_burned: u64,
        /// Is currency paused
        paused: bool,
    }

    /// Player's in-game wallet
    public struct GameWallet<phantom T> has key, store {
        id: UID,
        owner: address,
        balance: Balance<T>,
        /// Total earned
        total_earned: u64,
        /// Total spent
        total_spent: u64,
    }

    /// Shop that accepts game currency
    public struct GameShop<phantom T> has key, store {
        id: UID,
        name: String,
        /// Revenue collected
        revenue: Balance<T>,
        /// Total sales
        total_sales: u64,
    }

    // === Events ===

    public struct CurrencyMinted has copy, drop {
        recipient: address,
        amount: u64,
        new_supply: u64,
    }

    public struct CurrencyBurned has copy, drop {
        from: address,
        amount: u64,
        new_supply: u64,
    }

    public struct CurrencyTransferred has copy, drop {
        from: address,
        to: address,
        amount: u64,
    }

    public struct ShopPurchase has copy, drop {
        shop_id: ID,
        buyer: address,
        amount: u64,
        item: String,
    }

    // === Create Functions ===

    /// Create new currency manager
    public fun new_manager<T>(
        treasury_cap: TreasuryCap<T>,
        name: String,
        max_supply: u64,
        ctx: &mut TxContext,
    ): CurrencyManager<T> {
        CurrencyManager {
            id: object::new(ctx),
            name,
            treasury_cap,
            max_supply,
            circulating_supply: 0,
            total_minted: 0,
            total_burned: 0,
            paused: false,
        }
    }

    /// Create new game wallet
    public fun new_wallet<T>(ctx: &mut TxContext): GameWallet<T> {
        GameWallet {
            id: object::new(ctx),
            owner: ctx.sender(),
            balance: balance::zero(),
            total_earned: 0,
            total_spent: 0,
        }
    }

    /// Create new game shop
    public fun new_shop<T>(name: String, ctx: &mut TxContext): GameShop<T> {
        GameShop {
            id: object::new(ctx),
            name,
            revenue: balance::zero(),
            total_sales: 0,
        }
    }

    // === Core Functions ===

    /// Mint currency to wallet (game rewards)
    public fun mint_to_wallet<T>(
        manager: &mut CurrencyManager<T>,
        wallet: &mut GameWallet<T>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(!manager.paused, EPaused);
        assert!(amount > 0, EInvalidAmount);

        if (manager.max_supply > 0) {
            assert!(
                manager.circulating_supply + amount <= manager.max_supply,
                EExceedsMaxSupply,
            );
        };

        let minted = coin::mint(&mut manager.treasury_cap, amount, ctx);
        let minted_balance = coin::into_balance(minted);

        balance::join(&mut wallet.balance, minted_balance);
        wallet.total_earned = wallet.total_earned + amount;

        manager.circulating_supply = manager.circulating_supply + amount;
        manager.total_minted = manager.total_minted + amount;

        event::emit(CurrencyMinted {
            recipient: wallet.owner,
            amount,
            new_supply: manager.circulating_supply,
        });
    }

    /// Spend currency at shop
    public fun spend_at_shop<T>(
        manager: &mut CurrencyManager<T>,
        wallet: &mut GameWallet<T>,
        shop: &mut GameShop<T>,
        amount: u64,
        item: String,
    ) {
        assert!(!manager.paused, EPaused);
        assert!(balance::value(&wallet.balance) >= amount, EInsufficientBalance);

        let spent = balance::split(&mut wallet.balance, amount);
        balance::join(&mut shop.revenue, spent);

        wallet.total_spent = wallet.total_spent + amount;
        shop.total_sales = shop.total_sales + 1;

        event::emit(ShopPurchase {
            shop_id: object::id(shop),
            buyer: wallet.owner,
            amount,
            item,
        });
    }

    /// Burn currency from wallet
    public fun burn_from_wallet<T>(
        manager: &mut CurrencyManager<T>,
        wallet: &mut GameWallet<T>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(balance::value(&wallet.balance) >= amount, EInsufficientBalance);

        let to_burn = balance::split(&mut wallet.balance, amount);
        let coin_to_burn = coin::from_balance(to_burn, ctx);
        coin::burn(&mut manager.treasury_cap, coin_to_burn);

        manager.circulating_supply = manager.circulating_supply - amount;
        manager.total_burned = manager.total_burned + amount;

        event::emit(CurrencyBurned {
            from: wallet.owner,
            amount,
            new_supply: manager.circulating_supply,
        });
    }

    /// Transfer between wallets
    public fun transfer<T>(
        manager: &CurrencyManager<T>,
        from: &mut GameWallet<T>,
        to: &mut GameWallet<T>,
        amount: u64,
    ) {
        assert!(!manager.paused, EPaused);
        assert!(balance::value(&from.balance) >= amount, EInsufficientBalance);

        let transferred = balance::split(&mut from.balance, amount);
        balance::join(&mut to.balance, transferred);

        from.total_spent = from.total_spent + amount;
        to.total_earned = to.total_earned + amount;

        event::emit(CurrencyTransferred {
            from: from.owner,
            to: to.owner,
            amount,
        });
    }

    /// Deposit coin to wallet
    public fun deposit<T>(wallet: &mut GameWallet<T>, coin: Coin<T>) {
        let amount = coin::value(&coin);
        let coin_balance = coin::into_balance(coin);
        balance::join(&mut wallet.balance, coin_balance);
        wallet.total_earned = wallet.total_earned + amount;
    }

    /// Withdraw from wallet to coin
    public fun withdraw<T>(
        wallet: &mut GameWallet<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(balance::value(&wallet.balance) >= amount, EInsufficientBalance);
        let withdrawn = balance::split(&mut wallet.balance, amount);
        wallet.total_spent = wallet.total_spent + amount;
        coin::from_balance(withdrawn, ctx)
    }

    // === Admin Functions ===

    /// Pause/unpause currency
    public fun set_paused<T>(manager: &mut CurrencyManager<T>, paused: bool) {
        manager.paused = paused;
    }

    /// Withdraw shop revenue
    public fun withdraw_revenue<T>(
        shop: &mut GameShop<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        let withdrawn = balance::split(&mut shop.revenue, amount);
        coin::from_balance(withdrawn, ctx)
    }

    // === View Functions ===

    /// Get wallet balance
    public fun wallet_balance<T>(wallet: &GameWallet<T>): u64 {
        balance::value(&wallet.balance)
    }

    /// Get wallet total earned
    public fun wallet_total_earned<T>(wallet: &GameWallet<T>): u64 {
        wallet.total_earned
    }

    /// Get wallet total spent
    public fun wallet_total_spent<T>(wallet: &GameWallet<T>): u64 {
        wallet.total_spent
    }

    /// Get circulating supply
    public fun circulating_supply<T>(manager: &CurrencyManager<T>): u64 {
        manager.circulating_supply
    }

    /// Get max supply
    public fun max_supply<T>(manager: &CurrencyManager<T>): u64 {
        manager.max_supply
    }

    /// Get total minted
    public fun total_minted<T>(manager: &CurrencyManager<T>): u64 {
        manager.total_minted
    }

    /// Get total burned
    public fun total_burned<T>(manager: &CurrencyManager<T>): u64 {
        manager.total_burned
    }

    /// Is currency paused
    public fun is_paused<T>(manager: &CurrencyManager<T>): bool {
        manager.paused
    }

    /// Get shop revenue
    public fun shop_revenue<T>(shop: &GameShop<T>): u64 {
        balance::value(&shop.revenue)
    }

    /// Get shop total sales
    public fun shop_total_sales<T>(shop: &GameShop<T>): u64 {
        shop.total_sales
    }

    /// Calculate remaining mintable
    public fun remaining_mintable<T>(manager: &CurrencyManager<T>): u64 {
        if (manager.max_supply == 0) {
            // Unlimited
            18446744073709551615 // u64::MAX
        } else {
            manager.max_supply - manager.circulating_supply
        }
    }

    // === Tests ===

    #[test_only]
    use std::string;
    #[test_only]
    use sui::sui::SUI;

    #[test]
    fun test_create_wallet() {
        let ctx = &mut tx_context::dummy();
        let wallet = new_wallet<SUI>(ctx);

        assert!(wallet_balance(&wallet) == 0, 0);
        assert!(wallet_total_earned(&wallet) == 0, 1);
        assert!(wallet_total_spent(&wallet) == 0, 2);

        let GameWallet { id, owner: _, balance, total_earned: _, total_spent: _ } = wallet;
        balance::destroy_zero(balance);
        object::delete(id);
    }

    #[test]
    fun test_create_shop() {
        let ctx = &mut tx_context::dummy();
        let shop = new_shop<SUI>(string::utf8(b"Item Shop"), ctx);

        assert!(shop_revenue(&shop) == 0, 0);
        assert!(shop_total_sales(&shop) == 0, 1);

        let GameShop { id, name: _, revenue, total_sales: _ } = shop;
        balance::destroy_zero(revenue);
        object::delete(id);
    }
}
