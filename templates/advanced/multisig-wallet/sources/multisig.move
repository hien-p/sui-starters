/// @title Multisig Wallet
/// @notice Multi-signature wallet requiring N-of-M approvals
/// @dev Demonstrates threshold signatures and proposal patterns
module multisig_wallet::multisig {
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::vec_set::{Self, VecSet};
    use sui::table::{Self, Table};

    // === Errors ===

    const ENotOwner: u64 = 0;
    const EAlreadySigned: u64 = 1;
    const EThresholdNotMet: u64 = 2;
    const EProposalExpired: u64 = 3;
    const EProposalNotFound: u64 = 4;
    const EInvalidThreshold: u64 = 5;
    const EInsufficientBalance: u64 = 6;
    const EProposalAlreadyExecuted: u64 = 7;

    // === Structs ===

    /// Multi-signature wallet
    public struct MultisigWallet<phantom T> has key {
        id: UID,
        /// Wallet owners
        owners: VecSet<address>,
        /// Required signatures threshold
        threshold: u64,
        /// Wallet balance
        balance: Balance<T>,
        /// Proposal counter
        proposal_count: u64,
        /// Active proposals
        proposals: Table<u64, Proposal>,
    }

    /// Transfer proposal
    public struct Proposal has store {
        /// Proposal ID
        id: u64,
        /// Recipient address
        recipient: address,
        /// Amount to transfer
        amount: u64,
        /// Description
        description: vector<u8>,
        /// Signers who approved
        signers: VecSet<address>,
        /// Proposal creator
        creator: address,
        /// Is executed
        executed: bool,
        /// Expiration epoch
        expires_at: u64,
    }

    // === Events ===

    public struct WalletCreated has copy, drop {
        wallet_id: ID,
        owners: vector<address>,
        threshold: u64,
    }

    public struct ProposalCreated has copy, drop {
        wallet_id: ID,
        proposal_id: u64,
        recipient: address,
        amount: u64,
        creator: address,
    }

    public struct ProposalSigned has copy, drop {
        wallet_id: ID,
        proposal_id: u64,
        signer: address,
        signatures: u64,
        threshold: u64,
    }

    public struct ProposalExecuted has copy, drop {
        wallet_id: ID,
        proposal_id: u64,
        recipient: address,
        amount: u64,
    }

    public struct DepositMade has copy, drop {
        wallet_id: ID,
        depositor: address,
        amount: u64,
    }

    // === Entry Functions ===

    /// Create a new multisig wallet
    public entry fun create<T>(
        owners: vector<address>,
        threshold: u64,
        ctx: &mut TxContext,
    ) {
        let owner_count = vector::length(&owners);
        assert!(threshold > 0 && threshold <= owner_count, EInvalidThreshold);

        let mut owner_set = vec_set::empty();
        let mut i = 0;
        while (i < owner_count) {
            vec_set::insert(&mut owner_set, *vector::borrow(&owners, i));
            i = i + 1;
        };

        let wallet = MultisigWallet<T> {
            id: object::new(ctx),
            owners: owner_set,
            threshold,
            balance: balance::zero(),
            proposal_count: 0,
            proposals: table::new(ctx),
        };

        event::emit(WalletCreated {
            wallet_id: object::id(&wallet),
            owners,
            threshold,
        });

        transfer::share_object(wallet);
    }

    /// Deposit tokens
    public entry fun deposit<T>(
        wallet: &mut MultisigWallet<T>,
        tokens: Coin<T>,
        ctx: &TxContext,
    ) {
        let amount = coin::value(&tokens);

        balance::join(&mut wallet.balance, coin::into_balance(tokens));

        event::emit(DepositMade {
            wallet_id: object::id(wallet),
            depositor: ctx.sender(),
            amount,
        });
    }

    /// Create a transfer proposal
    public entry fun propose<T>(
        wallet: &mut MultisigWallet<T>,
        recipient: address,
        amount: u64,
        description: vector<u8>,
        expires_in_epochs: u64,
        ctx: &mut TxContext,
    ) {
        let sender = ctx.sender();
        assert!(vec_set::contains(&wallet.owners, &sender), ENotOwner);
        assert!(balance::value(&wallet.balance) >= amount, EInsufficientBalance);

        wallet.proposal_count = wallet.proposal_count + 1;
        let proposal_id = wallet.proposal_count;

        let mut signers = vec_set::empty();
        vec_set::insert(&mut signers, sender); // Creator auto-signs

        let proposal = Proposal {
            id: proposal_id,
            recipient,
            amount,
            description,
            signers,
            creator: sender,
            executed: false,
            expires_at: ctx.epoch() + expires_in_epochs,
        };

        table::add(&mut wallet.proposals, proposal_id, proposal);

        event::emit(ProposalCreated {
            wallet_id: object::id(wallet),
            proposal_id,
            recipient,
            amount,
            creator: sender,
        });

        event::emit(ProposalSigned {
            wallet_id: object::id(wallet),
            proposal_id,
            signer: sender,
            signatures: 1,
            threshold: wallet.threshold,
        });
    }

    /// Sign a proposal
    public entry fun sign<T>(
        wallet: &mut MultisigWallet<T>,
        proposal_id: u64,
        ctx: &TxContext,
    ) {
        let sender = ctx.sender();
        assert!(vec_set::contains(&wallet.owners, &sender), ENotOwner);
        assert!(table::contains(&wallet.proposals, proposal_id), EProposalNotFound);

        let proposal = table::borrow_mut(&mut wallet.proposals, proposal_id);

        assert!(!proposal.executed, EProposalAlreadyExecuted);
        assert!(ctx.epoch() < proposal.expires_at, EProposalExpired);
        assert!(!vec_set::contains(&proposal.signers, &sender), EAlreadySigned);

        vec_set::insert(&mut proposal.signers, sender);

        event::emit(ProposalSigned {
            wallet_id: object::id(wallet),
            proposal_id,
            signer: sender,
            signatures: vec_set::size(&proposal.signers),
            threshold: wallet.threshold,
        });
    }

    /// Execute a proposal if threshold met
    public entry fun execute<T>(
        wallet: &mut MultisigWallet<T>,
        proposal_id: u64,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&wallet.proposals, proposal_id), EProposalNotFound);

        let proposal = table::borrow_mut(&mut wallet.proposals, proposal_id);

        assert!(!proposal.executed, EProposalAlreadyExecuted);
        assert!(ctx.epoch() < proposal.expires_at, EProposalExpired);
        assert!(vec_set::size(&proposal.signers) >= wallet.threshold, EThresholdNotMet);

        let amount = proposal.amount;
        let recipient = proposal.recipient;

        proposal.executed = true;

        // Transfer tokens
        let transfer_balance = balance::split(&mut wallet.balance, amount);
        let transfer_coin = coin::from_balance(transfer_balance, ctx);

        event::emit(ProposalExecuted {
            wallet_id: object::id(wallet),
            proposal_id,
            recipient,
            amount,
        });

        transfer::public_transfer(transfer_coin, recipient);
    }

    // === View Functions ===

    /// Get wallet balance
    public fun wallet_balance<T>(wallet: &MultisigWallet<T>): u64 {
        balance::value(&wallet.balance)
    }

    /// Get threshold
    public fun threshold<T>(wallet: &MultisigWallet<T>): u64 {
        wallet.threshold
    }

    /// Get owner count
    public fun owner_count<T>(wallet: &MultisigWallet<T>): u64 {
        vec_set::size(&wallet.owners)
    }

    /// Is owner
    public fun is_owner<T>(wallet: &MultisigWallet<T>, addr: address): bool {
        vec_set::contains(&wallet.owners, &addr)
    }

    /// Get proposal count
    public fun proposal_count<T>(wallet: &MultisigWallet<T>): u64 {
        wallet.proposal_count
    }

    /// Get proposal info
    public fun proposal_info<T>(wallet: &MultisigWallet<T>, proposal_id: u64): (address, u64, u64, bool) {
        let proposal = table::borrow(&wallet.proposals, proposal_id);
        (
            proposal.recipient,
            proposal.amount,
            vec_set::size(&proposal.signers),
            proposal.executed,
        )
    }

    /// Has signed
    public fun has_signed<T>(wallet: &MultisigWallet<T>, proposal_id: u64, signer: address): bool {
        let proposal = table::borrow(&wallet.proposals, proposal_id);
        vec_set::contains(&proposal.signers, &signer)
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::sui::SUI;

    #[test]
    fun test_create_wallet() {
        let owner1 = @0x1;
        let owner2 = @0x2;
        let owner3 = @0x3;
        let mut scenario = test_scenario::begin(owner1);

        {
            let owners = vector[owner1, owner2, owner3];
            create<SUI>(owners, 2, scenario.ctx());
        };

        scenario.next_tx(owner1);
        {
            let wallet = scenario.take_shared<MultisigWallet<SUI>>();

            assert!(threshold(&wallet) == 2, 0);
            assert!(owner_count(&wallet) == 3, 1);
            assert!(is_owner(&wallet, owner1), 2);
            assert!(is_owner(&wallet, owner2), 3);

            test_scenario::return_shared(wallet);
        };

        scenario.end();
    }

    #[test]
    fun test_propose_and_execute() {
        let owner1 = @0x1;
        let owner2 = @0x2;
        let recipient = @0x99;
        let mut scenario = test_scenario::begin(owner1);

        // Create wallet
        {
            let owners = vector[owner1, owner2];
            create<SUI>(owners, 2, scenario.ctx());
        };

        // Deposit
        scenario.next_tx(owner1);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            let tokens = coin::mint_for_testing<SUI>(10000, scenario.ctx());
            deposit(&mut wallet, tokens, scenario.ctx());
            assert!(wallet_balance(&wallet) == 10000, 0);
            test_scenario::return_shared(wallet);
        };

        // Create proposal
        scenario.next_tx(owner1);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            propose(
                &mut wallet,
                recipient,
                5000,
                b"Payment",
                100,
                scenario.ctx(),
            );
            assert!(proposal_count(&wallet) == 1, 1);
            test_scenario::return_shared(wallet);
        };

        // Owner2 signs
        scenario.next_tx(owner2);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            sign(&mut wallet, 1, scenario.ctx());

            let (_, _, sigs, _) = proposal_info(&wallet, 1);
            assert!(sigs == 2, 2);

            test_scenario::return_shared(wallet);
        };

        // Execute
        scenario.next_tx(owner1);
        {
            let mut wallet = scenario.take_shared<MultisigWallet<SUI>>();
            execute(&mut wallet, 1, scenario.ctx());

            assert!(wallet_balance(&wallet) == 5000, 3);

            let (_, _, _, executed) = proposal_info(&wallet, 1);
            assert!(executed, 4);

            test_scenario::return_shared(wallet);
        };

        scenario.end();
    }
}
