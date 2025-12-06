/// @title Boost
/// @notice Staking boost multipliers and NFT boosters
/// @dev Part of @sui-starters/staking package
module sui_starters_staking::boost {
    use std::string::String;
    use sui::event;

    // === Errors ===

    const EBoostNotActive: u64 = 0;
    const EBoostExpired: u64 = 1;
    const EMaxBoostReached: u64 = 2;

    // === Constants ===

    const BPS_BASE: u64 = 10000;

    // === Structs ===

    /// Boost configuration
    public struct BoostConfig has store, copy, drop {
        /// Base multiplier (10000 = 1x)
        base_multiplier: u64,
        /// Max total multiplier
        max_multiplier: u64,
        /// Boost duration in epochs (0 = permanent)
        default_duration: u64,
    }

    /// Active boost on a position
    public struct Boost has key, store {
        id: UID,
        owner: address,
        /// Boost name/type
        name: String,
        /// Multiplier in bps (e.g., 2000 = 20% boost)
        multiplier: u64,
        /// Start epoch
        start_epoch: u64,
        /// End epoch (0 = permanent)
        end_epoch: u64,
        /// Is boost active
        active: bool,
    }

    /// NFT that provides staking boost
    public struct BoosterNFT has key, store {
        id: UID,
        name: String,
        /// Boost multiplier in bps
        boost_multiplier: u64,
        /// Boost duration in epochs (0 = while held)
        duration: u64,
        /// Tier/rarity
        tier: u8,
    }

    /// User's boost aggregator
    public struct BoostAggregator has key, store {
        id: UID,
        owner: address,
        /// Total boost multiplier (sum of all active boosts)
        total_boost: u64,
        /// Number of active boosts
        active_boost_count: u64,
    }

    // === Events ===

    public struct BoostApplied has copy, drop {
        boost_id: ID,
        owner: address,
        multiplier: u64,
        end_epoch: u64,
    }

    public struct BoostExpired has copy, drop {
        boost_id: ID,
        owner: address,
    }

    public struct BoosterMinted has copy, drop {
        nft_id: ID,
        name: String,
        boost_multiplier: u64,
        tier: u8,
    }

    // === Create Functions ===

    /// Create boost config
    public fun new_config(
        base_multiplier: u64,
        max_multiplier: u64,
        default_duration: u64,
    ): BoostConfig {
        BoostConfig {
            base_multiplier,
            max_multiplier,
            default_duration,
        }
    }

    /// Create boost aggregator
    public fun new_aggregator(ctx: &mut TxContext): BoostAggregator {
        BoostAggregator {
            id: object::new(ctx),
            owner: ctx.sender(),
            total_boost: 0,
            active_boost_count: 0,
        }
    }

    /// Mint booster NFT
    public fun mint_booster(
        name: String,
        boost_multiplier: u64,
        duration: u64,
        tier: u8,
        ctx: &mut TxContext,
    ): BoosterNFT {
        let nft = BoosterNFT {
            id: object::new(ctx),
            name,
            boost_multiplier,
            duration,
            tier,
        };

        event::emit(BoosterMinted {
            nft_id: object::id(&nft),
            name: nft.name,
            boost_multiplier,
            tier,
        });

        nft
    }

    // === Core Functions ===

    /// Apply boost from NFT
    public fun apply_boost(
        config: &BoostConfig,
        aggregator: &mut BoostAggregator,
        nft: &BoosterNFT,
        ctx: &mut TxContext,
    ): Boost {
        let current_epoch = ctx.epoch();
        let end_epoch = if (nft.duration == 0) {
            0 // Permanent while NFT is held
        } else {
            current_epoch + nft.duration
        };

        let new_total = aggregator.total_boost + nft.boost_multiplier;
        assert!(new_total <= config.max_multiplier - config.base_multiplier, EMaxBoostReached);

        aggregator.total_boost = new_total;
        aggregator.active_boost_count = aggregator.active_boost_count + 1;

        let boost = Boost {
            id: object::new(ctx),
            owner: ctx.sender(),
            name: nft.name,
            multiplier: nft.boost_multiplier,
            start_epoch: current_epoch,
            end_epoch,
            active: true,
        };

        event::emit(BoostApplied {
            boost_id: object::id(&boost),
            owner: ctx.sender(),
            multiplier: nft.boost_multiplier,
            end_epoch,
        });

        boost
    }

    /// Remove boost
    public fun remove_boost(
        aggregator: &mut BoostAggregator,
        boost: Boost,
    ) {
        let Boost {
            id,
            owner,
            name: _,
            multiplier,
            start_epoch: _,
            end_epoch: _,
            active,
        } = boost;

        if (active) {
            aggregator.total_boost = aggregator.total_boost - multiplier;
            aggregator.active_boost_count = aggregator.active_boost_count - 1;
        };

        event::emit(BoostExpired {
            boost_id: object::uid_to_inner(&id),
            owner,
        });

        object::delete(id);
    }

    /// Check and expire boost if needed
    public fun check_expiry(
        aggregator: &mut BoostAggregator,
        boost: &mut Boost,
        current_epoch: u64,
    ): bool {
        if (!boost.active) {
            return true
        };

        if (boost.end_epoch > 0 && current_epoch >= boost.end_epoch) {
            boost.active = false;
            aggregator.total_boost = aggregator.total_boost - boost.multiplier;
            aggregator.active_boost_count = aggregator.active_boost_count - 1;

            event::emit(BoostExpired {
                boost_id: object::id(boost),
                owner: boost.owner,
            });

            return true
        };

        false
    }

    // === View Functions ===

    /// Calculate effective multiplier
    public fun effective_multiplier(
        config: &BoostConfig,
        aggregator: &BoostAggregator,
    ): u64 {
        config.base_multiplier + aggregator.total_boost
    }

    /// Apply multiplier to amount
    public fun apply_multiplier(
        config: &BoostConfig,
        aggregator: &BoostAggregator,
        amount: u64,
    ): u64 {
        let multiplier = effective_multiplier(config, aggregator);
        (amount * multiplier) / BPS_BASE
    }

    /// Get total boost
    public fun total_boost(aggregator: &BoostAggregator): u64 {
        aggregator.total_boost
    }

    /// Get active boost count
    public fun active_boost_count(aggregator: &BoostAggregator): u64 {
        aggregator.active_boost_count
    }

    /// Is boost active
    public fun is_active(boost: &Boost): bool {
        boost.active
    }

    /// Get boost multiplier
    public fun boost_multiplier(boost: &Boost): u64 {
        boost.multiplier
    }

    /// Get booster NFT info
    public fun booster_info(nft: &BoosterNFT): (String, u64, u64, u8) {
        (nft.name, nft.boost_multiplier, nft.duration, nft.tier)
    }

    /// Config getters
    public fun config_base_multiplier(config: &BoostConfig): u64 { config.base_multiplier }
    public fun config_max_multiplier(config: &BoostConfig): u64 { config.max_multiplier }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use std::string;

    #[test]
    fun test_create_config() {
        let config = new_config(10000, 30000, 30);

        assert!(config_base_multiplier(&config) == 10000, 0);
        assert!(config_max_multiplier(&config) == 30000, 1);
    }

    #[test]
    fun test_mint_booster() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let nft = mint_booster(
                string::utf8(b"Golden Booster"),
                2000, // 20% boost
                30,
                3,
                scenario.ctx(),
            );

            let (name, mult, dur, tier) = booster_info(&nft);
            assert!(mult == 2000, 0);
            assert!(dur == 30, 1);
            assert!(tier == 3, 2);

            transfer::public_transfer(nft, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_apply_boost() {
        let user = @0x1;
        let mut scenario = test_scenario::begin(user);

        {
            let config = new_config(10000, 30000, 30);
            let mut aggregator = new_aggregator(scenario.ctx());

            let nft = mint_booster(
                string::utf8(b"Bronze Booster"),
                1000, // 10% boost
                0, // permanent
                1,
                scenario.ctx(),
            );

            let boost = apply_boost(&config, &mut aggregator, &nft, scenario.ctx());

            assert!(total_boost(&aggregator) == 1000, 0);
            assert!(active_boost_count(&aggregator) == 1, 1);
            assert!(effective_multiplier(&config, &aggregator) == 11000, 2);

            // Test apply multiplier
            let boosted = apply_multiplier(&config, &aggregator, 1000);
            assert!(boosted == 1100, 3); // 1000 * 1.1

            transfer::public_transfer(nft, user);
            transfer::public_transfer(boost, user);
            transfer::public_transfer(aggregator, user);
        };

        scenario.end();
    }

    #[test]
    fun test_remove_boost() {
        let user = @0x1;
        let mut scenario = test_scenario::begin(user);

        {
            let config = new_config(10000, 30000, 30);
            let mut aggregator = new_aggregator(scenario.ctx());

            let nft = mint_booster(
                string::utf8(b"Bronze Booster"),
                1000,
                0,
                1,
                scenario.ctx(),
            );

            let boost = apply_boost(&config, &mut aggregator, &nft, scenario.ctx());
            assert!(total_boost(&aggregator) == 1000, 0);

            remove_boost(&mut aggregator, boost);
            assert!(total_boost(&aggregator) == 0, 1);
            assert!(active_boost_count(&aggregator) == 0, 2);

            transfer::public_transfer(nft, user);
            transfer::public_transfer(aggregator, user);
        };

        scenario.end();
    }
}
