/// @title Burnable Token
/// @notice Token burn functionality with tracking
/// @dev Part of @sui-starters/token package
module sui_starters_token::burnable {
    use sui::coin::{Self, Coin, TreasuryCap};
    use sui::event;

    // === Errors ===

    /// Burn amount exceeds balance
    const EInsufficientBalance: u64 = 0;

    /// Burning is paused
    const EBurningPaused: u64 = 1;

    // === Structs ===

    /// Burn tracker for any coin type
    public struct BurnTracker<phantom T> has key, store {
        id: UID,
        /// Total amount burned
        total_burned: u64,
        /// Total burn transactions
        burn_count: u64,
        /// Is burning paused
        paused: bool,
    }

    /// Admin capability for burn tracker
    public struct BurnAdminCap<phantom T> has key, store {
        id: UID,
        tracker_id: ID,
    }

    // === Events ===

    /// Emitted when tokens are burned
    public struct TokensBurned<phantom T> has copy, drop {
        tracker_id: ID,
        burner: address,
        amount: u64,
        total_burned: u64,
    }

    /// Emitted when burn tracker is created
    public struct BurnTrackerCreated<phantom T> has copy, drop {
        tracker_id: ID,
    }

    // === Create Functions ===

    /// Create a new burn tracker
    public fun new<T>(ctx: &mut TxContext): (BurnTracker<T>, BurnAdminCap<T>) {
        let tracker = BurnTracker<T> {
            id: object::new(ctx),
            total_burned: 0,
            burn_count: 0,
            paused: false,
        };

        let tracker_id = object::id(&tracker);

        event::emit(BurnTrackerCreated<T> { tracker_id });

        let cap = BurnAdminCap<T> {
            id: object::new(ctx),
            tracker_id,
        };

        (tracker, cap)
    }

    // === Burn Functions ===

    /// Burn tokens and track
    public fun burn<T>(
        tracker: &mut BurnTracker<T>,
        treasury: &mut TreasuryCap<T>,
        coin: Coin<T>,
        ctx: &TxContext,
    ) {
        assert!(!tracker.paused, EBurningPaused);

        let amount = coin::value(&coin);
        coin::burn(treasury, coin);

        tracker.total_burned = tracker.total_burned + amount;
        tracker.burn_count = tracker.burn_count + 1;

        event::emit(TokensBurned<T> {
            tracker_id: object::id(tracker),
            burner: ctx.sender(),
            amount,
            total_burned: tracker.total_burned,
        });
    }

    /// Burn specific amount from coin
    public fun burn_amount<T>(
        tracker: &mut BurnTracker<T>,
        treasury: &mut TreasuryCap<T>,
        coin: &mut Coin<T>,
        amount: u64,
        ctx: &mut TxContext,
    ) {
        assert!(!tracker.paused, EBurningPaused);
        assert!(coin::value(coin) >= amount, EInsufficientBalance);

        let to_burn = coin::split(coin, amount, ctx);
        coin::burn(treasury, to_burn);

        tracker.total_burned = tracker.total_burned + amount;
        tracker.burn_count = tracker.burn_count + 1;

        event::emit(TokensBurned<T> {
            tracker_id: object::id(tracker),
            burner: ctx.sender(),
            amount,
            total_burned: tracker.total_burned,
        });
    }

    /// Burn without tracking (simple burn)
    public fun burn_simple<T>(
        treasury: &mut TreasuryCap<T>,
        coin: Coin<T>,
    ) {
        coin::burn(treasury, coin);
    }

    // === Admin Functions ===

    /// Pause burning
    public fun pause<T>(
        tracker: &mut BurnTracker<T>,
        _cap: &BurnAdminCap<T>,
    ) {
        tracker.paused = true;
    }

    /// Unpause burning
    public fun unpause<T>(
        tracker: &mut BurnTracker<T>,
        _cap: &BurnAdminCap<T>,
    ) {
        tracker.paused = false;
    }

    // === View Functions ===

    /// Get total burned amount
    public fun total_burned<T>(tracker: &BurnTracker<T>): u64 {
        tracker.total_burned
    }

    /// Get burn count
    public fun burn_count<T>(tracker: &BurnTracker<T>): u64 {
        tracker.burn_count
    }

    /// Is burning paused
    public fun is_paused<T>(tracker: &BurnTracker<T>): bool {
        tracker.paused
    }

    /// Get burn stats
    public fun burn_stats<T>(tracker: &BurnTracker<T>): (u64, u64, bool) {
        (tracker.total_burned, tracker.burn_count, tracker.paused)
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_burn_tracker() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let (tracker, cap) = new<sui::sui::SUI>(scenario.ctx());

            assert!(total_burned(&tracker) == 0, 0);
            assert!(burn_count(&tracker) == 0, 1);
            assert!(!is_paused(&tracker), 2);

            transfer::public_share_object(tracker);
            transfer::public_transfer(cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_pause_unpause() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let (mut tracker, cap) = new<sui::sui::SUI>(scenario.ctx());

            assert!(!is_paused(&tracker), 0);

            pause(&mut tracker, &cap);
            assert!(is_paused(&tracker), 1);

            unpause(&mut tracker, &cap);
            assert!(!is_paused(&tracker), 2);

            transfer::public_share_object(tracker);
            transfer::public_transfer(cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_burn_stats() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let (mut tracker, cap) = new<sui::sui::SUI>(scenario.ctx());

            // Manually update for testing
            tracker.total_burned = 1000;
            tracker.burn_count = 5;

            let (total, count, paused) = burn_stats(&tracker);
            assert!(total == 1000, 0);
            assert!(count == 5, 1);
            assert!(!paused, 2);

            transfer::public_share_object(tracker);
            transfer::public_transfer(cap, admin);
        };

        scenario.end();
    }
}
