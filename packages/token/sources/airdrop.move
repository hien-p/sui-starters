/// @title Token Airdrop
/// @notice Merkle-based and direct airdrop distribution
/// @dev Part of @sui-starters/token package
module sui_starters_token::airdrop {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::table::{Self, Table};
    use sui::clock::Clock;

    // === Errors ===

    /// Already claimed
    const EAlreadyClaimed: u64 = 0;

    /// Not eligible
    const ENotEligible: u64 = 1;

    /// Airdrop not started
    const EAirdropNotStarted: u64 = 2;

    /// Airdrop ended
    const EAirdropEnded: u64 = 3;

    /// Insufficient balance
    const EInsufficientBalance: u64 = 4;

    /// Invalid proof
    const EInvalidProof: u64 = 5;

    // === Structs ===

    /// Direct airdrop with whitelist
    public struct DirectAirdrop<phantom T> has key, store {
        id: UID,
        /// Token balance for distribution
        balance: Balance<T>,
        /// Amount per eligible address
        amount_per_address: u64,
        /// Claimed addresses
        claimed: Table<address, bool>,
        /// Eligible addresses
        eligible: Table<address, bool>,
        /// Total claimed
        total_claimed: u64,
        /// Total claims count
        claim_count: u64,
        /// Start time (0 = immediate)
        start_time: u64,
        /// End time (0 = no end)
        end_time: u64,
    }

    /// Merkle airdrop for large distributions
    public struct MerkleAirdrop<phantom T> has key, store {
        id: UID,
        /// Token balance
        balance: Balance<T>,
        /// Merkle root
        merkle_root: vector<u8>,
        /// Claimed leaf indices
        claimed: Table<u256, bool>,
        /// Total claimed amount
        total_claimed: u64,
        /// Total claims count
        claim_count: u64,
        /// Start time
        start_time: u64,
        /// End time
        end_time: u64,
    }

    /// Batch airdrop for direct transfers
    public struct BatchDistribution has copy, drop {
        recipient: address,
        amount: u64,
    }

    // === Events ===

    /// Emitted when airdrop is created
    public struct AirdropCreated has copy, drop {
        airdrop_id: ID,
        total_amount: u64,
        amount_per_address: u64,
    }

    /// Emitted when tokens are claimed
    public struct AirdropClaimed has copy, drop {
        airdrop_id: ID,
        claimer: address,
        amount: u64,
    }

    /// Emitted when airdrop is ended
    public struct AirdropEnded has copy, drop {
        airdrop_id: ID,
        remaining_amount: u64,
        total_claimed: u64,
    }

    /// Emitted for batch distribution
    public struct BatchDistributed has copy, drop {
        recipient_count: u64,
        total_amount: u64,
    }

    // === DirectAirdrop Functions ===

    /// Create new direct airdrop
    public fun new_direct<T>(
        tokens: Coin<T>,
        amount_per_address: u64,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext,
    ): DirectAirdrop<T> {
        let total_amount = coin::value(&tokens);

        let airdrop = DirectAirdrop<T> {
            id: object::new(ctx),
            balance: coin::into_balance(tokens),
            amount_per_address,
            claimed: table::new(ctx),
            eligible: table::new(ctx),
            total_claimed: 0,
            claim_count: 0,
            start_time,
            end_time,
        };

        event::emit(AirdropCreated {
            airdrop_id: object::id(&airdrop),
            total_amount,
            amount_per_address,
        });

        airdrop
    }

    /// Add eligible address
    public fun add_eligible<T>(airdrop: &mut DirectAirdrop<T>, addr: address) {
        if (!table::contains(&airdrop.eligible, addr)) {
            table::add(&mut airdrop.eligible, addr, true);
        };
    }

    /// Add multiple eligible addresses
    public fun add_eligible_batch<T>(airdrop: &mut DirectAirdrop<T>, addrs: vector<address>) {
        let len = vector::length(&addrs);
        let mut i = 0;
        while (i < len) {
            let addr = *vector::borrow(&addrs, i);
            add_eligible(airdrop, addr);
            i = i + 1;
        };
    }

    /// Check if address is eligible
    public fun is_eligible<T>(airdrop: &DirectAirdrop<T>, addr: address): bool {
        table::contains(&airdrop.eligible, addr)
    }

    /// Check if address has claimed
    public fun has_claimed<T>(airdrop: &DirectAirdrop<T>, addr: address): bool {
        table::contains(&airdrop.claimed, addr)
    }

    /// Check if airdrop is active
    public fun is_active<T>(airdrop: &DirectAirdrop<T>, clock: &Clock): bool {
        let now = sui::clock::timestamp_ms(clock);

        if (airdrop.start_time > 0 && now < airdrop.start_time) {
            return false
        };
        if (airdrop.end_time > 0 && now > airdrop.end_time) {
            return false
        };
        true
    }

    /// Claim airdrop
    public fun claim<T>(
        airdrop: &mut DirectAirdrop<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let sender = ctx.sender();
        let now = sui::clock::timestamp_ms(clock);

        // Check timing
        if (airdrop.start_time > 0) {
            assert!(now >= airdrop.start_time, EAirdropNotStarted);
        };
        if (airdrop.end_time > 0) {
            assert!(now <= airdrop.end_time, EAirdropEnded);
        };

        // Check eligibility
        assert!(is_eligible(airdrop, sender), ENotEligible);
        assert!(!has_claimed(airdrop, sender), EAlreadyClaimed);

        // Check balance
        assert!(balance::value(&airdrop.balance) >= airdrop.amount_per_address, EInsufficientBalance);

        // Mark claimed
        table::add(&mut airdrop.claimed, sender, true);
        airdrop.total_claimed = airdrop.total_claimed + airdrop.amount_per_address;
        airdrop.claim_count = airdrop.claim_count + 1;

        event::emit(AirdropClaimed {
            airdrop_id: object::id(airdrop),
            claimer: sender,
            amount: airdrop.amount_per_address,
        });

        coin::from_balance(balance::split(&mut airdrop.balance, airdrop.amount_per_address), ctx)
    }

    /// Get remaining balance
    public fun remaining_balance<T>(airdrop: &DirectAirdrop<T>): u64 {
        balance::value(&airdrop.balance)
    }

    /// Get total claimed
    public fun total_claimed<T>(airdrop: &DirectAirdrop<T>): u64 {
        airdrop.total_claimed
    }

    /// Get claim count
    public fun claim_count<T>(airdrop: &DirectAirdrop<T>): u64 {
        airdrop.claim_count
    }

    /// Get amount per address
    public fun amount_per_address<T>(airdrop: &DirectAirdrop<T>): u64 {
        airdrop.amount_per_address
    }

    /// Withdraw remaining tokens (admin)
    public fun withdraw_remaining<T>(
        airdrop: &mut DirectAirdrop<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        let remaining = balance::value(&airdrop.balance);

        event::emit(AirdropEnded {
            airdrop_id: object::id(airdrop),
            remaining_amount: remaining,
            total_claimed: airdrop.total_claimed,
        });

        coin::from_balance(balance::split(&mut airdrop.balance, remaining), ctx)
    }

    // === MerkleAirdrop Functions ===

    /// Create merkle airdrop
    public fun new_merkle<T>(
        tokens: Coin<T>,
        merkle_root: vector<u8>,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext,
    ): MerkleAirdrop<T> {
        MerkleAirdrop<T> {
            id: object::new(ctx),
            balance: coin::into_balance(tokens),
            merkle_root,
            claimed: table::new(ctx),
            total_claimed: 0,
            claim_count: 0,
            start_time,
            end_time,
        }
    }

    /// Claim from merkle airdrop
    /// Note: In production, you'd verify the merkle proof
    /// This is a simplified version for demonstration
    public fun claim_merkle<T>(
        airdrop: &mut MerkleAirdrop<T>,
        index: u256,
        amount: u64,
        _proof: vector<vector<u8>>,
        clock: &Clock,
        ctx: &mut TxContext,
    ): Coin<T> {
        let now = sui::clock::timestamp_ms(clock);

        // Check timing
        if (airdrop.start_time > 0) {
            assert!(now >= airdrop.start_time, EAirdropNotStarted);
        };
        if (airdrop.end_time > 0) {
            assert!(now <= airdrop.end_time, EAirdropEnded);
        };

        // Check not claimed
        assert!(!table::contains(&airdrop.claimed, index), EAlreadyClaimed);

        // TODO: Verify merkle proof
        // This would involve hashing (index, sender, amount) and verifying against root
        // For now, we trust the proof

        assert!(balance::value(&airdrop.balance) >= amount, EInsufficientBalance);

        // Mark claimed
        table::add(&mut airdrop.claimed, index, true);
        airdrop.total_claimed = airdrop.total_claimed + amount;
        airdrop.claim_count = airdrop.claim_count + 1;

        event::emit(AirdropClaimed {
            airdrop_id: object::id(airdrop),
            claimer: ctx.sender(),
            amount,
        });

        coin::from_balance(balance::split(&mut airdrop.balance, amount), ctx)
    }

    /// Check if index has claimed
    public fun merkle_has_claimed<T>(airdrop: &MerkleAirdrop<T>, index: u256): bool {
        table::contains(&airdrop.claimed, index)
    }

    /// Get merkle root
    public fun merkle_root<T>(airdrop: &MerkleAirdrop<T>): vector<u8> {
        airdrop.merkle_root
    }

    /// Get merkle remaining balance
    public fun merkle_remaining<T>(airdrop: &MerkleAirdrop<T>): u64 {
        balance::value(&airdrop.balance)
    }

    /// Get merkle total claimed
    public fun merkle_total_claimed<T>(airdrop: &MerkleAirdrop<T>): u64 {
        airdrop.total_claimed
    }

    // === Batch Distribution Functions ===

    /// Batch distribute tokens
    public fun batch_distribute<T>(
        tokens: &mut Coin<T>,
        distributions: vector<BatchDistribution>,
        ctx: &mut TxContext,
    ) {
        let len = vector::length(&distributions);
        let mut total_amount: u64 = 0;

        let mut i = 0;
        while (i < len) {
            let dist = vector::borrow(&distributions, i);
            assert!(coin::value(tokens) >= dist.amount, EInsufficientBalance);

            let payment = coin::split(tokens, dist.amount, ctx);
            transfer::public_transfer(payment, dist.recipient);
            total_amount = total_amount + dist.amount;

            i = i + 1;
        };

        event::emit(BatchDistributed {
            recipient_count: len,
            total_amount,
        });
    }

    /// Create batch distribution entry
    public fun create_distribution(recipient: address, amount: u64): BatchDistribution {
        BatchDistribution { recipient, amount }
    }

    /// Simple batch airdrop (equal amounts)
    public fun simple_batch<T>(
        tokens: &mut Coin<T>,
        recipients: vector<address>,
        amount_each: u64,
        ctx: &mut TxContext,
    ) {
        let len = vector::length(&recipients);
        let total_needed = len * amount_each;
        assert!(coin::value(tokens) >= total_needed, EInsufficientBalance);

        let mut i = 0;
        while (i < len) {
            let recipient = *vector::borrow(&recipients, i);
            let payment = coin::split(tokens, amount_each, ctx);
            transfer::public_transfer(payment, recipient);
            i = i + 1;
        };

        event::emit(BatchDistributed {
            recipient_count: len,
            total_amount: total_needed,
        });
    }

    // === Tests ===

    #[test]
    fun test_direct_airdrop() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        use sui::clock;

        let admin = @0xAD;
        let user1 = @0x1;
        let user2 = @0x2;
        let mut scenario = test_scenario::begin(admin);

        // Create airdrop
        {
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            let mut airdrop = new_direct(tokens, 100, 0, 0, scenario.ctx());

            // Add eligible addresses
            add_eligible(&mut airdrop, user1);
            add_eligible(&mut airdrop, user2);

            assert!(is_eligible(&airdrop, user1), 0);
            assert!(is_eligible(&airdrop, user2), 1);
            assert!(!has_claimed(&airdrop, user1), 2);

            transfer::public_share_object(airdrop);
        };

        // User1 claims
        scenario.next_tx(user1);
        {
            let mut airdrop = scenario.take_shared<DirectAirdrop<SUI>>();
            let test_clock = clock::create_for_testing(scenario.ctx());

            let tokens = claim(&mut airdrop, &test_clock, scenario.ctx());
            assert!(coin::value(&tokens) == 100, 3);
            assert!(has_claimed(&airdrop, user1), 4);
            assert!(claim_count(&airdrop) == 1, 5);

            transfer::public_transfer(tokens, user1);
            clock::destroy_for_testing(test_clock);
            test_scenario::return_shared(airdrop);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EAlreadyClaimed)]
    fun test_double_claim() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        use sui::clock;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            let mut airdrop = new_direct(tokens, 100, 0, 0, scenario.ctx());
            add_eligible(&mut airdrop, user);
            transfer::public_share_object(airdrop);
        };

        // First claim
        scenario.next_tx(user);
        {
            let mut airdrop = scenario.take_shared<DirectAirdrop<SUI>>();
            let test_clock = clock::create_for_testing(scenario.ctx());
            let tokens = claim(&mut airdrop, &test_clock, scenario.ctx());
            transfer::public_transfer(tokens, user);
            clock::destroy_for_testing(test_clock);
            test_scenario::return_shared(airdrop);
        };

        // Second claim - should fail
        scenario.next_tx(user);
        {
            let mut airdrop = scenario.take_shared<DirectAirdrop<SUI>>();
            let test_clock = clock::create_for_testing(scenario.ctx());
            let tokens = claim(&mut airdrop, &test_clock, scenario.ctx()); // Should fail
            transfer::public_transfer(tokens, user);
            clock::destroy_for_testing(test_clock);
            test_scenario::return_shared(airdrop);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ENotEligible)]
    fun test_not_eligible() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;
        use sui::clock;

        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            let airdrop = new_direct(tokens, 100, 0, 0, scenario.ctx());
            // Not adding user to eligible list
            transfer::public_share_object(airdrop);
        };

        scenario.next_tx(user);
        {
            let mut airdrop = scenario.take_shared<DirectAirdrop<SUI>>();
            let test_clock = clock::create_for_testing(scenario.ctx());
            let tokens = claim(&mut airdrop, &test_clock, scenario.ctx()); // Should fail
            transfer::public_transfer(tokens, user);
            clock::destroy_for_testing(test_clock);
            test_scenario::return_shared(airdrop);
        };

        scenario.end();
    }

    #[test]
    fun test_batch_eligible() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            let mut airdrop = new_direct(tokens, 100, 0, 0, scenario.ctx());

            let addrs = vector[@0x1, @0x2, @0x3, @0x4, @0x5];
            add_eligible_batch(&mut airdrop, addrs);

            assert!(is_eligible(&airdrop, @0x1), 0);
            assert!(is_eligible(&airdrop, @0x3), 1);
            assert!(is_eligible(&airdrop, @0x5), 2);
            assert!(!is_eligible(&airdrop, @0x6), 3);

            transfer::public_share_object(airdrop);
        };

        scenario.end();
    }

    #[test]
    fun test_create_distribution() {
        let dist = create_distribution(@0x1, 100);
        assert!(dist.recipient == @0x1, 0);
        assert!(dist.amount == 100, 1);
    }

    #[test]
    fun test_merkle_airdrop_basic() {
        use sui::test_scenario;
        use sui::coin;
        use sui::sui::SUI;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            let root = vector[1, 2, 3, 4]; // Dummy merkle root

            let airdrop = new_merkle(tokens, root, 0, 0, scenario.ctx());

            assert!(merkle_root(&airdrop) == vector[1, 2, 3, 4], 0);
            assert!(merkle_remaining(&airdrop) == 10000, 1);
            assert!(!merkle_has_claimed(&airdrop, 0), 2);

            transfer::public_share_object(airdrop);
        };

        scenario.end();
    }
}
