/// @title Simple Coin
/// @notice Basic fungible token - learn Coin and TreasuryCap patterns
/// @dev Demonstrates coin creation, minting, and basic tokenomics
module simple_coin::simple_coin {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::url;

    // === One-Time Witness ===

    /// One-time witness for coin creation
    public struct SIMPLE_COIN has drop {}

    // === Init Function ===

    fun init(witness: SIMPLE_COIN, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            witness,
            9, // 9 decimals like SUI
            b"SIMPLE",
            b"Simple Coin",
            b"A simple fungible token example for learning Sui Move",
            option::some(url::new_unsafe_from_bytes(b"https://example.com/simple-coin.png")),
            ctx,
        );

        // Transfer ownership
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury_cap, ctx.sender());
    }

    // === Entry Functions ===

    /// Mint new coins to recipient
    public entry fun mint(
        treasury_cap: &mut TreasuryCap<SIMPLE_COIN>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        let coin = coin::mint(treasury_cap, amount, ctx);
        transfer::public_transfer(coin, recipient);
    }

    /// Burn coins
    public entry fun burn(
        treasury_cap: &mut TreasuryCap<SIMPLE_COIN>,
        coin: Coin<SIMPLE_COIN>,
    ) {
        coin::burn(treasury_cap, coin);
    }

    /// Split coins
    public entry fun split(
        coin: &mut Coin<SIMPLE_COIN>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext,
    ) {
        let split_coin = coin::split(coin, amount, ctx);
        transfer::public_transfer(split_coin, recipient);
    }

    /// Merge coins
    public entry fun merge(
        coin: &mut Coin<SIMPLE_COIN>,
        other: Coin<SIMPLE_COIN>,
    ) {
        coin::join(coin, other);
    }

    // === View Functions ===

    /// Get total supply
    public fun total_supply(treasury_cap: &TreasuryCap<SIMPLE_COIN>): u64 {
        coin::total_supply(treasury_cap)
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_init() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            init(SIMPLE_COIN {}, scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let treasury = scenario.take_from_sender<TreasuryCap<SIMPLE_COIN>>();
            assert!(total_supply(&treasury) == 0, 0);
            scenario.return_to_sender(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_mint() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        {
            init(SIMPLE_COIN {}, scenario.ctx());
        };

        // Mint to user
        scenario.next_tx(admin);
        {
            let mut treasury = scenario.take_from_sender<TreasuryCap<SIMPLE_COIN>>();
            mint(&mut treasury, 1000000000, user, scenario.ctx()); // 1 token
            assert!(total_supply(&treasury) == 1000000000, 0);
            scenario.return_to_sender(treasury);
        };

        // Check user balance
        scenario.next_tx(user);
        {
            let coin = scenario.take_from_sender<Coin<SIMPLE_COIN>>();
            assert!(coin::value(&coin) == 1000000000, 1);
            scenario.return_to_sender(coin);
        };

        scenario.end();
    }

    #[test]
    fun test_burn() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            init(SIMPLE_COIN {}, scenario.ctx());
        };

        // Mint
        scenario.next_tx(admin);
        {
            let mut treasury = scenario.take_from_sender<TreasuryCap<SIMPLE_COIN>>();
            mint(&mut treasury, 1000000000, admin, scenario.ctx());
            scenario.return_to_sender(treasury);
        };

        // Burn
        scenario.next_tx(admin);
        {
            let mut treasury = scenario.take_from_sender<TreasuryCap<SIMPLE_COIN>>();
            let coin = scenario.take_from_sender<Coin<SIMPLE_COIN>>();

            burn(&mut treasury, coin);
            assert!(total_supply(&treasury) == 0, 0);

            scenario.return_to_sender(treasury);
        };

        scenario.end();
    }

    #[test]
    fun test_split_and_merge() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        {
            init(SIMPLE_COIN {}, scenario.ctx());
        };

        // Mint
        scenario.next_tx(admin);
        {
            let mut treasury = scenario.take_from_sender<TreasuryCap<SIMPLE_COIN>>();
            mint(&mut treasury, 1000, admin, scenario.ctx());
            scenario.return_to_sender(treasury);
        };

        // Split
        scenario.next_tx(admin);
        {
            let mut coin = scenario.take_from_sender<Coin<SIMPLE_COIN>>();
            split(&mut coin, 400, user, scenario.ctx());
            assert!(coin::value(&coin) == 600, 0);
            scenario.return_to_sender(coin);
        };

        // Check user received split
        scenario.next_tx(user);
        {
            let coin = scenario.take_from_sender<Coin<SIMPLE_COIN>>();
            assert!(coin::value(&coin) == 400, 1);
            transfer::public_transfer(coin, admin);
        };

        // Merge back
        scenario.next_tx(admin);
        {
            let mut coin1 = scenario.take_from_sender<Coin<SIMPLE_COIN>>();
            let coin2 = scenario.take_from_sender<Coin<SIMPLE_COIN>>();
            merge(&mut coin1, coin2);
            assert!(coin::value(&coin1) == 1000, 2);
            scenario.return_to_sender(coin1);
        };

        scenario.end();
    }
}
