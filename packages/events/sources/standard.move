/// @title Standard Events
/// @notice Standardized event structs for indexing and analytics
/// @dev Part of @sui-starters/events package
module sui_starters_events::standard {
    use std::string::String;
    use std::type_name::TypeName;
    use sui::event;

    // === Transfer Events ===

    /// Standard transfer event for any object
    public struct TransferEvent has copy, drop {
        /// Sender address
        from: address,
        /// Recipient address
        to: address,
        /// Object ID being transferred
        object_id: ID,
        /// Type of the object
        object_type: TypeName,
        /// Timestamp in milliseconds
        timestamp: u64,
    }

    /// Batch transfer event
    public struct BatchTransferEvent has copy, drop {
        from: address,
        to: address,
        object_ids: vector<ID>,
        object_type: TypeName,
        count: u64,
        timestamp: u64,
    }

    // === Mint/Burn Events ===

    /// Mint event for NFTs or tokens
    public struct MintEvent has copy, drop {
        /// Minter address
        minter: address,
        /// Recipient address
        recipient: address,
        /// Minted object ID
        object_id: ID,
        /// Type of the object
        object_type: TypeName,
        /// Amount (for fungible, 1 for NFT)
        amount: Option<u64>,
        /// Timestamp
        timestamp: u64,
    }

    /// Burn event for NFTs or tokens
    public struct BurnEvent has copy, drop {
        /// Burner address
        burner: address,
        /// Burned object ID
        object_id: ID,
        /// Type of the object
        object_type: TypeName,
        /// Amount (for fungible, 1 for NFT)
        amount: Option<u64>,
        /// Timestamp
        timestamp: u64,
    }

    /// Batch mint event
    public struct BatchMintEvent has copy, drop {
        minter: address,
        recipient: address,
        object_ids: vector<ID>,
        object_type: TypeName,
        count: u64,
        timestamp: u64,
    }

    // === Trade Events ===

    /// Trade/Sale event
    public struct TradeEvent has copy, drop {
        /// Buyer address
        buyer: address,
        /// Seller address
        seller: address,
        /// Item being traded
        item_id: ID,
        /// Item type
        item_type: TypeName,
        /// Price paid
        price: u64,
        /// Fee amount
        fee: u64,
        /// Royalty amount
        royalty: u64,
        /// Payment token type
        payment_type: TypeName,
        /// Timestamp
        timestamp: u64,
    }

    /// Listing event (item listed for sale)
    public struct ListingEvent has copy, drop {
        seller: address,
        item_id: ID,
        item_type: TypeName,
        price: u64,
        payment_type: TypeName,
        expiration: Option<u64>,
        timestamp: u64,
    }

    /// Delisting event
    public struct DelistingEvent has copy, drop {
        seller: address,
        item_id: ID,
        item_type: TypeName,
        timestamp: u64,
    }

    // === Swap Events ===

    /// Token swap event (for DEX)
    public struct SwapEvent has copy, drop {
        /// Swapper address
        swapper: address,
        /// Pool ID
        pool_id: ID,
        /// Token in type
        token_in_type: TypeName,
        /// Token out type
        token_out_type: TypeName,
        /// Amount in
        amount_in: u64,
        /// Amount out
        amount_out: u64,
        /// Fee amount
        fee: u64,
        /// Timestamp
        timestamp: u64,
    }

    /// Liquidity add event
    public struct AddLiquidityEvent has copy, drop {
        provider: address,
        pool_id: ID,
        token_x_type: TypeName,
        token_y_type: TypeName,
        amount_x: u64,
        amount_y: u64,
        lp_minted: u64,
        timestamp: u64,
    }

    /// Liquidity remove event
    public struct RemoveLiquidityEvent has copy, drop {
        provider: address,
        pool_id: ID,
        token_x_type: TypeName,
        token_y_type: TypeName,
        amount_x: u64,
        amount_y: u64,
        lp_burned: u64,
        timestamp: u64,
    }

    // === Staking Events ===

    /// Stake event
    public struct StakeEvent has copy, drop {
        staker: address,
        pool_id: ID,
        token_type: TypeName,
        amount: u64,
        lock_duration: Option<u64>,
        timestamp: u64,
    }

    /// Unstake event
    public struct UnstakeEvent has copy, drop {
        staker: address,
        pool_id: ID,
        token_type: TypeName,
        amount: u64,
        rewards_claimed: u64,
        timestamp: u64,
    }

    /// Claim rewards event
    public struct ClaimRewardsEvent has copy, drop {
        claimer: address,
        pool_id: ID,
        reward_type: TypeName,
        amount: u64,
        timestamp: u64,
    }

    // === Governance Events ===

    /// Proposal created event
    public struct ProposalCreatedEvent has copy, drop {
        dao_id: ID,
        proposal_id: ID,
        proposer: address,
        title: String,
        start_time: u64,
        end_time: u64,
        timestamp: u64,
    }

    /// Vote cast event
    public struct VoteCastEvent has copy, drop {
        dao_id: ID,
        proposal_id: ID,
        voter: address,
        vote_type: u8, // 0=For, 1=Against, 2=Abstain
        weight: u64,
        timestamp: u64,
    }

    /// Proposal executed event
    public struct ProposalExecutedEvent has copy, drop {
        dao_id: ID,
        proposal_id: ID,
        executor: address,
        timestamp: u64,
    }

    // === Access Control Events ===

    /// Role granted event
    public struct RoleGrantedEvent has copy, drop {
        account: address,
        role: u8,
        granter: address,
        timestamp: u64,
    }

    /// Role revoked event
    public struct RoleRevokedEvent has copy, drop {
        account: address,
        role: u8,
        revoker: address,
        timestamp: u64,
    }

    /// Ownership transferred event
    public struct OwnershipTransferredEvent has copy, drop {
        previous_owner: address,
        new_owner: address,
        timestamp: u64,
    }

    // === Generic Events ===

    /// Generic action event (for custom actions)
    public struct ActionEvent has copy, drop {
        actor: address,
        action: String,
        target_id: Option<ID>,
        data: vector<u8>,
        timestamp: u64,
    }

    /// Error event (for logging errors)
    public struct ErrorEvent has copy, drop {
        actor: address,
        error_code: u64,
        message: String,
        timestamp: u64,
    }

    // === Emit Functions ===

    /// Emit transfer event
    public fun emit_transfer(
        from: address,
        to: address,
        object_id: ID,
        object_type: TypeName,
        timestamp: u64,
    ) {
        event::emit(TransferEvent {
            from,
            to,
            object_id,
            object_type,
            timestamp,
        });
    }

    /// Emit mint event
    public fun emit_mint(
        minter: address,
        recipient: address,
        object_id: ID,
        object_type: TypeName,
        amount: Option<u64>,
        timestamp: u64,
    ) {
        event::emit(MintEvent {
            minter,
            recipient,
            object_id,
            object_type,
            amount,
            timestamp,
        });
    }

    /// Emit burn event
    public fun emit_burn(
        burner: address,
        object_id: ID,
        object_type: TypeName,
        amount: Option<u64>,
        timestamp: u64,
    ) {
        event::emit(BurnEvent {
            burner,
            object_id,
            object_type,
            amount,
            timestamp,
        });
    }

    /// Emit trade event
    public fun emit_trade(
        buyer: address,
        seller: address,
        item_id: ID,
        item_type: TypeName,
        price: u64,
        fee: u64,
        royalty: u64,
        payment_type: TypeName,
        timestamp: u64,
    ) {
        event::emit(TradeEvent {
            buyer,
            seller,
            item_id,
            item_type,
            price,
            fee,
            royalty,
            payment_type,
            timestamp,
        });
    }

    /// Emit swap event
    public fun emit_swap(
        swapper: address,
        pool_id: ID,
        token_in_type: TypeName,
        token_out_type: TypeName,
        amount_in: u64,
        amount_out: u64,
        fee: u64,
        timestamp: u64,
    ) {
        event::emit(SwapEvent {
            swapper,
            pool_id,
            token_in_type,
            token_out_type,
            amount_in,
            amount_out,
            fee,
            timestamp,
        });
    }

    /// Emit stake event
    public fun emit_stake(
        staker: address,
        pool_id: ID,
        token_type: TypeName,
        amount: u64,
        lock_duration: Option<u64>,
        timestamp: u64,
    ) {
        event::emit(StakeEvent {
            staker,
            pool_id,
            token_type,
            amount,
            lock_duration,
            timestamp,
        });
    }

    /// Emit unstake event
    public fun emit_unstake(
        staker: address,
        pool_id: ID,
        token_type: TypeName,
        amount: u64,
        rewards_claimed: u64,
        timestamp: u64,
    ) {
        event::emit(UnstakeEvent {
            staker,
            pool_id,
            token_type,
            amount,
            rewards_claimed,
            timestamp,
        });
    }

    /// Emit action event
    public fun emit_action(
        actor: address,
        action: String,
        target_id: Option<ID>,
        data: vector<u8>,
        timestamp: u64,
    ) {
        event::emit(ActionEvent {
            actor,
            action,
            target_id,
            data,
            timestamp,
        });
    }

    /// Emit error event
    public fun emit_error(
        actor: address,
        error_code: u64,
        message: String,
        timestamp: u64,
    ) {
        event::emit(ErrorEvent {
            actor,
            error_code,
            message,
            timestamp,
        });
    }

    // === Tests ===

    #[test]
    fun test_emit_transfer() {
        use std::type_name;

        emit_transfer(
            @0x1,
            @0x2,
            object::id_from_address(@0x123),
            type_name::get<u64>(),
            1000,
        );
    }

    #[test]
    fun test_emit_mint() {
        use std::type_name;

        emit_mint(
            @0x1,
            @0x2,
            object::id_from_address(@0x123),
            type_name::get<u64>(),
            option::some(100),
            1000,
        );
    }

    #[test]
    fun test_emit_trade() {
        use std::type_name;

        emit_trade(
            @0x1,
            @0x2,
            object::id_from_address(@0x123),
            type_name::get<u64>(),
            1000,
            50,
            25,
            type_name::get<u64>(),
            1000,
        );
    }

    #[test]
    fun test_emit_action() {
        use std::string;

        emit_action(
            @0x1,
            string::utf8(b"test_action"),
            option::none(),
            vector[1, 2, 3],
            1000,
        );
    }
}
