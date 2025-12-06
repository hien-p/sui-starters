/// @title Mint Capability
/// @notice Controlled minting with phases and limits
/// @dev Part of @sui-starters/nft package
module sui_starters_nft::mint_cap {
    use sui::event;
    use sui::clock::Clock;

    // === Errors ===

    /// Mint not started
    const EMintNotStarted: u64 = 0;

    /// Mint ended
    const EMintEnded: u64 = 1;

    /// Mint limit reached
    const EMintLimitReached: u64 = 2;

    /// Not authorized to mint
    const ENotAuthorized: u64 = 3;

    /// Per-wallet limit reached
    const EPerWalletLimitReached: u64 = 4;

    /// Invalid mint phase
    const EInvalidPhase: u64 = 5;

    // === Structs ===

    /// Mint capability for a collection
    public struct MintCap<phantom T> has key, store {
        id: UID,
        /// Total minted using this cap
        minted: u64,
        /// Maximum mintable with this cap (0 = unlimited)
        max_mint: u64,
        /// Per-transaction limit
        per_tx_limit: u64,
    }

    /// Timed mint capability with start/end times
    public struct TimedMintCap<phantom T> has key, store {
        id: UID,
        /// Total minted
        minted: u64,
        /// Maximum mintable
        max_mint: u64,
        /// Per-transaction limit
        per_tx_limit: u64,
        /// Mint start time (0 = no start restriction)
        start_time: u64,
        /// Mint end time (0 = no end restriction)
        end_time: u64,
    }

    /// Phased mint with multiple phases
    public struct MintPhase has store, copy, drop {
        /// Phase name
        name: vector<u8>,
        /// Start time
        start_time: u64,
        /// End time
        end_time: u64,
        /// Price in this phase
        price: u64,
        /// Max per wallet in this phase
        max_per_wallet: u64,
        /// Max total for this phase
        max_supply: u64,
        /// Current minted in this phase
        minted: u64,
    }

    /// Multi-phase mint capability
    public struct PhasedMintCap<phantom T> has key, store {
        id: UID,
        /// Current phase index
        current_phase: u64,
        /// All phases
        phases: vector<MintPhase>,
        /// Total minted across all phases
        total_minted: u64,
    }

    /// Per-wallet mint tracker
    public struct WalletMintTracker has key {
        id: UID,
        /// Mints per wallet: wallet -> count
        mints: sui::table::Table<address, u64>,
    }

    // === Events ===

    /// Emitted when mint cap is created
    public struct MintCapCreated has copy, drop {
        cap_id: ID,
        max_mint: u64,
    }

    /// Emitted when mint occurs
    public struct Minted has copy, drop {
        cap_id: ID,
        minter: address,
        amount: u64,
        total_minted: u64,
    }

    /// Emitted when phase changes
    public struct PhaseChanged has copy, drop {
        cap_id: ID,
        previous_phase: u64,
        new_phase: u64,
    }

    // === MintCap Functions ===

    /// Create new mint capability
    public fun new<T>(max_mint: u64, per_tx_limit: u64, ctx: &mut TxContext): MintCap<T> {
        let cap = MintCap<T> {
            id: object::new(ctx),
            minted: 0,
            max_mint,
            per_tx_limit,
        };

        event::emit(MintCapCreated {
            cap_id: object::id(&cap),
            max_mint,
        });

        cap
    }

    /// Create unlimited mint capability
    public fun new_unlimited<T>(per_tx_limit: u64, ctx: &mut TxContext): MintCap<T> {
        new<T>(0, per_tx_limit, ctx)
    }

    /// Check if can mint amount
    public fun can_mint<T>(cap: &MintCap<T>, amount: u64): bool {
        if (amount > cap.per_tx_limit && cap.per_tx_limit > 0) {
            return false
        };
        if (cap.max_mint == 0) {
            return true // Unlimited
        };
        cap.minted + amount <= cap.max_mint
    }

    /// Use mint capability (returns amount to mint)
    public fun use_mint<T>(cap: &mut MintCap<T>, amount: u64, ctx: &TxContext): u64 {
        assert!(can_mint(cap, amount), EMintLimitReached);

        cap.minted = cap.minted + amount;

        event::emit(Minted {
            cap_id: object::id(cap),
            minter: ctx.sender(),
            amount,
            total_minted: cap.minted,
        });

        amount
    }

    /// Get minted count
    public fun minted<T>(cap: &MintCap<T>): u64 {
        cap.minted
    }

    /// Get max mint
    public fun max_mint<T>(cap: &MintCap<T>): u64 {
        cap.max_mint
    }

    /// Get remaining
    public fun remaining<T>(cap: &MintCap<T>): u64 {
        if (cap.max_mint == 0) {
            18446744073709551615 // MAX_U64
        } else if (cap.minted >= cap.max_mint) {
            0
        } else {
            cap.max_mint - cap.minted
        }
    }

    /// Get per-tx limit
    public fun per_tx_limit<T>(cap: &MintCap<T>): u64 {
        cap.per_tx_limit
    }

    /// Update per-tx limit
    public fun set_per_tx_limit<T>(cap: &mut MintCap<T>, limit: u64) {
        cap.per_tx_limit = limit;
    }

    /// Destroy mint cap
    public fun destroy<T>(cap: MintCap<T>) {
        let MintCap { id, minted: _, max_mint: _, per_tx_limit: _ } = cap;
        object::delete(id);
    }

    // === TimedMintCap Functions ===

    /// Create timed mint capability
    public fun new_timed<T>(
        max_mint: u64,
        per_tx_limit: u64,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext,
    ): TimedMintCap<T> {
        TimedMintCap<T> {
            id: object::new(ctx),
            minted: 0,
            max_mint,
            per_tx_limit,
            start_time,
            end_time,
        }
    }

    /// Check if timed mint is active
    public fun is_active<T>(cap: &TimedMintCap<T>, clock: &Clock): bool {
        let now = sui::clock::timestamp_ms(clock);

        if (cap.start_time > 0 && now < cap.start_time) {
            return false
        };
        if (cap.end_time > 0 && now > cap.end_time) {
            return false
        };
        true
    }

    /// Check if can mint with timed cap
    public fun timed_can_mint<T>(cap: &TimedMintCap<T>, amount: u64, clock: &Clock): bool {
        if (!is_active(cap, clock)) {
            return false
        };
        if (amount > cap.per_tx_limit && cap.per_tx_limit > 0) {
            return false
        };
        if (cap.max_mint == 0) {
            return true
        };
        cap.minted + amount <= cap.max_mint
    }

    /// Use timed mint capability
    public fun use_timed_mint<T>(
        cap: &mut TimedMintCap<T>,
        amount: u64,
        clock: &Clock,
        ctx: &TxContext
    ): u64 {
        let now = sui::clock::timestamp_ms(clock);

        if (cap.start_time > 0) {
            assert!(now >= cap.start_time, EMintNotStarted);
        };
        if (cap.end_time > 0) {
            assert!(now <= cap.end_time, EMintEnded);
        };
        assert!(timed_can_mint(cap, amount, clock), EMintLimitReached);

        cap.minted = cap.minted + amount;

        event::emit(Minted {
            cap_id: object::id(cap),
            minter: ctx.sender(),
            amount,
            total_minted: cap.minted,
        });

        amount
    }

    /// Get timed cap minted count
    public fun timed_minted<T>(cap: &TimedMintCap<T>): u64 {
        cap.minted
    }

    /// Get timed cap start time
    public fun start_time<T>(cap: &TimedMintCap<T>): u64 {
        cap.start_time
    }

    /// Get timed cap end time
    public fun end_time<T>(cap: &TimedMintCap<T>): u64 {
        cap.end_time
    }

    /// Update timed cap times
    public fun set_times<T>(cap: &mut TimedMintCap<T>, start_time: u64, end_time: u64) {
        cap.start_time = start_time;
        cap.end_time = end_time;
    }

    /// Destroy timed mint cap
    public fun destroy_timed<T>(cap: TimedMintCap<T>) {
        let TimedMintCap { id, minted: _, max_mint: _, per_tx_limit: _, start_time: _, end_time: _ } = cap;
        object::delete(id);
    }

    // === PhasedMintCap Functions ===

    /// Create phased mint capability
    public fun new_phased<T>(ctx: &mut TxContext): PhasedMintCap<T> {
        PhasedMintCap<T> {
            id: object::new(ctx),
            current_phase: 0,
            phases: vector[],
            total_minted: 0,
        }
    }

    /// Add a phase
    public fun add_phase<T>(
        cap: &mut PhasedMintCap<T>,
        name: vector<u8>,
        start_time: u64,
        end_time: u64,
        price: u64,
        max_per_wallet: u64,
        max_supply: u64,
    ) {
        let phase = MintPhase {
            name,
            start_time,
            end_time,
            price,
            max_per_wallet,
            max_supply,
            minted: 0,
        };
        vector::push_back(&mut cap.phases, phase);
    }

    /// Get current phase
    public fun current_phase<T>(cap: &PhasedMintCap<T>): u64 {
        cap.current_phase
    }

    /// Get phase count
    public fun phase_count<T>(cap: &PhasedMintCap<T>): u64 {
        vector::length(&cap.phases)
    }

    /// Set current phase
    public fun set_phase<T>(cap: &mut PhasedMintCap<T>, phase: u64) {
        assert!(phase < vector::length(&cap.phases), EInvalidPhase);
        let previous = cap.current_phase;
        cap.current_phase = phase;

        event::emit(PhaseChanged {
            cap_id: object::id(cap),
            previous_phase: previous,
            new_phase: phase,
        });
    }

    /// Get current phase info
    public fun get_phase_info<T>(cap: &PhasedMintCap<T>): MintPhase {
        *vector::borrow(&cap.phases, cap.current_phase)
    }

    /// Get phase price
    public fun phase_price<T>(cap: &PhasedMintCap<T>): u64 {
        let phase = vector::borrow(&cap.phases, cap.current_phase);
        phase.price
    }

    /// Check if current phase is active
    public fun phase_is_active<T>(cap: &PhasedMintCap<T>, clock: &Clock): bool {
        if (vector::is_empty(&cap.phases)) {
            return false
        };

        let phase = vector::borrow(&cap.phases, cap.current_phase);
        let now = sui::clock::timestamp_ms(clock);

        if (phase.start_time > 0 && now < phase.start_time) {
            return false
        };
        if (phase.end_time > 0 && now > phase.end_time) {
            return false
        };
        if (phase.max_supply > 0 && phase.minted >= phase.max_supply) {
            return false
        };

        true
    }

    /// Use phased mint
    public fun use_phased_mint<T>(
        cap: &mut PhasedMintCap<T>,
        amount: u64,
        clock: &Clock,
        ctx: &TxContext,
    ): u64 {
        assert!(phase_is_active(cap, clock), EInvalidPhase);

        let phase = vector::borrow_mut(&mut cap.phases, cap.current_phase);
        if (phase.max_supply > 0) {
            assert!(phase.minted + amount <= phase.max_supply, EMintLimitReached);
        };

        phase.minted = phase.minted + amount;
        cap.total_minted = cap.total_minted + amount;

        event::emit(Minted {
            cap_id: object::id(cap),
            minter: ctx.sender(),
            amount,
            total_minted: cap.total_minted,
        });

        amount
    }

    /// Get total minted across all phases
    public fun phased_total_minted<T>(cap: &PhasedMintCap<T>): u64 {
        cap.total_minted
    }

    /// Destroy phased mint cap
    public fun destroy_phased<T>(cap: PhasedMintCap<T>) {
        let PhasedMintCap { id, current_phase: _, phases: _, total_minted: _ } = cap;
        object::delete(id);
    }

    // === WalletMintTracker Functions ===

    /// Create wallet mint tracker
    public fun new_tracker(ctx: &mut TxContext): WalletMintTracker {
        WalletMintTracker {
            id: object::new(ctx),
            mints: sui::table::new(ctx),
        }
    }

    /// Get wallet mint count
    public fun wallet_minted(tracker: &WalletMintTracker, wallet: address): u64 {
        if (sui::table::contains(&tracker.mints, wallet)) {
            *sui::table::borrow(&tracker.mints, wallet)
        } else {
            0
        }
    }

    /// Track wallet mint
    public fun track_mint(tracker: &mut WalletMintTracker, wallet: address, amount: u64) {
        if (sui::table::contains(&tracker.mints, wallet)) {
            let current = sui::table::borrow_mut(&mut tracker.mints, wallet);
            *current = *current + amount;
        } else {
            sui::table::add(&mut tracker.mints, wallet, amount);
        };
    }

    /// Check if wallet can mint (given a limit)
    public fun wallet_can_mint(
        tracker: &WalletMintTracker,
        wallet: address,
        amount: u64,
        limit: u64,
    ): bool {
        if (limit == 0) {
            return true // No limit
        };
        wallet_minted(tracker, wallet) + amount <= limit
    }

    /// Require wallet can mint
    public fun require_wallet_can_mint(
        tracker: &WalletMintTracker,
        wallet: address,
        amount: u64,
        limit: u64,
    ) {
        assert!(wallet_can_mint(tracker, wallet, amount, limit), EPerWalletLimitReached);
    }

    // === Tests ===

    /// Test witness type
    public struct TEST_MINT has drop {}

    #[test]
    fun test_mint_cap_basic() {
        use sui::test_scenario;

        let minter = @0x1;
        let mut scenario = test_scenario::begin(minter);

        {
            let mut cap = new<TEST_MINT>(100, 10, scenario.ctx());
            assert!(minted(&cap) == 0, 0);
            assert!(max_mint(&cap) == 100, 1);
            assert!(remaining(&cap) == 100, 2);
            assert!(can_mint(&cap, 5), 3);

            let amount = use_mint(&mut cap, 5, scenario.ctx());
            assert!(amount == 5, 4);
            assert!(minted(&cap) == 5, 5);
            assert!(remaining(&cap) == 95, 6);

            destroy(cap);
        };

        scenario.end();
    }

    #[test]
    fun test_mint_cap_unlimited() {
        use sui::test_scenario;

        let minter = @0x1;
        let mut scenario = test_scenario::begin(minter);

        {
            let cap = new_unlimited<TEST_MINT>(10, scenario.ctx());
            assert!(max_mint(&cap) == 0, 0);
            assert!(remaining(&cap) == 18446744073709551615, 1);
            assert!(can_mint(&cap, 10), 2);

            destroy(cap);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EMintLimitReached)]
    fun test_mint_cap_limit() {
        use sui::test_scenario;

        let minter = @0x1;
        let mut scenario = test_scenario::begin(minter);

        {
            let mut cap = new<TEST_MINT>(10, 10, scenario.ctx());
            use_mint(&mut cap, 10, scenario.ctx());
            use_mint(&mut cap, 1, scenario.ctx()); // Should fail

            destroy(cap);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EMintLimitReached)]
    fun test_per_tx_limit() {
        use sui::test_scenario;

        let minter = @0x1;
        let mut scenario = test_scenario::begin(minter);

        {
            let mut cap = new<TEST_MINT>(100, 5, scenario.ctx()); // Max 5 per tx
            use_mint(&mut cap, 10, scenario.ctx()); // Should fail - exceeds per-tx limit

            destroy(cap);
        };

        scenario.end();
    }

    #[test]
    fun test_wallet_tracker() {
        use sui::test_scenario;

        let admin = @0xAD;
        let user1 = @0x1;
        let user2 = @0x2;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut tracker = new_tracker(scenario.ctx());

            assert!(wallet_minted(&tracker, user1) == 0, 0);
            assert!(wallet_can_mint(&tracker, user1, 5, 10), 1);

            track_mint(&mut tracker, user1, 5);
            assert!(wallet_minted(&tracker, user1) == 5, 2);
            assert!(wallet_can_mint(&tracker, user1, 5, 10), 3);
            assert!(!wallet_can_mint(&tracker, user1, 6, 10), 4);

            track_mint(&mut tracker, user2, 3);
            assert!(wallet_minted(&tracker, user2) == 3, 5);

            transfer::share_object(tracker);
        };

        scenario.end();
    }

    #[test]
    fun test_phased_mint() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut cap = new_phased<TEST_MINT>(scenario.ctx());

            // Add whitelist phase
            add_phase(
                &mut cap,
                b"Whitelist",
                0, // No start time restriction for test
                0, // No end time restriction for test
                1000, // Price
                5, // Max per wallet
                100, // Max supply
            );

            // Add public phase
            add_phase(
                &mut cap,
                b"Public",
                0,
                0,
                2000,
                10,
                1000,
            );

            assert!(phase_count(&cap) == 2, 0);
            assert!(current_phase(&cap) == 0, 1);
            assert!(phase_price(&cap) == 1000, 2);

            set_phase(&mut cap, 1);
            assert!(current_phase(&cap) == 1, 3);
            assert!(phase_price(&cap) == 2000, 4);

            destroy_phased(cap);
        };

        scenario.end();
    }
}
