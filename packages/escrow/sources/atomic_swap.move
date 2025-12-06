/// @title Atomic Swap
/// @notice Trustless atomic swaps between two parties
/// @dev Part of @sui-starters/escrow package
module sui_starters_escrow::atomic_swap {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::Clock;
    use sui::event;
    use sui::hash;

    // === Errors ===

    /// Swap has expired
    const ESwapExpired: u64 = 0;

    /// Invalid secret
    const EInvalidSecret: u64 = 1;

    /// Not the recipient
    const ENotRecipient: u64 = 2;

    /// Not the creator
    const ENotCreator: u64 = 3;

    /// Swap not expired yet
    const ESwapNotExpired: u64 = 4;

    /// Invalid amount
    const EInvalidAmount: u64 = 5;

    /// Already claimed
    const EAlreadyClaimed: u64 = 6;

    // === Structs ===

    /// Atomic swap with hash-locked secret
    public struct AtomicSwap<phantom T> has key, store {
        id: UID,
        /// Creator (who locked the funds)
        creator: address,
        /// Recipient (who can claim with secret)
        recipient: address,
        /// Locked funds
        balance: Balance<T>,
        /// Hash of the secret (SHA3-256)
        secret_hash: vector<u8>,
        /// Expiration timestamp
        expiration: u64,
        /// Whether claimed
        claimed: bool,
    }

    /// Simple escrow between two parties
    public struct Escrow<phantom T> has key, store {
        id: UID,
        /// Depositor
        depositor: address,
        /// Recipient
        recipient: address,
        /// Escrowed funds
        balance: Balance<T>,
        /// Description/purpose
        description: vector<u8>,
        /// Creation timestamp
        created_at: u64,
    }

    /// Two-way swap (both parties deposit)
    public struct TwoWaySwap<phantom A, phantom B> has key, store {
        id: UID,
        /// Party A
        party_a: address,
        /// Party B
        party_b: address,
        /// Tokens from party A
        balance_a: Balance<A>,
        /// Tokens from party B
        balance_b: Balance<B>,
        /// Party A deposited
        a_deposited: bool,
        /// Party B deposited
        b_deposited: bool,
        /// Expected amount from A
        expected_a: u64,
        /// Expected amount from B
        expected_b: u64,
        /// Expiration
        expiration: u64,
    }

    // === Events ===

    /// Emitted when atomic swap is created
    public struct SwapCreated has copy, drop {
        swap_id: ID,
        creator: address,
        recipient: address,
        amount: u64,
        expiration: u64,
    }

    /// Emitted when swap is claimed
    public struct SwapClaimed has copy, drop {
        swap_id: ID,
        claimer: address,
        amount: u64,
    }

    /// Emitted when swap is refunded
    public struct SwapRefunded has copy, drop {
        swap_id: ID,
        refunded_to: address,
        amount: u64,
    }

    /// Emitted when escrow is created
    public struct EscrowCreated has copy, drop {
        escrow_id: ID,
        depositor: address,
        recipient: address,
        amount: u64,
    }

    /// Emitted when escrow is released
    public struct EscrowReleased has copy, drop {
        escrow_id: ID,
        recipient: address,
        amount: u64,
    }

    /// Emitted when two-way swap completes
    public struct TwoWaySwapCompleted has copy, drop {
        swap_id: ID,
        party_a: address,
        party_b: address,
        amount_a: u64,
        amount_b: u64,
    }

    // === Atomic Swap Functions ===

    /// Create a new atomic swap
    /// The secret should be kept private until ready to claim
    public fun create_atomic_swap<T>(
        tokens: Coin<T>,
        recipient: address,
        secret_hash: vector<u8>,
        duration_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): AtomicSwap<T> {
        let amount = coin::value(&tokens);
        assert!(amount > 0, EInvalidAmount);

        let now = sui::clock::timestamp_ms(clock);
        let expiration = now + duration_ms;

        let swap = AtomicSwap<T> {
            id: object::new(ctx),
            creator: ctx.sender(),
            recipient,
            balance: coin::into_balance(tokens),
            secret_hash,
            expiration,
            claimed: false,
        };

        event::emit(SwapCreated {
            swap_id: object::id(&swap),
            creator: ctx.sender(),
            recipient,
            amount,
            expiration,
        });

        swap
    }

    /// Claim the swap with the correct secret
    public fun claim_atomic_swap<T>(
        swap: AtomicSwap<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let now = sui::clock::timestamp_ms(clock);
        assert!(now < swap.expiration, ESwapExpired);
        assert!(ctx.sender() == swap.recipient, ENotRecipient);
        assert!(!swap.claimed, EAlreadyClaimed);

        // Verify secret
        let computed_hash = hash::keccak256(&secret);
        assert!(computed_hash == swap.secret_hash, EInvalidSecret);

        let AtomicSwap {
            id,
            creator: _,
            recipient,
            balance,
            secret_hash: _,
            expiration: _,
            claimed: _,
        } = swap;

        let amount = balance::value(&balance);
        let swap_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(SwapClaimed {
            swap_id,
            claimer: recipient,
            amount,
        });

        coin::from_balance(balance, ctx)
    }

    /// Refund the swap after expiration
    public fun refund_atomic_swap<T>(
        swap: AtomicSwap<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let now = sui::clock::timestamp_ms(clock);
        assert!(now >= swap.expiration, ESwapNotExpired);
        assert!(ctx.sender() == swap.creator, ENotCreator);

        let AtomicSwap {
            id,
            creator,
            recipient: _,
            balance,
            secret_hash: _,
            expiration: _,
            claimed: _,
        } = swap;

        let amount = balance::value(&balance);
        let swap_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(SwapRefunded {
            swap_id,
            refunded_to: creator,
            amount,
        });

        coin::from_balance(balance, ctx)
    }

    // === Escrow Functions ===

    /// Create simple escrow
    public fun create_escrow<T>(
        tokens: Coin<T>,
        recipient: address,
        description: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Escrow<T> {
        let amount = coin::value(&tokens);
        assert!(amount > 0, EInvalidAmount);

        let now = sui::clock::timestamp_ms(clock);

        let escrow = Escrow<T> {
            id: object::new(ctx),
            depositor: ctx.sender(),
            recipient,
            balance: coin::into_balance(tokens),
            description,
            created_at: now,
        };

        event::emit(EscrowCreated {
            escrow_id: object::id(&escrow),
            depositor: ctx.sender(),
            recipient,
            amount,
        });

        escrow
    }

    /// Release escrow to recipient (only depositor can release)
    public fun release_escrow<T>(
        escrow: Escrow<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(ctx.sender() == escrow.depositor, ENotCreator);

        let Escrow {
            id,
            depositor: _,
            recipient,
            balance,
            description: _,
            created_at: _,
        } = escrow;

        let amount = balance::value(&balance);
        let escrow_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(EscrowReleased {
            escrow_id,
            recipient,
            amount,
        });

        coin::from_balance(balance, ctx)
    }

    /// Cancel escrow and return to depositor
    public fun cancel_escrow<T>(
        escrow: Escrow<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(ctx.sender() == escrow.depositor, ENotCreator);

        let Escrow {
            id,
            depositor,
            recipient: _,
            balance,
            description: _,
            created_at: _,
        } = escrow;

        let amount = balance::value(&balance);
        let swap_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(SwapRefunded {
            swap_id,
            refunded_to: depositor,
            amount,
        });

        coin::from_balance(balance, ctx)
    }

    // === Two-Way Swap Functions ===

    /// Create a two-way swap
    public fun create_two_way_swap<A, B>(
        party_b: address,
        expected_a: u64,
        expected_b: u64,
        duration_ms: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): TwoWaySwap<A, B> {
        let now = sui::clock::timestamp_ms(clock);

        TwoWaySwap<A, B> {
            id: object::new(ctx),
            party_a: ctx.sender(),
            party_b,
            balance_a: balance::zero(),
            balance_b: balance::zero(),
            a_deposited: false,
            b_deposited: false,
            expected_a,
            expected_b,
            expiration: now + duration_ms,
        }
    }

    /// Party A deposits their tokens
    public fun deposit_a<A, B>(
        swap: &mut TwoWaySwap<A, B>,
        tokens: Coin<A>,
        ctx: &TxContext,
    ) {
        assert!(ctx.sender() == swap.party_a, ENotCreator);
        assert!(coin::value(&tokens) >= swap.expected_a, EInvalidAmount);

        balance::join(&mut swap.balance_a, coin::into_balance(tokens));
        swap.a_deposited = true;
    }

    /// Party B deposits their tokens
    public fun deposit_b<A, B>(
        swap: &mut TwoWaySwap<A, B>,
        tokens: Coin<B>,
        ctx: &TxContext,
    ) {
        assert!(ctx.sender() == swap.party_b, ENotRecipient);
        assert!(coin::value(&tokens) >= swap.expected_b, EInvalidAmount);

        balance::join(&mut swap.balance_b, coin::into_balance(tokens));
        swap.b_deposited = true;
    }

    /// Execute the swap (anyone can call once both deposited)
    public fun execute_two_way_swap<A, B>(
        swap: TwoWaySwap<A, B>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Coin<B>, Coin<A>) {
        let now = sui::clock::timestamp_ms(clock);
        assert!(now < swap.expiration, ESwapExpired);
        assert!(swap.a_deposited && swap.b_deposited, EInvalidAmount);

        let TwoWaySwap {
            id,
            party_a,
            party_b,
            balance_a,
            balance_b,
            a_deposited: _,
            b_deposited: _,
            expected_a: _,
            expected_b: _,
            expiration: _,
        } = swap;

        let amount_a = balance::value(&balance_a);
        let amount_b = balance::value(&balance_b);
        let swap_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(TwoWaySwapCompleted {
            swap_id,
            party_a,
            party_b,
            amount_a,
            amount_b,
        });

        // Party A gets B's tokens, Party B gets A's tokens
        (coin::from_balance(balance_b, ctx), coin::from_balance(balance_a, ctx))
    }

    /// Cancel two-way swap after expiration
    public fun cancel_two_way_swap<A, B>(
        swap: TwoWaySwap<A, B>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): (Coin<A>, Coin<B>) {
        let now = sui::clock::timestamp_ms(clock);
        assert!(now >= swap.expiration, ESwapNotExpired);

        let TwoWaySwap {
            id,
            party_a: _,
            party_b: _,
            balance_a,
            balance_b,
            a_deposited: _,
            b_deposited: _,
            expected_a: _,
            expected_b: _,
            expiration: _,
        } = swap;

        object::delete(id);

        // Return tokens to original depositors
        (coin::from_balance(balance_a, ctx), coin::from_balance(balance_b, ctx))
    }

    // === View Functions ===

    /// Get swap creator
    public fun swap_creator<T>(swap: &AtomicSwap<T>): address {
        swap.creator
    }

    /// Get swap recipient
    public fun swap_recipient<T>(swap: &AtomicSwap<T>): address {
        swap.recipient
    }

    /// Get swap balance
    public fun swap_balance<T>(swap: &AtomicSwap<T>): u64 {
        balance::value(&swap.balance)
    }

    /// Get swap expiration
    public fun swap_expiration<T>(swap: &AtomicSwap<T>): u64 {
        swap.expiration
    }

    /// Check if swap expired
    public fun is_swap_expired<T>(swap: &AtomicSwap<T>, clock: &Clock): bool {
        let now = sui::clock::timestamp_ms(clock);
        now >= swap.expiration
    }

    /// Get escrow depositor
    public fun escrow_depositor<T>(escrow: &Escrow<T>): address {
        escrow.depositor
    }

    /// Get escrow recipient
    public fun escrow_recipient<T>(escrow: &Escrow<T>): address {
        escrow.recipient
    }

    /// Get escrow balance
    public fun escrow_balance<T>(escrow: &Escrow<T>): u64 {
        balance::value(&escrow.balance)
    }

    /// Get two-way swap status
    public fun two_way_status<A, B>(swap: &TwoWaySwap<A, B>): (bool, bool) {
        (swap.a_deposited, swap.b_deposited)
    }

    /// Hash a secret for creating atomic swap
    public fun hash_secret(secret: &vector<u8>): vector<u8> {
        hash::keccak256(secret)
    }

    // === Tests ===

    #[test]
    fun test_create_escrow() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let admin = @0xAD;
        let recipient = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let escrow = create_escrow(tokens, recipient, b"Payment", &test_clock, scenario.ctx());

            assert!(escrow_depositor(&escrow) == admin, 0);
            assert!(escrow_recipient(&escrow) == recipient, 1);
            assert!(escrow_balance(&escrow) == 1000, 2);

            clock::destroy_for_testing(test_clock);
            transfer::public_share_object(escrow);
        };

        scenario.end();
    }

    #[test]
    fun test_release_escrow() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let admin = @0xAD;
        let recipient = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let escrow = create_escrow(tokens, recipient, b"Payment", &test_clock, scenario.ctx());

            // Release escrow
            let released = release_escrow(escrow, scenario.ctx());
            assert!(coin::value(&released) == 1000, 0);

            coin::burn_for_testing(released);
            clock::destroy_for_testing(test_clock);
        };

        scenario.end();
    }

    #[test]
    fun test_hash_secret() {
        let secret = b"my_secret_key";
        let hash = hash_secret(&secret);

        // Hash should be 32 bytes
        assert!(vector::length(&hash) == 32, 0);

        // Same secret should produce same hash
        let hash2 = hash_secret(&secret);
        assert!(hash == hash2, 1);
    }

    #[test]
    fun test_atomic_swap_create() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;
        use sui::clock;

        let creator = @0xAA;
        let recipient = @0xBB;
        let mut scenario = test_scenario::begin(creator);

        {
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            let secret_hash = hash_secret(&b"secret123");

            let swap = create_atomic_swap(
                tokens,
                recipient,
                secret_hash,
                60000, // 1 minute
                &test_clock,
                scenario.ctx(),
            );

            assert!(swap_creator(&swap) == creator, 0);
            assert!(swap_recipient(&swap) == recipient, 1);
            assert!(swap_balance(&swap) == 1000, 2);
            assert!(swap_expiration(&swap) == 61000, 3);
            assert!(!is_swap_expired(&swap, &test_clock), 4);

            clock::destroy_for_testing(test_clock);
            transfer::public_share_object(swap);
        };

        scenario.end();
    }

    #[test]
    fun test_two_way_swap_create() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::clock;

        let party_a = @0xAA;
        let party_b = @0xBB;
        let mut scenario = test_scenario::begin(party_a);

        {
            let mut test_clock = clock::create_for_testing(scenario.ctx());
            clock::set_for_testing(&mut test_clock, 1000);

            let swap = create_two_way_swap<SUI, SUI>(
                party_b,
                1000, // expected from A
                2000, // expected from B
                60000,
                &test_clock,
                scenario.ctx(),
            );

            let (a_deposited, b_deposited) = two_way_status(&swap);
            assert!(!a_deposited && !b_deposited, 0);

            clock::destroy_for_testing(test_clock);
            transfer::public_share_object(swap);
        };

        scenario.end();
    }
}
