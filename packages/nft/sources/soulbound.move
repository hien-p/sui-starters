/// @title Soulbound NFT
/// @notice Non-transferable NFTs (SBTs) for credentials, achievements, etc.
/// @dev Part of @sui-starters/nft package
module sui_starters_nft::soulbound {
    use std::string::String;
    use sui::event;
    use sui::vec_map::{Self, VecMap};

    // === Errors ===

    /// Soulbound tokens cannot be transferred
    const ECannotTransfer: u64 = 0;

    /// Token already exists for this soul
    const EAlreadyExists: u64 = 1;

    /// Token is revoked
    const ERevoked: u64 = 2;

    /// Not the issuer
    const ENotIssuer: u64 = 3;

    /// Not the owner
    const ENotOwner: u64 = 4;

    // === Structs ===

    /// Soulbound token (non-transferable)
    public struct SoulboundToken<phantom T> has key {
        id: UID,
        /// Token name
        name: String,
        /// Token description
        description: String,
        /// Token image URL
        image_url: String,
        /// Issuer address
        issuer: address,
        /// Soul (owner) address
        soul: address,
        /// Issue timestamp
        issued_at: u64,
        /// Expiry timestamp (0 = no expiry)
        expires_at: u64,
        /// Is revoked
        revoked: bool,
        /// Revoked timestamp
        revoked_at: u64,
        /// Additional metadata
        metadata: VecMap<String, String>,
    }

    /// Issuer capability for soulbound tokens
    public struct IssuerCap<phantom T> has key, store {
        id: UID,
        /// Issuer name
        name: String,
        /// Total issued
        total_issued: u64,
        /// Total revoked
        total_revoked: u64,
    }

    /// Soulbound token registry (tracks issued tokens)
    public struct SBTRegistry<phantom T> has key, store {
        id: UID,
        /// Soul -> Token ID mapping
        tokens: sui::table::Table<address, ID>,
        /// Total tokens
        total: u64,
    }

    // === Events ===

    /// Emitted when SBT is issued
    public struct SBTIssued has copy, drop {
        token_id: ID,
        issuer: address,
        soul: address,
        name: String,
    }

    /// Emitted when SBT is revoked
    public struct SBTRevoked has copy, drop {
        token_id: ID,
        issuer: address,
        soul: address,
        reason: String,
    }

    /// Emitted when SBT is burned by soul
    public struct SBTBurned has copy, drop {
        token_id: ID,
        soul: address,
    }

    // === IssuerCap Functions ===

    /// Create issuer capability
    public fun new_issuer<T>(name: String, ctx: &mut TxContext): IssuerCap<T> {
        IssuerCap<T> {
            id: object::new(ctx),
            name,
            total_issued: 0,
            total_revoked: 0,
        }
    }

    /// Get issuer name
    public fun issuer_name<T>(cap: &IssuerCap<T>): String {
        cap.name
    }

    /// Get total issued
    public fun total_issued<T>(cap: &IssuerCap<T>): u64 {
        cap.total_issued
    }

    /// Get total revoked
    public fun total_revoked<T>(cap: &IssuerCap<T>): u64 {
        cap.total_revoked
    }

    /// Destroy issuer cap
    public fun destroy_issuer<T>(cap: IssuerCap<T>) {
        let IssuerCap { id, name: _, total_issued: _, total_revoked: _ } = cap;
        object::delete(id);
    }

    // === SBTRegistry Functions ===

    /// Create SBT registry
    public fun new_registry<T>(ctx: &mut TxContext): SBTRegistry<T> {
        SBTRegistry<T> {
            id: object::new(ctx),
            tokens: sui::table::new(ctx),
            total: 0,
        }
    }

    /// Check if soul has token
    public fun has_token<T>(registry: &SBTRegistry<T>, soul: address): bool {
        sui::table::contains(&registry.tokens, soul)
    }

    /// Get token ID for soul
    public fun get_token_id<T>(registry: &SBTRegistry<T>, soul: address): ID {
        *sui::table::borrow(&registry.tokens, soul)
    }

    /// Get registry total
    public fun registry_total<T>(registry: &SBTRegistry<T>): u64 {
        registry.total
    }

    // === SoulboundToken Functions ===

    /// Issue soulbound token
    public fun issue<T>(
        cap: &mut IssuerCap<T>,
        soul: address,
        name: String,
        description: String,
        image_url: String,
        issued_at: u64,
        expires_at: u64,
        ctx: &mut TxContext,
    ): SoulboundToken<T> {
        let issuer = ctx.sender();

        let token = SoulboundToken<T> {
            id: object::new(ctx),
            name,
            description,
            image_url,
            issuer,
            soul,
            issued_at,
            expires_at,
            revoked: false,
            revoked_at: 0,
            metadata: vec_map::empty(),
        };

        cap.total_issued = cap.total_issued + 1;

        event::emit(SBTIssued {
            token_id: object::id(&token),
            issuer,
            soul,
            name: token.name,
        });

        token
    }

    /// Issue and transfer to soul
    public fun issue_to<T>(
        cap: &mut IssuerCap<T>,
        soul: address,
        name: String,
        description: String,
        image_url: String,
        issued_at: u64,
        expires_at: u64,
        ctx: &mut TxContext,
    ) {
        let token = issue(cap, soul, name, description, image_url, issued_at, expires_at, ctx);
        transfer::transfer(token, soul);
    }

    /// Issue with registry tracking
    public fun issue_with_registry<T>(
        cap: &mut IssuerCap<T>,
        registry: &mut SBTRegistry<T>,
        soul: address,
        name: String,
        description: String,
        image_url: String,
        issued_at: u64,
        expires_at: u64,
        ctx: &mut TxContext,
    ) {
        assert!(!has_token(registry, soul), EAlreadyExists);

        let token = issue(cap, soul, name, description, image_url, issued_at, expires_at, ctx);
        let token_id = object::id(&token);

        sui::table::add(&mut registry.tokens, soul, token_id);
        registry.total = registry.total + 1;

        transfer::transfer(token, soul);
    }

    /// Add metadata to token during issuance
    public fun add_metadata<T>(
        token: &mut SoulboundToken<T>,
        key: String,
        value: String,
        ctx: &TxContext,
    ) {
        assert!(token.issuer == ctx.sender(), ENotIssuer);
        vec_map::insert(&mut token.metadata, key, value);
    }

    /// Revoke token (by issuer)
    public fun revoke<T>(
        cap: &mut IssuerCap<T>,
        token: &mut SoulboundToken<T>,
        reason: String,
        revoked_at: u64,
        ctx: &TxContext,
    ) {
        assert!(token.issuer == ctx.sender(), ENotIssuer);
        assert!(!token.revoked, ERevoked);

        token.revoked = true;
        token.revoked_at = revoked_at;
        cap.total_revoked = cap.total_revoked + 1;

        event::emit(SBTRevoked {
            token_id: object::id(token),
            issuer: token.issuer,
            soul: token.soul,
            reason,
        });
    }

    /// Burn token (by soul/owner)
    public fun burn<T>(token: SoulboundToken<T>, ctx: &TxContext) {
        assert!(token.soul == ctx.sender(), ENotOwner);

        let token_id = object::id(&token);
        let soul = token.soul;

        event::emit(SBTBurned {
            token_id,
            soul,
        });

        let SoulboundToken {
            id,
            name: _,
            description: _,
            image_url: _,
            issuer: _,
            soul: _,
            issued_at: _,
            expires_at: _,
            revoked: _,
            revoked_at: _,
            metadata: _,
        } = token;

        object::delete(id);
    }

    // === View Functions ===

    /// Get token name
    public fun name<T>(token: &SoulboundToken<T>): String {
        token.name
    }

    /// Get token description
    public fun description<T>(token: &SoulboundToken<T>): String {
        token.description
    }

    /// Get token image URL
    public fun image_url<T>(token: &SoulboundToken<T>): String {
        token.image_url
    }

    /// Get issuer
    public fun issuer<T>(token: &SoulboundToken<T>): address {
        token.issuer
    }

    /// Get soul (owner)
    public fun soul<T>(token: &SoulboundToken<T>): address {
        token.soul
    }

    /// Get issued timestamp
    public fun issued_at<T>(token: &SoulboundToken<T>): u64 {
        token.issued_at
    }

    /// Get expiry timestamp
    public fun expires_at<T>(token: &SoulboundToken<T>): u64 {
        token.expires_at
    }

    /// Check if revoked
    public fun is_revoked<T>(token: &SoulboundToken<T>): bool {
        token.revoked
    }

    /// Get revoked timestamp
    public fun revoked_at<T>(token: &SoulboundToken<T>): u64 {
        token.revoked_at
    }

    /// Check if expired
    public fun is_expired<T>(token: &SoulboundToken<T>, current_time: u64): bool {
        if (token.expires_at == 0) {
            return false // No expiry
        };
        current_time > token.expires_at
    }

    /// Check if token is valid (not revoked and not expired)
    public fun is_valid<T>(token: &SoulboundToken<T>, current_time: u64): bool {
        !token.revoked && !is_expired(token, current_time)
    }

    /// Get metadata value
    public fun get_metadata<T>(token: &SoulboundToken<T>, key: &String): String {
        *vec_map::get(&token.metadata, key)
    }

    /// Check if metadata exists
    public fun has_metadata<T>(token: &SoulboundToken<T>, key: &String): bool {
        vec_map::contains(&token.metadata, key)
    }

    /// Get token ID
    public fun id<T>(token: &SoulboundToken<T>): ID {
        object::id(token)
    }

    // === Tests ===

    /// Test witness type
    public struct TEST_SBT has drop {}

    #[test]
    fun test_issue_sbt() {
        use sui::test_scenario;
        use std::string;

        let issuer_addr = @0x1;
        let soul_addr = @0x2;
        let mut scenario = test_scenario::begin(issuer_addr);

        {
            let mut cap = new_issuer<TEST_SBT>(string::utf8(b"Test Issuer"), scenario.ctx());
            assert!(total_issued(&cap) == 0, 0);

            let token = issue(
                &mut cap,
                soul_addr,
                string::utf8(b"Achievement"),
                string::utf8(b"Test achievement"),
                string::utf8(b"https://image.url"),
                1000,
                0, // No expiry
                scenario.ctx(),
            );

            assert!(total_issued(&cap) == 1, 1);
            assert!(name(&token) == string::utf8(b"Achievement"), 2);
            assert!(soul(&token) == soul_addr, 3);
            assert!(issuer(&token) == issuer_addr, 4);
            assert!(!is_revoked(&token), 5);

            transfer::transfer(token, soul_addr);
            destroy_issuer(cap);
        };

        scenario.end();
    }

    #[test]
    fun test_revoke_sbt() {
        use sui::test_scenario;
        use std::string;

        let issuer_addr = @0x1;
        let soul_addr = @0x2;
        let mut scenario = test_scenario::begin(issuer_addr);

        {
            let mut cap = new_issuer<TEST_SBT>(string::utf8(b"Issuer"), scenario.ctx());

            let mut token = issue(
                &mut cap,
                soul_addr,
                string::utf8(b"Badge"),
                string::utf8(b"Test"),
                string::utf8(b""),
                1000,
                0,
                scenario.ctx(),
            );

            assert!(!is_revoked(&token), 0);

            revoke(
                &mut cap,
                &mut token,
                string::utf8(b"Violated terms"),
                2000,
                scenario.ctx(),
            );

            assert!(is_revoked(&token), 1);
            assert!(revoked_at(&token) == 2000, 2);
            assert!(total_revoked(&cap) == 1, 3);

            transfer::transfer(token, soul_addr);
            destroy_issuer(cap);
        };

        scenario.end();
    }

    #[test]
    fun test_burn_sbt() {
        use sui::test_scenario;
        use std::string;

        let issuer_addr = @0x1;
        let soul_addr = @0x2;
        let mut scenario = test_scenario::begin(issuer_addr);

        // Issue token
        {
            let mut cap = new_issuer<TEST_SBT>(string::utf8(b"Issuer"), scenario.ctx());

            issue_to(
                &mut cap,
                soul_addr,
                string::utf8(b"Badge"),
                string::utf8(b"Test"),
                string::utf8(b""),
                1000,
                0,
                scenario.ctx(),
            );

            destroy_issuer(cap);
        };

        // Burn as soul
        scenario.next_tx(soul_addr);
        {
            let token = scenario.take_from_sender<SoulboundToken<TEST_SBT>>();
            burn(token, scenario.ctx());
        };

        scenario.end();
    }

    #[test]
    fun test_validity_check() {
        use sui::test_scenario;
        use std::string;

        let issuer_addr = @0x1;
        let soul_addr = @0x2;
        let mut scenario = test_scenario::begin(issuer_addr);

        {
            let mut cap = new_issuer<TEST_SBT>(string::utf8(b"Issuer"), scenario.ctx());

            // Token with expiry
            let token = issue(
                &mut cap,
                soul_addr,
                string::utf8(b"Badge"),
                string::utf8(b"Test"),
                string::utf8(b""),
                1000,
                5000, // Expires at 5000
                scenario.ctx(),
            );

            // Not expired at 3000
            assert!(is_valid(&token, 3000), 0);
            assert!(!is_expired(&token, 3000), 1);

            // Expired at 6000
            assert!(!is_valid(&token, 6000), 2);
            assert!(is_expired(&token, 6000), 3);

            transfer::transfer(token, soul_addr);
            destroy_issuer(cap);
        };

        scenario.end();
    }

    #[test]
    fun test_no_expiry() {
        use sui::test_scenario;
        use std::string;

        let issuer_addr = @0x1;
        let soul_addr = @0x2;
        let mut scenario = test_scenario::begin(issuer_addr);

        {
            let mut cap = new_issuer<TEST_SBT>(string::utf8(b"Issuer"), scenario.ctx());

            let token = issue(
                &mut cap,
                soul_addr,
                string::utf8(b"Permanent Badge"),
                string::utf8(b"Never expires"),
                string::utf8(b""),
                1000,
                0, // No expiry
                scenario.ctx(),
            );

            // Should never expire
            assert!(!is_expired(&token, 1000000000), 0);
            assert!(is_valid(&token, 1000000000), 1);

            transfer::transfer(token, soul_addr);
            destroy_issuer(cap);
        };

        scenario.end();
    }

    #[test]
    fun test_metadata() {
        use sui::test_scenario;
        use std::string;

        let issuer_addr = @0x1;
        let soul_addr = @0x2;
        let mut scenario = test_scenario::begin(issuer_addr);

        {
            let mut cap = new_issuer<TEST_SBT>(string::utf8(b"Issuer"), scenario.ctx());

            let mut token = issue(
                &mut cap,
                soul_addr,
                string::utf8(b"Badge"),
                string::utf8(b"Test"),
                string::utf8(b""),
                1000,
                0,
                scenario.ctx(),
            );

            add_metadata(&mut token, string::utf8(b"level"), string::utf8(b"gold"), scenario.ctx());
            add_metadata(&mut token, string::utf8(b"score"), string::utf8(b"100"), scenario.ctx());

            assert!(has_metadata(&token, &string::utf8(b"level")), 0);
            assert!(get_metadata(&token, &string::utf8(b"level")) == string::utf8(b"gold"), 1);

            transfer::transfer(token, soul_addr);
            destroy_issuer(cap);
        };

        scenario.end();
    }

    #[test]
    fun test_registry() {
        use sui::test_scenario;
        use std::string;

        let issuer_addr = @0x1;
        let soul1 = @0x2;
        let soul2 = @0x3;
        let mut scenario = test_scenario::begin(issuer_addr);

        {
            let mut cap = new_issuer<TEST_SBT>(string::utf8(b"Issuer"), scenario.ctx());
            let mut registry = new_registry<TEST_SBT>(scenario.ctx());

            assert!(registry_total(&registry) == 0, 0);
            assert!(!has_token(&registry, soul1), 1);

            issue_with_registry(
                &mut cap,
                &mut registry,
                soul1,
                string::utf8(b"Badge1"),
                string::utf8(b"Test"),
                string::utf8(b""),
                1000,
                0,
                scenario.ctx(),
            );

            assert!(registry_total(&registry) == 1, 2);
            assert!(has_token(&registry, soul1), 3);
            assert!(!has_token(&registry, soul2), 4);

            transfer::public_share_object(registry);
            destroy_issuer(cap);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EAlreadyExists)]
    fun test_duplicate_issuance() {
        use sui::test_scenario;
        use std::string;

        let issuer_addr = @0x1;
        let soul = @0x2;
        let mut scenario = test_scenario::begin(issuer_addr);

        {
            let mut cap = new_issuer<TEST_SBT>(string::utf8(b"Issuer"), scenario.ctx());
            let mut registry = new_registry<TEST_SBT>(scenario.ctx());

            issue_with_registry(
                &mut cap,
                &mut registry,
                soul,
                string::utf8(b"Badge1"),
                string::utf8(b"Test"),
                string::utf8(b""),
                1000,
                0,
                scenario.ctx(),
            );

            // Should fail - already has token
            issue_with_registry(
                &mut cap,
                &mut registry,
                soul,
                string::utf8(b"Badge2"),
                string::utf8(b"Test"),
                string::utf8(b""),
                2000,
                0,
                scenario.ctx(),
            );

            transfer::public_share_object(registry);
            destroy_issuer(cap);
        };

        scenario.end();
    }
}
