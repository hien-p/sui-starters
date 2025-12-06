/// @title NFT Royalty
/// @notice Royalty calculation and distribution for NFT sales
/// @dev Part of @sui-starters/nft package
module sui_starters_nft::royalty {
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};

    // === Errors ===

    /// Royalty exceeds maximum (100%)
    const ERoyaltyTooHigh: u64 = 0;

    /// Invalid split percentages (must sum to 100%)
    const EInvalidSplit: u64 = 1;

    /// Insufficient payment for royalty
    const EInsufficientPayment: u64 = 2;

    /// Not authorized
    const ENotAuthorized: u64 = 3;

    // === Constants ===

    /// Maximum royalty in basis points (100% = 10000)
    const MAX_ROYALTY_BPS: u16 = 10000;

    /// Basis points denominator
    const BPS_DENOMINATOR: u64 = 10000;

    // === Structs ===

    /// Simple royalty configuration
    public struct RoyaltyConfig has store, copy, drop {
        /// Royalty in basis points (e.g., 500 = 5%)
        royalty_bps: u16,
        /// Recipient address
        recipient: address,
    }

    /// Royalty configuration with splits
    public struct RoyaltyWithSplits has store, drop {
        /// Total royalty in basis points
        royalty_bps: u16,
        /// Recipients with their share (in bps of royalty)
        recipients: vector<RoyaltyRecipient>,
    }

    /// Royalty recipient info
    public struct RoyaltyRecipient has store, copy, drop {
        /// Recipient address
        addr: address,
        /// Share in basis points (of the royalty amount)
        share_bps: u16,
    }

    /// Royalty calculation result
    public struct RoyaltyResult has copy, drop {
        /// Total royalty amount
        royalty_amount: u64,
        /// Seller receives
        seller_amount: u64,
        /// Original sale price
        sale_price: u64,
    }

    /// Accumulated royalties (for claiming)
    public struct RoyaltyVault<phantom T> has key, store {
        id: UID,
        /// Accumulated balance
        balance: Balance<T>,
        /// Total collected
        total_collected: u64,
        /// Total claimed
        total_claimed: u64,
    }

    // === Events ===

    /// Emitted when royalty is paid
    public struct RoyaltyPaid has copy, drop {
        sale_price: u64,
        royalty_amount: u64,
        recipient: address,
    }

    /// Emitted when royalty is split
    public struct RoyaltySplit has copy, drop {
        total_royalty: u64,
        recipient: address,
        amount: u64,
    }

    /// Emitted when royalty config is updated
    public struct RoyaltyConfigUpdated has copy, drop {
        royalty_bps: u16,
        recipient: address,
    }

    /// Emitted when royalty is claimed
    public struct RoyaltyClaimed has copy, drop {
        claimer: address,
        amount: u64,
    }

    // === RoyaltyConfig Functions ===

    /// Create new royalty config
    public fun new(royalty_bps: u16, recipient: address): RoyaltyConfig {
        assert!(royalty_bps <= MAX_ROYALTY_BPS, ERoyaltyTooHigh);

        RoyaltyConfig {
            royalty_bps,
            recipient,
        }
    }

    /// Create royalty config with no royalty
    public fun zero(): RoyaltyConfig {
        RoyaltyConfig {
            royalty_bps: 0,
            recipient: @0x0,
        }
    }

    /// Get royalty in basis points
    public fun royalty_bps(config: &RoyaltyConfig): u16 {
        config.royalty_bps
    }

    /// Get recipient
    public fun recipient(config: &RoyaltyConfig): address {
        config.recipient
    }

    /// Calculate royalty amount
    public fun calculate(config: &RoyaltyConfig, sale_price: u64): u64 {
        if (config.royalty_bps == 0) {
            return 0
        };
        ((sale_price as u128) * (config.royalty_bps as u128) / (BPS_DENOMINATOR as u128)) as u64
    }

    /// Calculate royalty with full result
    public fun calculate_full(config: &RoyaltyConfig, sale_price: u64): RoyaltyResult {
        let royalty_amount = calculate(config, sale_price);
        RoyaltyResult {
            royalty_amount,
            seller_amount: sale_price - royalty_amount,
            sale_price,
        }
    }

    /// Update royalty config
    public fun update(config: &mut RoyaltyConfig, royalty_bps: u16, recipient: address) {
        assert!(royalty_bps <= MAX_ROYALTY_BPS, ERoyaltyTooHigh);

        config.royalty_bps = royalty_bps;
        config.recipient = recipient;

        event::emit(RoyaltyConfigUpdated {
            royalty_bps,
            recipient,
        });
    }

    /// Pay royalty from coin
    public fun pay<T>(
        config: &RoyaltyConfig,
        payment: &mut Coin<T>,
        sale_price: u64,
        ctx: &mut TxContext,
    ): u64 {
        let royalty_amount = calculate(config, sale_price);
        if (royalty_amount == 0) {
            return 0
        };

        assert!(coin::value(payment) >= royalty_amount, EInsufficientPayment);

        let royalty_coin = coin::split(payment, royalty_amount, ctx);
        transfer::public_transfer(royalty_coin, config.recipient);

        event::emit(RoyaltyPaid {
            sale_price,
            royalty_amount,
            recipient: config.recipient,
        });

        royalty_amount
    }

    // === RoyaltyWithSplits Functions ===

    /// Create royalty with splits
    public fun new_with_splits(royalty_bps: u16): RoyaltyWithSplits {
        assert!(royalty_bps <= MAX_ROYALTY_BPS, ERoyaltyTooHigh);

        RoyaltyWithSplits {
            royalty_bps,
            recipients: vector[],
        }
    }

    /// Add recipient to splits
    public fun add_recipient(config: &mut RoyaltyWithSplits, addr: address, share_bps: u16) {
        let recipient = RoyaltyRecipient { addr, share_bps };
        vector::push_back(&mut config.recipients, recipient);
    }

    /// Validate splits sum to 100%
    public fun validate_splits(config: &RoyaltyWithSplits): bool {
        let mut total_share: u64 = 0;
        let len = vector::length(&config.recipients);
        let mut i = 0;
        while (i < len) {
            let recipient = vector::borrow(&config.recipients, i);
            total_share = total_share + (recipient.share_bps as u64);
            i = i + 1;
        };
        total_share == (BPS_DENOMINATOR as u64)
    }

    /// Get total royalty bps
    public fun splits_royalty_bps(config: &RoyaltyWithSplits): u16 {
        config.royalty_bps
    }

    /// Get recipient count
    public fun recipient_count(config: &RoyaltyWithSplits): u64 {
        vector::length(&config.recipients)
    }

    /// Calculate split royalty amounts
    public fun calculate_splits(config: &RoyaltyWithSplits, sale_price: u64): vector<u64> {
        let total_royalty = ((sale_price as u128) * (config.royalty_bps as u128) / (BPS_DENOMINATOR as u128)) as u64;

        let mut amounts = vector[];
        let len = vector::length(&config.recipients);
        let mut i = 0;
        while (i < len) {
            let recipient = vector::borrow(&config.recipients, i);
            let amount = ((total_royalty as u128) * (recipient.share_bps as u128) / (BPS_DENOMINATOR as u128)) as u64;
            vector::push_back(&mut amounts, amount);
            i = i + 1;
        };

        amounts
    }

    /// Pay royalty with splits
    public fun pay_splits<T>(
        config: &RoyaltyWithSplits,
        payment: &mut Coin<T>,
        sale_price: u64,
        ctx: &mut TxContext,
    ): u64 {
        let total_royalty = ((sale_price as u128) * (config.royalty_bps as u128) / (BPS_DENOMINATOR as u128)) as u64;
        if (total_royalty == 0) {
            return 0
        };

        assert!(coin::value(payment) >= total_royalty, EInsufficientPayment);

        let len = vector::length(&config.recipients);
        let mut i = 0;
        let mut paid: u64 = 0;

        while (i < len) {
            let recipient = vector::borrow(&config.recipients, i);
            let amount = if (i == len - 1) {
                // Last recipient gets remainder to avoid rounding issues
                total_royalty - paid
            } else {
                ((total_royalty as u128) * (recipient.share_bps as u128) / (BPS_DENOMINATOR as u128)) as u64
            };

            if (amount > 0) {
                let royalty_coin = coin::split(payment, amount, ctx);
                transfer::public_transfer(royalty_coin, recipient.addr);

                event::emit(RoyaltySplit {
                    total_royalty,
                    recipient: recipient.addr,
                    amount,
                });

                paid = paid + amount;
            };

            i = i + 1;
        };

        paid
    }

    // === RoyaltyVault Functions ===

    /// Create royalty vault
    public fun new_vault<T>(ctx: &mut TxContext): RoyaltyVault<T> {
        RoyaltyVault<T> {
            id: object::new(ctx),
            balance: balance::zero(),
            total_collected: 0,
            total_claimed: 0,
        }
    }

    /// Deposit royalty to vault
    public fun deposit<T>(vault: &mut RoyaltyVault<T>, payment: Coin<T>) {
        let amount = coin::value(&payment);
        balance::join(&mut vault.balance, coin::into_balance(payment));
        vault.total_collected = vault.total_collected + amount;
    }

    /// Claim from vault
    public fun claim<T>(vault: &mut RoyaltyVault<T>, amount: u64, ctx: &mut TxContext): Coin<T> {
        let claimed = coin::from_balance(balance::split(&mut vault.balance, amount), ctx);
        vault.total_claimed = vault.total_claimed + amount;

        event::emit(RoyaltyClaimed {
            claimer: ctx.sender(),
            amount,
        });

        claimed
    }

    /// Claim all from vault
    public fun claim_all<T>(vault: &mut RoyaltyVault<T>, ctx: &mut TxContext): Coin<T> {
        let amount = balance::value(&vault.balance);
        claim(vault, amount, ctx)
    }

    /// Get vault balance
    public fun vault_balance<T>(vault: &RoyaltyVault<T>): u64 {
        balance::value(&vault.balance)
    }

    /// Get total collected
    public fun total_collected<T>(vault: &RoyaltyVault<T>): u64 {
        vault.total_collected
    }

    /// Get total claimed
    public fun total_claimed<T>(vault: &RoyaltyVault<T>): u64 {
        vault.total_claimed
    }

    // === RoyaltyResult Accessors ===

    /// Get royalty amount from result
    public fun result_royalty_amount(result: &RoyaltyResult): u64 {
        result.royalty_amount
    }

    /// Get seller amount from result
    public fun result_seller_amount(result: &RoyaltyResult): u64 {
        result.seller_amount
    }

    /// Get sale price from result
    public fun result_sale_price(result: &RoyaltyResult): u64 {
        result.sale_price
    }

    // === Helper Functions ===

    /// Calculate percentage in basis points
    public fun bps_to_percentage(bps: u16): u64 {
        (bps as u64) * 100 / BPS_DENOMINATOR
    }

    /// Convert percentage to basis points
    public fun percentage_to_bps(percentage: u64): u16 {
        ((percentage * BPS_DENOMINATOR / 100) as u16)
    }

    // === Tests ===

    #[test]
    fun test_royalty_config_basic() {
        let config = new(500, @0x1); // 5%
        assert!(royalty_bps(&config) == 500, 0);
        assert!(recipient(&config) == @0x1, 1);
    }

    #[test]
    fun test_calculate_royalty() {
        let config = new(500, @0x1); // 5%

        // 5% of 10000 = 500
        assert!(calculate(&config, 10000) == 500, 0);

        // 5% of 1000 = 50
        assert!(calculate(&config, 1000) == 50, 1);

        // 5% of 100 = 5
        assert!(calculate(&config, 100) == 5, 2);
    }

    #[test]
    fun test_calculate_full() {
        let config = new(1000, @0x1); // 10%

        let result = calculate_full(&config, 10000);
        assert!(result_royalty_amount(&result) == 1000, 0);
        assert!(result_seller_amount(&result) == 9000, 1);
        assert!(result_sale_price(&result) == 10000, 2);
    }

    #[test]
    fun test_zero_royalty() {
        let config = zero();
        assert!(royalty_bps(&config) == 0, 0);
        assert!(calculate(&config, 10000) == 0, 1);
    }

    #[test]
    #[expected_failure(abort_code = ERoyaltyTooHigh)]
    fun test_royalty_too_high() {
        new(10001, @0x1); // Over 100%
    }

    #[test]
    fun test_royalty_with_splits() {
        let mut config = new_with_splits(1000); // 10% total

        // Artist gets 70%, Platform gets 30%
        add_recipient(&mut config, @0x1, 7000);
        add_recipient(&mut config, @0x2, 3000);

        assert!(validate_splits(&config), 0);
        assert!(splits_royalty_bps(&config) == 1000, 1);
        assert!(recipient_count(&config) == 2, 2);

        let amounts = calculate_splits(&config, 10000);
        // Total royalty = 1000
        // Artist = 700 (70% of 1000)
        // Platform = 300 (30% of 1000)
        assert!(*vector::borrow(&amounts, 0) == 700, 3);
        assert!(*vector::borrow(&amounts, 1) == 300, 4);
    }

    #[test]
    fun test_invalid_splits() {
        let mut config = new_with_splits(1000);

        // Only adds 50% - should not validate
        add_recipient(&mut config, @0x1, 5000);

        assert!(!validate_splits(&config), 0);
    }

    #[test]
    fun test_vault() {
        use sui::test_scenario;
        use sui::sui::SUI;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let vault = new_vault<SUI>(scenario.ctx());

            assert!(vault_balance(&vault) == 0, 0);
            assert!(total_collected(&vault) == 0, 1);
            assert!(total_claimed(&vault) == 0, 2);

            transfer::public_share_object(vault);
        };

        scenario.end();
    }

    #[test]
    fun test_bps_conversion() {
        // 500 bps = 5%
        assert!(bps_to_percentage(500) == 5, 0);

        // 1000 bps = 10%
        assert!(bps_to_percentage(1000) == 10, 1);

        // 5% = 500 bps
        assert!(percentage_to_bps(5) == 500, 2);

        // 10% = 1000 bps
        assert!(percentage_to_bps(10) == 1000, 3);
    }

    #[test]
    fun test_update_config() {
        let mut config = new(500, @0x1);
        update(&mut config, 1000, @0x2);

        assert!(royalty_bps(&config) == 1000, 0);
        assert!(recipient(&config) == @0x2, 1);
    }
}
