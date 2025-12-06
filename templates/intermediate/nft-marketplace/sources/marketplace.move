/// @title NFT Marketplace
/// @notice Basic marketplace for buying and selling NFTs
/// @dev Demonstrates kiosk alternatives, escrow, and fee collection
module nft_marketplace::marketplace {
    use std::string::String;
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::dynamic_object_field as dof;

    // === Errors ===

    const EInvalidPrice: u64 = 0;
    const ENotOwner: u64 = 1;
    const EListingNotFound: u64 = 2;
    const EInsufficientPayment: u64 = 3;

    // === Constants ===

    const FEE_BPS: u64 = 250; // 2.5% fee

    // === Structs ===

    /// Marketplace shared object
    public struct Marketplace has key {
        id: UID,
        /// Fee recipient
        fee_recipient: address,
        /// Collected fees
        fees: Balance<SUI>,
        /// Total volume traded
        total_volume: u64,
        /// Total listings ever
        total_listings: u64,
    }

    /// Listing for an NFT
    public struct Listing<phantom T: key + store> has key, store {
        id: UID,
        /// Item for sale
        item_id: ID,
        /// Seller
        seller: address,
        /// Price in SUI
        price: u64,
    }

    /// Listing key for dynamic field
    public struct ListingKey has copy, drop, store {
        item_id: ID,
    }

    /// Admin capability
    public struct MarketplaceAdmin has key, store {
        id: UID,
    }

    // === Events ===

    public struct MarketplaceCreated has copy, drop {
        marketplace_id: ID,
        fee_recipient: address,
    }

    public struct ItemListed has copy, drop {
        marketplace_id: ID,
        listing_id: ID,
        item_id: ID,
        seller: address,
        price: u64,
    }

    public struct ItemDelisted has copy, drop {
        marketplace_id: ID,
        item_id: ID,
        seller: address,
    }

    public struct ItemSold has copy, drop {
        marketplace_id: ID,
        item_id: ID,
        seller: address,
        buyer: address,
        price: u64,
        fee: u64,
    }

    // === Entry Functions ===

    /// Create marketplace
    public entry fun create(fee_recipient: address, ctx: &mut TxContext) {
        let marketplace = Marketplace {
            id: object::new(ctx),
            fee_recipient,
            fees: balance::zero(),
            total_volume: 0,
            total_listings: 0,
        };

        let admin = MarketplaceAdmin {
            id: object::new(ctx),
        };

        event::emit(MarketplaceCreated {
            marketplace_id: object::id(&marketplace),
            fee_recipient,
        });

        transfer::share_object(marketplace);
        transfer::transfer(admin, ctx.sender());
    }

    /// List an item for sale
    public fun list<T: key + store>(
        marketplace: &mut Marketplace,
        item: T,
        price: u64,
        ctx: &mut TxContext,
    ) {
        assert!(price > 0, EInvalidPrice);

        let item_id = object::id(&item);

        let listing = Listing<T> {
            id: object::new(ctx),
            item_id,
            seller: ctx.sender(),
            price,
        };

        let listing_id = object::id(&listing);

        event::emit(ItemListed {
            marketplace_id: object::id(marketplace),
            listing_id,
            item_id,
            seller: ctx.sender(),
            price,
        });

        marketplace.total_listings = marketplace.total_listings + 1;

        // Store item and listing
        dof::add(&mut marketplace.id, ListingKey { item_id }, item);
        dof::add(&mut marketplace.id, listing_id, listing);
    }

    /// Delist an item (seller only)
    public fun delist<T: key + store>(
        marketplace: &mut Marketplace,
        item_id: ID,
        listing_id: ID,
        ctx: &mut TxContext,
    ): T {
        // Get and verify listing
        let listing: Listing<T> = dof::remove(&mut marketplace.id, listing_id);

        assert!(listing.seller == ctx.sender(), ENotOwner);
        assert!(listing.item_id == item_id, EListingNotFound);

        let Listing { id, item_id: _, seller, price: _ } = listing;
        object::delete(id);

        event::emit(ItemDelisted {
            marketplace_id: object::id(marketplace),
            item_id,
            seller,
        });

        // Return item
        dof::remove(&mut marketplace.id, ListingKey { item_id })
    }

    /// Buy a listed item
    public fun buy<T: key + store>(
        marketplace: &mut Marketplace,
        item_id: ID,
        listing_id: ID,
        mut payment: Coin<SUI>,
        ctx: &mut TxContext,
    ): T {
        // Get and consume listing
        let listing: Listing<T> = dof::remove(&mut marketplace.id, listing_id);

        assert!(listing.item_id == item_id, EListingNotFound);
        assert!(coin::value(&payment) >= listing.price, EInsufficientPayment);

        let Listing { id, item_id: _, seller, price } = listing;
        object::delete(id);

        // Calculate fee
        let fee_amount = (price * FEE_BPS) / 10000;
        let seller_amount = price - fee_amount;

        // Split payment
        let fee_coin = coin::split(&mut payment, fee_amount, ctx);
        let seller_coin = coin::split(&mut payment, seller_amount, ctx);

        // Collect fee
        balance::join(&mut marketplace.fees, coin::into_balance(fee_coin));
        marketplace.total_volume = marketplace.total_volume + price;

        // Pay seller
        transfer::public_transfer(seller_coin, seller);

        // Return excess payment
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, ctx.sender());
        } else {
            coin::destroy_zero(payment);
        };

        event::emit(ItemSold {
            marketplace_id: object::id(marketplace),
            item_id,
            seller,
            buyer: ctx.sender(),
            price,
            fee: fee_amount,
        });

        // Return item to buyer
        dof::remove(&mut marketplace.id, ListingKey { item_id })
    }

    /// Withdraw collected fees (admin only)
    public entry fun withdraw_fees(
        marketplace: &mut Marketplace,
        _admin: &MarketplaceAdmin,
        ctx: &mut TxContext,
    ) {
        let amount = balance::value(&marketplace.fees);
        let fees = balance::split(&mut marketplace.fees, amount);
        let coin = coin::from_balance(fees, ctx);
        transfer::public_transfer(coin, marketplace.fee_recipient);
    }

    /// Update fee recipient
    public entry fun set_fee_recipient(
        marketplace: &mut Marketplace,
        _admin: &MarketplaceAdmin,
        new_recipient: address,
    ) {
        marketplace.fee_recipient = new_recipient;
    }

    // === View Functions ===

    /// Get marketplace stats
    public fun stats(marketplace: &Marketplace): (u64, u64, u64) {
        (
            marketplace.total_volume,
            marketplace.total_listings,
            balance::value(&marketplace.fees),
        )
    }

    /// Get listing info
    public fun listing_info<T: key + store>(listing: &Listing<T>): (ID, address, u64) {
        (listing.item_id, listing.seller, listing.price)
    }

    /// Get fee bps
    public fun fee_bps(): u64 { FEE_BPS }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test_only]
    public struct TestNFT has key, store {
        id: UID,
        name: String,
    }

    #[test]
    fun test_create_marketplace() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            create(admin, scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let marketplace = scenario.take_shared<Marketplace>();
            let (volume, listings, fees) = stats(&marketplace);

            assert!(volume == 0, 0);
            assert!(listings == 0, 1);
            assert!(fees == 0, 2);

            test_scenario::return_shared(marketplace);
        };

        scenario.end();
    }

    #[test]
    fun test_list_and_buy() {
        let admin = @0xAD;
        let seller = @0x1;
        let buyer = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // Create marketplace
        {
            create(admin, scenario.ctx());
        };

        // Seller lists NFT
        scenario.next_tx(seller);
        {
            let mut marketplace = scenario.take_shared<Marketplace>();

            let nft = TestNFT {
                id: object::new(scenario.ctx()),
                name: std::string::utf8(b"Test NFT"),
            };

            list(&mut marketplace, nft, 1000, scenario.ctx());

            let (_, listings, _) = stats(&marketplace);
            assert!(listings == 1, 0);

            test_scenario::return_shared(marketplace);
        };

        scenario.end();
    }
}
