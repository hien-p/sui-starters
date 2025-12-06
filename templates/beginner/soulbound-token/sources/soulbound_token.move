/// @title Soulbound Token (SBT)
/// @notice Non-transferable token bound to an address - learn access control
/// @dev Demonstrates soulbound tokens, issuer patterns, and revocation
module soulbound_token::soulbound_token {
    use std::string::String;
    use sui::event;
    use sui::package;
    use sui::display;

    // === Errors ===

    const EAlreadyHasSBT: u64 = 0;
    const ENotRevocable: u64 = 1;

    // === Structs ===

    /// One-time witness
    public struct SOULBOUND_TOKEN has drop {}

    /// Soulbound token - cannot be transferred
    public struct SoulboundToken has key {
        id: UID,
        /// Token name/title
        name: String,
        /// Description or achievement
        description: String,
        /// Image URL
        image_url: String,
        /// Issuer who created this token
        issuer: address,
        /// Issue timestamp
        issued_at: u64,
        /// Can this token be revoked?
        revocable: bool,
    }

    /// Issuer capability
    public struct IssuerCap has key, store {
        id: UID,
        /// Issuer name
        name: String,
        /// Total tokens issued
        total_issued: u64,
    }

    // === Events ===

    public struct SBTIssued has copy, drop {
        sbt_id: ID,
        name: String,
        recipient: address,
        issuer: address,
    }

    public struct SBTRevoked has copy, drop {
        sbt_id: ID,
        name: String,
        holder: address,
        revoker: address,
    }

    // === Init Function ===

    fun init(otw: SOULBOUND_TOKEN, ctx: &mut TxContext) {
        let keys = vector[
            std::string::utf8(b"name"),
            std::string::utf8(b"description"),
            std::string::utf8(b"image_url"),
            std::string::utf8(b"issuer"),
        ];

        let values = vector[
            std::string::utf8(b"{name}"),
            std::string::utf8(b"{description}"),
            std::string::utf8(b"{image_url}"),
            std::string::utf8(b"Issued by: {issuer}"),
        ];

        let publisher = package::claim(otw, ctx);
        let mut disp = display::new_with_fields<SoulboundToken>(
            &publisher,
            keys,
            values,
            ctx,
        );

        display::update_version(&mut disp);

        let issuer_cap = IssuerCap {
            id: object::new(ctx),
            name: std::string::utf8(b"Default Issuer"),
            total_issued: 0,
        };

        transfer::public_transfer(publisher, ctx.sender());
        transfer::public_transfer(disp, ctx.sender());
        transfer::public_transfer(issuer_cap, ctx.sender());
    }

    // === Entry Functions ===

    /// Issue a new soulbound token
    public entry fun issue(
        cap: &mut IssuerCap,
        name: String,
        description: String,
        image_url: String,
        recipient: address,
        revocable: bool,
        ctx: &mut TxContext,
    ) {
        cap.total_issued = cap.total_issued + 1;

        let sbt = SoulboundToken {
            id: object::new(ctx),
            name,
            description,
            image_url,
            issuer: ctx.sender(),
            issued_at: ctx.epoch(),
            revocable,
        };

        event::emit(SBTIssued {
            sbt_id: object::id(&sbt),
            name: sbt.name,
            recipient,
            issuer: ctx.sender(),
        });

        // Transfer to recipient - they cannot transfer it away
        transfer::transfer(sbt, recipient);
    }

    /// Revoke a soulbound token (issuer only, if revocable)
    public entry fun revoke(
        _cap: &IssuerCap,
        sbt: SoulboundToken,
        ctx: &TxContext,
    ) {
        assert!(sbt.revocable, ENotRevocable);
        assert!(sbt.issuer == ctx.sender(), ENotRevocable);

        let SoulboundToken {
            id,
            name,
            description: _,
            image_url: _,
            issuer: _,
            issued_at: _,
            revocable: _,
        } = sbt;

        // Note: holder must provide the SBT for revocation
        // In practice, you'd use a different mechanism

        event::emit(SBTRevoked {
            sbt_id: object::uid_to_inner(&id),
            name,
            holder: ctx.sender(), // The one calling revoke
            revoker: ctx.sender(),
        });

        object::delete(id);
    }

    /// Voluntarily burn your own SBT
    public entry fun burn(sbt: SoulboundToken) {
        let SoulboundToken {
            id,
            name: _,
            description: _,
            image_url: _,
            issuer: _,
            issued_at: _,
            revocable: _,
        } = sbt;

        object::delete(id);
    }

    /// Update issuer name
    public entry fun set_issuer_name(cap: &mut IssuerCap, name: String) {
        cap.name = name;
    }

    // === View Functions ===

    /// Get SBT name
    public fun name(sbt: &SoulboundToken): String {
        sbt.name
    }

    /// Get SBT description
    public fun description(sbt: &SoulboundToken): String {
        sbt.description
    }

    /// Get SBT issuer
    public fun issuer(sbt: &SoulboundToken): address {
        sbt.issuer
    }

    /// Is SBT revocable
    public fun is_revocable(sbt: &SoulboundToken): bool {
        sbt.revocable
    }

    /// Get total issued by issuer
    public fun total_issued(cap: &IssuerCap): u64 {
        cap.total_issued
    }

    /// Get issuer cap name
    public fun issuer_name(cap: &IssuerCap): String {
        cap.name
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use std::string;

    #[test]
    fun test_issue_sbt() {
        let admin = @0x1;
        let recipient = @0x2;
        let mut scenario = test_scenario::begin(admin);

        {
            init(SOULBOUND_TOKEN {}, scenario.ctx());
        };

        // Issue SBT
        scenario.next_tx(admin);
        {
            let mut cap = scenario.take_from_sender<IssuerCap>();

            issue(
                &mut cap,
                string::utf8(b"Achievement Badge"),
                string::utf8(b"Completed the tutorial"),
                string::utf8(b"https://example.com/badge.png"),
                recipient,
                false,
                scenario.ctx(),
            );

            assert!(total_issued(&cap) == 1, 0);
            scenario.return_to_sender(cap);
        };

        // Check recipient has SBT
        scenario.next_tx(recipient);
        {
            let sbt = scenario.take_from_sender<SoulboundToken>();

            assert!(name(&sbt) == string::utf8(b"Achievement Badge"), 1);
            assert!(issuer(&sbt) == admin, 2);
            assert!(!is_revocable(&sbt), 3);

            scenario.return_to_sender(sbt);
        };

        scenario.end();
    }

    #[test]
    fun test_burn_own_sbt() {
        let admin = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(admin);

        {
            init(SOULBOUND_TOKEN {}, scenario.ctx());
        };

        // Issue
        scenario.next_tx(admin);
        {
            let mut cap = scenario.take_from_sender<IssuerCap>();
            issue(
                &mut cap,
                string::utf8(b"Test Badge"),
                string::utf8(b"Test"),
                string::utf8(b"https://example.com/test.png"),
                user,
                false,
                scenario.ctx(),
            );
            scenario.return_to_sender(cap);
        };

        // User burns their own SBT
        scenario.next_tx(user);
        {
            let sbt = scenario.take_from_sender<SoulboundToken>();
            burn(sbt);
        };

        scenario.end();
    }

    #[test]
    fun test_multiple_issues() {
        let admin = @0x1;
        let user1 = @0x2;
        let user2 = @0x3;
        let mut scenario = test_scenario::begin(admin);

        {
            init(SOULBOUND_TOKEN {}, scenario.ctx());
        };

        // Issue multiple SBTs
        scenario.next_tx(admin);
        {
            let mut cap = scenario.take_from_sender<IssuerCap>();

            issue(
                &mut cap,
                string::utf8(b"Badge 1"),
                string::utf8(b"First"),
                string::utf8(b"https://example.com/1.png"),
                user1,
                false,
                scenario.ctx(),
            );

            issue(
                &mut cap,
                string::utf8(b"Badge 2"),
                string::utf8(b"Second"),
                string::utf8(b"https://example.com/2.png"),
                user2,
                true,
                scenario.ctx(),
            );

            assert!(total_issued(&cap) == 2, 0);
            scenario.return_to_sender(cap);
        };

        scenario.end();
    }
}
