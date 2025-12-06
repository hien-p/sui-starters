/// @title Coin Flip Example
/// @notice Simple betting game with commit-reveal randomness
/// @dev Example demonstrating game mechanics and fair randomness
module coin_flip::coin_flip {
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::hash::keccak256;

    // === Errors ===

    const EInvalidBetAmount: u64 = 0;
    const EInsufficientHouseBalance: u64 = 1;
    const EGameNotFound: u64 = 2;
    const EInvalidReveal: u64 = 3;

    // === Structs ===

    /// House bank for the game
    public struct House has key {
        id: UID,
        /// House balance
        balance: Balance<SUI>,
        /// Minimum bet
        min_bet: u64,
        /// Maximum bet
        max_bet: u64,
        /// Total games played
        games_played: u64,
        /// Total paid out
        total_paid: u64,
    }

    /// Active game (commit phase)
    public struct Game has key {
        id: UID,
        player: address,
        bet_amount: u64,
        player_choice: bool, // true = heads, false = tails
        player_commitment: vector<u8>,
    }

    // === Events ===

    public struct GameCreated has copy, drop {
        game_id: ID,
        player: address,
        bet_amount: u64,
        choice: bool,
    }

    public struct GameResolved has copy, drop {
        game_id: ID,
        player: address,
        bet_amount: u64,
        player_choice: bool,
        result: bool,
        won: bool,
        payout: u64,
    }

    // === Entry Functions ===

    /// Initialize the house
    public entry fun create_house(
        initial_balance: Coin<SUI>,
        min_bet: u64,
        max_bet: u64,
        ctx: &mut TxContext,
    ) {
        let house = House {
            id: object::new(ctx),
            balance: coin::into_balance(initial_balance),
            min_bet,
            max_bet,
            games_played: 0,
            total_paid: 0,
        };

        transfer::share_object(house);
    }

    /// Start a game with a bet
    public entry fun play(
        house: &mut House,
        bet: Coin<SUI>,
        choice: bool, // true = heads
        commitment: vector<u8>, // hash(secret || choice)
        ctx: &mut TxContext,
    ) {
        let bet_amount = coin::value(&bet);

        assert!(bet_amount >= house.min_bet, EInvalidBetAmount);
        assert!(bet_amount <= house.max_bet, EInvalidBetAmount);
        assert!(balance::value(&house.balance) >= bet_amount * 2, EInsufficientHouseBalance);

        // Take bet
        balance::join(&mut house.balance, coin::into_balance(bet));

        let game = Game {
            id: object::new(ctx),
            player: ctx.sender(),
            bet_amount,
            player_choice: choice,
            player_commitment: commitment,
        };

        event::emit(GameCreated {
            game_id: object::id(&game),
            player: ctx.sender(),
            bet_amount,
            choice,
        });

        transfer::transfer(game, ctx.sender());
    }

    /// Resolve the game with house randomness
    public entry fun resolve(
        house: &mut House,
        game: Game,
        house_secret: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let Game {
            id,
            player,
            bet_amount,
            player_choice,
            player_commitment,
        } = game;

        // Generate result from combined randomness
        let mut combined = player_commitment;
        vector::append(&mut combined, house_secret);
        let hash = keccak256(&combined);
        let result = *vector::borrow(&hash, 0) % 2 == 0; // Even = heads

        let won = player_choice == result;
        let payout = if (won) { bet_amount * 2 } else { 0 };

        house.games_played = house.games_played + 1;

        if (won) {
            house.total_paid = house.total_paid + payout;
            let winnings = balance::split(&mut house.balance, payout);
            let payout_coin = coin::from_balance(winnings, ctx);
            transfer::public_transfer(payout_coin, player);
        };

        event::emit(GameResolved {
            game_id: object::uid_to_inner(&id),
            player,
            bet_amount,
            player_choice,
            result,
            won,
            payout,
        });

        object::delete(id);
    }

    /// Add funds to house
    public entry fun fund_house(house: &mut House, funds: Coin<SUI>) {
        balance::join(&mut house.balance, coin::into_balance(funds));
    }

    // === View Functions ===

    /// Get house balance
    public fun house_balance(house: &House): u64 {
        balance::value(&house.balance)
    }

    /// Get house stats
    public fun house_stats(house: &House): (u64, u64, u64, u64) {
        (
            balance::value(&house.balance),
            house.games_played,
            house.total_paid,
            house.min_bet,
        )
    }

    /// Get game info
    public fun game_info(game: &Game): (address, u64, bool) {
        (game.player, game.bet_amount, game.player_choice)
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_house() {
        let admin = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let initial = coin::mint_for_testing<SUI>(100000, scenario.ctx());
            create_house(initial, 100, 10000, scenario.ctx());
        };

        scenario.next_tx(admin);
        {
            let house = scenario.take_shared<House>();
            assert!(house_balance(&house) == 100000, 0);
            test_scenario::return_shared(house);
        };

        scenario.end();
    }

    #[test]
    fun test_play_game() {
        let admin = @0x1;
        let player = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // Create house
        {
            let initial = coin::mint_for_testing<SUI>(100000, scenario.ctx());
            create_house(initial, 100, 10000, scenario.ctx());
        };

        // Player plays
        scenario.next_tx(player);
        {
            let mut house = scenario.take_shared<House>();
            let bet = coin::mint_for_testing<SUI>(1000, scenario.ctx());

            let commitment = keccak256(&b"player_secret_heads");

            play(&mut house, bet, true, commitment, scenario.ctx());

            // House should have bet added
            assert!(house_balance(&house) == 101000, 0);

            test_scenario::return_shared(house);
        };

        // Check player has game
        scenario.next_tx(player);
        {
            let game = scenario.take_from_sender<Game>();
            let (p, amount, choice) = game_info(&game);
            assert!(p == player, 1);
            assert!(amount == 1000, 2);
            assert!(choice == true, 3);
            scenario.return_to_sender(game);
        };

        scenario.end();
    }
}
