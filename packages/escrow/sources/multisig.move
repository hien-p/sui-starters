/// @title Multisig Escrow
/// @notice Multi-signature escrow requiring multiple approvals
/// @dev Part of @sui-starters/escrow package
module sui_starters_escrow::multisig {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::vec_set::{Self, VecSet};

    // === Errors ===

    /// Not a signer
    const ENotSigner: u64 = 0;

    /// Already signed
    const EAlreadySigned: u64 = 1;

    /// Not enough signatures
    const ENotEnoughSignatures: u64 = 2;

    /// Invalid threshold
    const EInvalidThreshold: u64 = 3;

    /// Already executed
    const EAlreadyExecuted: u64 = 4;

    /// Invalid amount
    const EInvalidAmount: u64 = 5;

    /// Invalid signers
    const EInvalidSigners: u64 = 6;

    /// Proposal expired
    const EProposalExpired: u64 = 7;

    // === Structs ===

    /// Multisig wallet
    public struct MultisigWallet<phantom T> has key, store {
        id: UID,
        /// List of signers
        signers: vector<address>,
        /// Required signatures threshold
        threshold: u64,
        /// Wallet balance
        balance: Balance<T>,
        /// Proposal counter
        proposal_count: u64,
    }

    /// Withdrawal proposal
    public struct Proposal<phantom T> has key, store {
        id: UID,
        /// Associated wallet ID
        wallet_id: ID,
        /// Proposal index
        index: u64,
        /// Recipient address
        recipient: address,
        /// Amount to withdraw
        amount: u64,
        /// Addresses that have signed
        signatures: VecSet<address>,
        /// Has been executed
        executed: bool,
        /// Creation timestamp
        created_at: u64,
        /// Expiration timestamp (0 = no expiry)
        expires_at: u64,
        /// Description
        description: vector<u8>,
    }

    /// Signer capability for a wallet
    public struct SignerCap has key, store {
        id: UID,
        /// Wallet ID this cap is for
        wallet_id: ID,
        /// Signer address
        signer: address,
    }

    // === Events ===

    /// Emitted when wallet is created
    public struct WalletCreated has copy, drop {
        wallet_id: ID,
        signers: vector<address>,
        threshold: u64,
    }

    /// Emitted when deposit is made
    public struct Deposited has copy, drop {
        wallet_id: ID,
        depositor: address,
        amount: u64,
    }

    /// Emitted when proposal is created
    public struct ProposalCreated has copy, drop {
        proposal_id: ID,
        wallet_id: ID,
        recipient: address,
        amount: u64,
        creator: address,
    }

    /// Emitted when proposal is signed
    public struct ProposalSigned has copy, drop {
        proposal_id: ID,
        signer: address,
        signature_count: u64,
        threshold: u64,
    }

    /// Emitted when proposal is executed
    public struct ProposalExecuted has copy, drop {
        proposal_id: ID,
        recipient: address,
        amount: u64,
    }

    // === Wallet Functions ===

    /// Create a new multisig wallet
    public fun create_wallet<T>(
        signers: vector<address>,
        threshold: u64,
        ctx: &mut TxContext,
    ): (MultisigWallet<T>, vector<SignerCap>) {
        let signer_count = vector::length(&signers);
        assert!(signer_count > 0, EInvalidSigners);
        assert!(threshold > 0 && threshold <= signer_count, EInvalidThreshold);

        let wallet = MultisigWallet<T> {
            id: object::new(ctx),
            signers: copy signers,
            threshold,
            balance: balance::zero(),
            proposal_count: 0,
        };

        let wallet_id = object::id(&wallet);

        // Create signer capabilities
        let mut caps = vector[];
        let mut i = 0;
        while (i < signer_count) {
            let signer = *vector::borrow(&signers, i);
            let cap = SignerCap {
                id: object::new(ctx),
                wallet_id,
                signer,
            };
            vector::push_back(&mut caps, cap);
            i = i + 1;
        };

        event::emit(WalletCreated {
            wallet_id,
            signers,
            threshold,
        });

        (wallet, caps)
    }

    /// Deposit tokens into wallet
    public fun deposit<T>(
        wallet: &mut MultisigWallet<T>,
        tokens: Coin<T>,
        ctx: &TxContext,
    ) {
        let amount = coin::value(&tokens);
        assert!(amount > 0, EInvalidAmount);

        balance::join(&mut wallet.balance, coin::into_balance(tokens));

        event::emit(Deposited {
            wallet_id: object::id(wallet),
            depositor: ctx.sender(),
            amount,
        });
    }

    // === Proposal Functions ===

    /// Create a withdrawal proposal
    public fun create_proposal<T>(
        wallet: &mut MultisigWallet<T>,
        cap: &SignerCap,
        recipient: address,
        amount: u64,
        description: vector<u8>,
        expires_at: u64,
        created_at: u64,
        ctx: &mut TxContext,
    ): Proposal<T> {
        assert!(cap.wallet_id == object::id(wallet), ENotSigner);
        assert!(amount > 0, EInvalidAmount);

        let index = wallet.proposal_count;
        wallet.proposal_count = index + 1;

        let mut signatures = vec_set::empty();
        vec_set::insert(&mut signatures, cap.signer);

        let proposal = Proposal<T> {
            id: object::new(ctx),
            wallet_id: object::id(wallet),
            index,
            recipient,
            amount,
            signatures,
            executed: false,
            created_at,
            expires_at,
            description,
        };

        event::emit(ProposalCreated {
            proposal_id: object::id(&proposal),
            wallet_id: object::id(wallet),
            recipient,
            amount,
            creator: cap.signer,
        });

        event::emit(ProposalSigned {
            proposal_id: object::id(&proposal),
            signer: cap.signer,
            signature_count: 1,
            threshold: wallet.threshold,
        });

        proposal
    }

    /// Sign a proposal
    public fun sign_proposal<T>(
        wallet: &MultisigWallet<T>,
        proposal: &mut Proposal<T>,
        cap: &SignerCap,
        current_time: u64,
    ) {
        assert!(cap.wallet_id == object::id(wallet), ENotSigner);
        assert!(proposal.wallet_id == object::id(wallet), ENotSigner);
        assert!(!proposal.executed, EAlreadyExecuted);
        assert!(!vec_set::contains(&proposal.signatures, &cap.signer), EAlreadySigned);

        if (proposal.expires_at > 0) {
            assert!(current_time < proposal.expires_at, EProposalExpired);
        };

        vec_set::insert(&mut proposal.signatures, cap.signer);

        event::emit(ProposalSigned {
            proposal_id: object::id(proposal),
            signer: cap.signer,
            signature_count: vec_set::length(&proposal.signatures),
            threshold: wallet.threshold,
        });
    }

    /// Execute a proposal if it has enough signatures
    public fun execute_proposal<T>(
        wallet: &mut MultisigWallet<T>,
        proposal: Proposal<T>,
        current_time: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        assert!(proposal.wallet_id == object::id(wallet), ENotSigner);
        assert!(!proposal.executed, EAlreadyExecuted);
        assert!(
            vec_set::length(&proposal.signatures) >= wallet.threshold,
            ENotEnoughSignatures,
        );

        if (proposal.expires_at > 0) {
            assert!(current_time < proposal.expires_at, EProposalExpired);
        };

        assert!(balance::value(&wallet.balance) >= proposal.amount, EInvalidAmount);

        let Proposal {
            id,
            wallet_id: _,
            index: _,
            recipient,
            amount,
            signatures: _,
            executed: _,
            created_at: _,
            expires_at: _,
            description: _,
        } = proposal;

        let proposal_id = object::uid_to_inner(&id);
        object::delete(id);

        event::emit(ProposalExecuted {
            proposal_id,
            recipient,
            amount,
        });

        coin::from_balance(
            balance::split(&mut wallet.balance, amount),
            ctx,
        )
    }

    /// Cancel a proposal (any signer can cancel)
    public fun cancel_proposal<T>(
        wallet: &MultisigWallet<T>,
        proposal: Proposal<T>,
        cap: &SignerCap,
    ) {
        assert!(cap.wallet_id == object::id(wallet), ENotSigner);
        assert!(proposal.wallet_id == object::id(wallet), ENotSigner);
        assert!(!proposal.executed, EAlreadyExecuted);

        let Proposal {
            id,
            wallet_id: _,
            index: _,
            recipient: _,
            amount: _,
            signatures: _,
            executed: _,
            created_at: _,
            expires_at: _,
            description: _,
        } = proposal;

        object::delete(id);
    }

    // === View Functions ===

    /// Get wallet signers
    public fun signers<T>(wallet: &MultisigWallet<T>): vector<address> {
        wallet.signers
    }

    /// Get wallet threshold
    public fun threshold<T>(wallet: &MultisigWallet<T>): u64 {
        wallet.threshold
    }

    /// Get wallet balance
    public fun wallet_balance<T>(wallet: &MultisigWallet<T>): u64 {
        balance::value(&wallet.balance)
    }

    /// Get proposal count
    public fun proposal_count<T>(wallet: &MultisigWallet<T>): u64 {
        wallet.proposal_count
    }

    /// Check if address is a signer
    public fun is_signer<T>(wallet: &MultisigWallet<T>, addr: address): bool {
        let mut i = 0;
        while (i < vector::length(&wallet.signers)) {
            if (*vector::borrow(&wallet.signers, i) == addr) {
                return true
            };
            i = i + 1;
        };
        false
    }

    /// Get proposal info
    public fun proposal_info<T>(proposal: &Proposal<T>): (address, u64, u64, bool) {
        (
            proposal.recipient,
            proposal.amount,
            vec_set::length(&proposal.signatures),
            proposal.executed,
        )
    }

    /// Check if proposal can be executed
    public fun can_execute<T>(wallet: &MultisigWallet<T>, proposal: &Proposal<T>): bool {
        !proposal.executed &&
        vec_set::length(&proposal.signatures) >= wallet.threshold &&
        balance::value(&wallet.balance) >= proposal.amount
    }

    /// Get signature count
    public fun signature_count<T>(proposal: &Proposal<T>): u64 {
        vec_set::length(&proposal.signatures)
    }

    /// Check if address has signed
    public fun has_signed<T>(proposal: &Proposal<T>, addr: address): bool {
        vec_set::contains(&proposal.signatures, &addr)
    }

    /// Get signer cap wallet ID
    public fun cap_wallet_id(cap: &SignerCap): ID {
        cap.wallet_id
    }

    /// Get signer cap signer address
    public fun cap_signer(cap: &SignerCap): address {
        cap.signer
    }

    // === Tests ===

    #[test]
    fun test_create_wallet() {
        use sui::test_scenario;
        use sui::sui::SUI;

        let admin = @0xAD;
        let signer1 = @0xA1;
        let signer2 = @0xA2;
        let mut scenario = test_scenario::begin(admin);

        {
            let signers = vector[signer1, signer2];
            let (wallet, mut caps) = create_wallet<SUI>(signers, 2, scenario.ctx());

            assert!(threshold(&wallet) == 2, 0);
            assert!(vector::length(&signers(&wallet)) == 2, 1);
            assert!(is_signer(&wallet, signer1), 2);
            assert!(is_signer(&wallet, signer2), 3);
            assert!(!is_signer(&wallet, admin), 4);
            assert!(wallet_balance(&wallet) == 0, 5);
            assert!(vector::length(&caps) == 2, 6);

            transfer::public_share_object(wallet);

            // Transfer caps to signers (pop_back gets last element first)
            let cap2 = vector::pop_back(&mut caps);
            let cap1 = vector::pop_back(&mut caps);
            vector::destroy_empty(caps);

            transfer::public_transfer(cap1, signer1);
            transfer::public_transfer(cap2, signer2);
        };

        scenario.end();
    }

    #[test]
    fun test_deposit() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;

        let admin = @0xAD;
        let signer1 = @0xA1;
        let signer2 = @0xA2;
        let mut scenario = test_scenario::begin(admin);

        {
            let signers = vector[signer1, signer2];
            let (wallet, mut caps) = create_wallet<SUI>(signers, 2, scenario.ctx());
            transfer::public_share_object(wallet);

            let cap2 = vector::pop_back(&mut caps);
            let cap1 = vector::pop_back(&mut caps);
            vector::destroy_empty(caps);
            transfer::public_transfer(cap1, signer1);
            transfer::public_transfer(cap2, signer2);
        };

        scenario.next_tx(admin);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();

            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            deposit(&mut wallet, tokens, scenario.ctx());

            assert!(wallet_balance(&wallet) == 1000, 0);

            test_scenario::return_shared(wallet);
        };

        scenario.end();
    }

    #[test]
    fun test_create_and_sign_proposal() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;

        let admin = @0xAD;
        let signer1 = @0xA1;
        let signer2 = @0xA2;
        let recipient = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        // Create wallet
        {
            let signers = vector[signer1, signer2];
            let (wallet, mut caps) = create_wallet<SUI>(signers, 2, scenario.ctx());
            transfer::public_share_object(wallet);

            // caps are in order [signer1_cap, signer2_cap], pop_back gets last first
            let cap2 = vector::pop_back(&mut caps); // signer2's cap
            let cap1 = vector::pop_back(&mut caps); // signer1's cap
            vector::destroy_empty(caps);
            transfer::public_transfer(cap1, signer1);
            transfer::public_transfer(cap2, signer2);
        };

        // Deposit
        scenario.next_tx(admin);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            deposit(&mut wallet, tokens, scenario.ctx());
            test_scenario::return_shared(wallet);
        };

        // Create proposal (signer1)
        scenario.next_tx(signer1);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            let cap = scenario.take_from_sender<SignerCap>();

            let proposal = create_proposal(
                &mut wallet,
                &cap,
                recipient,
                500,
                b"Test withdrawal",
                0, // No expiry
                1000,
                scenario.ctx(),
            );

            assert!(signature_count(&proposal) == 1, 0);
            assert!(has_signed(&proposal, signer1), 1);
            assert!(!can_execute(&wallet, &proposal), 2);

            transfer::public_share_object(proposal);
            transfer::public_transfer(cap, signer1);
            test_scenario::return_shared(wallet);
        };

        // Sign proposal (signer2)
        scenario.next_tx(signer2);
        {
            let wallet = scenario.take_shared<MultisigWallet<SUI>>();
            let mut proposal = scenario.take_shared<Proposal<SUI>>();
            let cap = scenario.take_from_sender<SignerCap>();

            sign_proposal(&wallet, &mut proposal, &cap, 2000);

            assert!(signature_count(&proposal) == 2, 3);
            assert!(has_signed(&proposal, signer2), 4);
            assert!(can_execute(&wallet, &proposal), 5);

            transfer::public_transfer(cap, signer2);
            test_scenario::return_shared(proposal);
            test_scenario::return_shared(wallet);
        };

        // Execute proposal
        scenario.next_tx(signer1);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            let proposal = scenario.take_shared<Proposal<SUI>>();

            let withdrawn = execute_proposal(&mut wallet, proposal, 3000, scenario.ctx());

            assert!(coin::value(&withdrawn) == 500, 6);
            assert!(wallet_balance(&wallet) == 500, 7);

            transfer::public_transfer(withdrawn, recipient);
            test_scenario::return_shared(wallet);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ENotEnoughSignatures)]
    fun test_execute_without_enough_signatures_fails() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;

        let admin = @0xAD;
        let signer1 = @0xA1;
        let signer2 = @0xA2;
        let recipient = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        {
            let signers = vector[signer1, signer2];
            let (wallet, mut caps) = create_wallet<SUI>(signers, 2, scenario.ctx());
            transfer::public_share_object(wallet);

            let cap2 = vector::pop_back(&mut caps);
            let cap1 = vector::pop_back(&mut caps);
            vector::destroy_empty(caps);
            transfer::public_transfer(cap1, signer1);
            transfer::public_transfer(cap2, signer2);
        };

        scenario.next_tx(admin);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            deposit(&mut wallet, tokens, scenario.ctx());
            test_scenario::return_shared(wallet);
        };

        scenario.next_tx(signer1);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            let cap = scenario.take_from_sender<SignerCap>();

            let proposal = create_proposal(
                &mut wallet,
                &cap,
                recipient,
                500,
                b"Test",
                0,
                1000,
                scenario.ctx(),
            );

            // Try to execute with only 1 signature (need 2) - should fail
            let withdrawn = execute_proposal(&mut wallet, proposal, 2000, scenario.ctx());

            transfer::public_transfer(withdrawn, recipient);
            transfer::public_transfer(cap, signer1);
            test_scenario::return_shared(wallet);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EAlreadySigned)]
    fun test_double_sign_fails() {
        use sui::test_scenario;
        use sui::sui::SUI;
        use sui::coin;

        let admin = @0xAD;
        let signer1 = @0xA1;
        let signer2 = @0xA2;
        let recipient = @0xBB;
        let mut scenario = test_scenario::begin(admin);

        {
            let signers = vector[signer1, signer2];
            let (wallet, mut caps) = create_wallet<SUI>(signers, 2, scenario.ctx());
            transfer::public_share_object(wallet);

            let cap2 = vector::pop_back(&mut caps);
            let cap1 = vector::pop_back(&mut caps);
            vector::destroy_empty(caps);
            transfer::public_transfer(cap1, signer1);
            transfer::public_transfer(cap2, signer2);
        };

        scenario.next_tx(admin);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(1000, scenario.ctx());
            deposit(&mut wallet, tokens, scenario.ctx());
            test_scenario::return_shared(wallet);
        };

        scenario.next_tx(signer1);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            let cap = scenario.take_from_sender<SignerCap>();

            let mut proposal = create_proposal(
                &mut wallet,
                &cap,
                recipient,
                500,
                b"Test",
                0,
                1000,
                scenario.ctx(),
            );

            // Try to sign again - should fail
            sign_proposal(&wallet, &mut proposal, &cap, 2000);

            transfer::public_share_object(proposal);
            transfer::public_transfer(cap, signer1);
            test_scenario::return_shared(wallet);
        };

        scenario.end();
    }
}
