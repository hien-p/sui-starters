/// @title Sui Starters Package Registry
/// @notice Registry for managing @sui-starters package metadata and MVR resolution
/// @dev Enables package discovery and versioning for the Sui Starters ecosystem
module sui_starters_registry::registry {
    use std::string::String;
    use sui::event;
    use sui::table::{Self, Table};

    // === Errors ===

    const EPackageNotFound: u64 = 0;
    const EPackageAlreadyExists: u64 = 1;
    const ENotAuthorized: u64 = 2;
    const EInvalidVersion: u64 = 3;

    // === Structs ===

    /// Admin capability for managing the registry
    public struct RegistryAdminCap has key, store {
        id: UID,
    }

    /// Package metadata
    public struct PackageInfo has store, copy, drop {
        /// Package ID on-chain
        package_id: address,
        /// Package name (e.g., "core", "access", "events")
        name: String,
        /// Version string (e.g., "1.0.0")
        version: String,
        /// Description
        description: String,
        /// Deployment network (e.g., "testnet", "mainnet")
        network: String,
        /// Deployment timestamp
        deployed_at: u64,
        /// Deployer address
        deployer: address,
    }

    /// Main registry object
    public struct PackageRegistry has key {
        id: UID,
        /// Package name -> PackageInfo
        packages: Table<String, PackageInfo>,
        /// Total packages registered
        count: u64,
        /// Registry owner
        owner: address,
    }

    // === Events ===

    /// Emitted when a package is registered
    public struct PackageRegistered has copy, drop {
        name: String,
        package_id: address,
        version: String,
        network: String,
    }

    /// Emitted when a package is updated
    public struct PackageUpdated has copy, drop {
        name: String,
        old_package_id: address,
        new_package_id: address,
        new_version: String,
    }

    // === Init ===

    fun init(ctx: &mut TxContext) {
        let admin_cap = RegistryAdminCap {
            id: object::new(ctx),
        };

        let registry = PackageRegistry {
            id: object::new(ctx),
            packages: table::new(ctx),
            count: 0,
            owner: ctx.sender(),
        };

        transfer::transfer(admin_cap, ctx.sender());
        transfer::share_object(registry);
    }

    // === Admin Functions ===

    /// Register a new package
    public entry fun register_package(
        _admin: &RegistryAdminCap,
        registry: &mut PackageRegistry,
        name: String,
        package_id: address,
        version: String,
        description: String,
        network: String,
        deployed_at: u64,
        ctx: &TxContext
    ) {
        assert!(!table::contains(&registry.packages, name), EPackageAlreadyExists);

        let package_info = PackageInfo {
            package_id,
            name,
            version,
            description,
            network,
            deployed_at,
            deployer: ctx.sender(),
        };

        table::add(&mut registry.packages, name, package_info);
        registry.count = registry.count + 1;

        event::emit(PackageRegistered {
            name,
            package_id,
            version,
            network,
        });
    }

    /// Update existing package (e.g., for new version or network)
    public entry fun update_package(
        _admin: &RegistryAdminCap,
        registry: &mut PackageRegistry,
        name: String,
        new_package_id: address,
        new_version: String,
        description: String,
        network: String,
        deployed_at: u64,
        ctx: &TxContext
    ) {
        assert!(table::contains(&registry.packages, name), EPackageNotFound);

        let old_info = table::borrow(&registry.packages, name);
        let old_package_id = old_info.package_id;

        let new_info = PackageInfo {
            package_id: new_package_id,
            name,
            version: new_version,
            description,
            network,
            deployed_at,
            deployer: ctx.sender(),
        };

        table::remove(&mut registry.packages, name);
        table::add(&mut registry.packages, name, new_info);

        event::emit(PackageUpdated {
            name,
            old_package_id,
            new_package_id,
            new_version,
        });
    }

    // === View Functions ===

    /// Get package info by name
    public fun get_package(registry: &PackageRegistry, name: String): &PackageInfo {
        assert!(table::contains(&registry.packages, name), EPackageNotFound);
        table::borrow(&registry.packages, name)
    }

    /// Check if package exists
    public fun has_package(registry: &PackageRegistry, name: String): bool {
        table::contains(&registry.packages, name)
    }

    /// Get package ID for MVR resolution
    public fun resolve_package_id(registry: &PackageRegistry, name: String): address {
        let info = get_package(registry, name);
        info.package_id
    }

    /// Get total packages count
    public fun total_packages(registry: &PackageRegistry): u64 {
        registry.count
    }

    /// Get registry owner
    public fun owner(registry: &PackageRegistry): address {
        registry.owner
    }

    // === Package Info Getters ===

    public fun package_id(info: &PackageInfo): address { info.package_id }
    public fun name(info: &PackageInfo): String { info.name }
    public fun version(info: &PackageInfo): String { info.version }
    public fun description(info: &PackageInfo): String { info.description }
    public fun network(info: &PackageInfo): String { info.network }
    public fun deployed_at(info: &PackageInfo): u64 { info.deployed_at }
    public fun deployer(info: &PackageInfo): address { info.deployer }

    // === Tests ===

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test]
    fun test_register_package() {
        use sui::test_scenario;
        use std::string;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        // Initialize registry
        {
            init_for_testing(scenario.ctx());
        };

        // Register a package
        scenario.next_tx(admin);
        {
            let admin_cap = scenario.take_from_sender<RegistryAdminCap>();
            let mut registry = scenario.take_shared<PackageRegistry>();

            register_package(
                &admin_cap,
                &mut registry,
                string::utf8(b"core"),
                @0x123,
                string::utf8(b"1.0.0"),
                string::utf8(b"Core utilities"),
                string::utf8(b"testnet"),
                1000,
                scenario.ctx()
            );

            assert!(total_packages(&registry) == 1, 0);
            assert!(has_package(&registry, string::utf8(b"core")), 1);

            scenario.return_to_sender(admin_cap);
            test_scenario::return_shared(registry);
        };

        scenario.end();
    }
}
