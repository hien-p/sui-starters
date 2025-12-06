/// @title Basic NFT
/// @notice Simple NFT implementation - learn owned objects and display
/// @dev Demonstrates NFT minting, transfer, and display standard
module basic_nft::basic_nft {
    use std::string::{Self, String};
    use sui::event;
    use sui::package;
    use sui::display;

    // === Structs ===

    /// One-time witness for module initialization
    public struct BASIC_NFT has drop {}

    /// A simple NFT with name, description, and image URL
    public struct NFT has key, store {
        id: UID,
        /// NFT name
        name: String,
        /// NFT description
        description: String,
        /// Image URL
        image_url: String,
        /// Creator address
        creator: address,
        /// Token number in collection
        number: u64,
    }

    /// Mint capability - only holder can mint
    public struct MintCap has key, store {
        id: UID,
        /// Total minted so far
        minted: u64,
        /// Maximum supply (0 = unlimited)
        max_supply: u64,
    }

    // === Events ===

    public struct NFTMinted has copy, drop {
        nft_id: ID,
        name: String,
        number: u64,
        recipient: address,
    }

    public struct NFTBurned has copy, drop {
        nft_id: ID,
        name: String,
    }

    // === Errors ===

    const EMaxSupplyReached: u64 = 0;

    // === Init Function ===

    fun init(otw: BASIC_NFT, ctx: &mut TxContext) {
        // Create display
        let keys = vector[
            string::utf8(b"name"),
            string::utf8(b"description"),
            string::utf8(b"image_url"),
            string::utf8(b"creator"),
            string::utf8(b"number"),
        ];

        let values = vector[
            string::utf8(b"{name}"),
            string::utf8(b"{description}"),
            string::utf8(b"{image_url}"),
            string::utf8(b"{creator}"),
            string::utf8(b"#{number}"),
        ];

        let publisher = package::claim(otw, ctx);
        let mut disp = display::new_with_fields<NFT>(
            &publisher,
            keys,
            values,
            ctx,
        );

        display::update_version(&mut disp);

        // Create mint cap
        let mint_cap = MintCap {
            id: object::new(ctx),
            minted: 0,
            max_supply: 0, // Unlimited
        };

        transfer::public_transfer(publisher, ctx.sender());
        transfer::public_transfer(disp, ctx.sender());
        transfer::public_transfer(mint_cap, ctx.sender());
    }

    // === Entry Functions ===

    /// Mint a new NFT
    public entry fun mint(
        cap: &mut MintCap,
        name: String,
        description: String,
        image_url: String,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        if (cap.max_supply > 0) {
            assert!(cap.minted < cap.max_supply, EMaxSupplyReached);
        };

        cap.minted = cap.minted + 1;

        let nft = NFT {
            id: object::new(ctx),
            name,
            description,
            image_url,
            creator: ctx.sender(),
            number: cap.minted,
        };

        event::emit(NFTMinted {
            nft_id: object::id(&nft),
            name: nft.name,
            number: nft.number,
            recipient,
        });

        transfer::public_transfer(nft, recipient);
    }

    /// Burn an NFT
    public entry fun burn(nft: NFT) {
        let NFT {
            id,
            name,
            description: _,
            image_url: _,
            creator: _,
            number: _,
        } = nft;

        event::emit(NFTBurned {
            nft_id: object::uid_to_inner(&id),
            name,
        });

        object::delete(id);
    }

    /// Set max supply (0 = unlimited)
    public entry fun set_max_supply(cap: &mut MintCap, max_supply: u64) {
        cap.max_supply = max_supply;
    }

    // === View Functions ===

    /// Get NFT name
    public fun name(nft: &NFT): String {
        nft.name
    }

    /// Get NFT description
    public fun description(nft: &NFT): String {
        nft.description
    }

    /// Get NFT image URL
    public fun image_url(nft: &NFT): String {
        nft.image_url
    }

    /// Get NFT creator
    public fun creator(nft: &NFT): address {
        nft.creator
    }

    /// Get NFT number
    public fun number(nft: &NFT): u64 {
        nft.number
    }

    /// Get total minted
    public fun total_minted(cap: &MintCap): u64 {
        cap.minted
    }

    /// Get max supply
    public fun max_supply(cap: &MintCap): u64 {
        cap.max_supply
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_mint() {
        let creator = @0x1;
        let recipient = @0x2;
        let mut scenario = test_scenario::begin(creator);

        // Init
        {
            init(BASIC_NFT {}, scenario.ctx());
        };

        // Mint NFT
        scenario.next_tx(creator);
        {
            let mut cap = scenario.take_from_sender<MintCap>();

            mint(
                &mut cap,
                string::utf8(b"Cool NFT"),
                string::utf8(b"A very cool NFT"),
                string::utf8(b"https://example.com/nft.png"),
                recipient,
                scenario.ctx(),
            );

            assert!(total_minted(&cap) == 1, 0);

            scenario.return_to_sender(cap);
        };

        // Check recipient received NFT
        scenario.next_tx(recipient);
        {
            let nft = scenario.take_from_sender<NFT>();

            assert!(name(&nft) == string::utf8(b"Cool NFT"), 1);
            assert!(number(&nft) == 1, 2);

            scenario.return_to_sender(nft);
        };

        scenario.end();
    }

    #[test]
    fun test_burn() {
        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        // Init and mint
        {
            init(BASIC_NFT {}, scenario.ctx());
        };

        scenario.next_tx(creator);
        {
            let mut cap = scenario.take_from_sender<MintCap>();
            mint(
                &mut cap,
                string::utf8(b"To Burn"),
                string::utf8(b"This will be burned"),
                string::utf8(b"https://example.com/burn.png"),
                creator,
                scenario.ctx(),
            );
            scenario.return_to_sender(cap);
        };

        // Burn
        scenario.next_tx(creator);
        {
            let nft = scenario.take_from_sender<NFT>();
            burn(nft);
        };

        scenario.end();
    }

    #[test]
    fun test_max_supply() {
        let creator = @0x1;
        let mut scenario = test_scenario::begin(creator);

        {
            init(BASIC_NFT {}, scenario.ctx());
        };

        scenario.next_tx(creator);
        {
            let mut cap = scenario.take_from_sender<MintCap>();

            set_max_supply(&mut cap, 10);
            assert!(max_supply(&cap) == 10, 0);

            scenario.return_to_sender(cap);
        };

        scenario.end();
    }
}
