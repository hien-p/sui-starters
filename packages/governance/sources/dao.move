/// @title DAO Core
/// @notice Core DAO structure and management
/// @dev Part of @sui-starters/governance package
module sui_starters_governance::dao {
    use std::string::String;
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};

    // === Errors ===

    const ENotMember: u64 = 0;
    const EAlreadyMember: u64 = 1;
    const EInsufficientVotingPower: u64 = 2;
    const EDAOPaused: u64 = 3;

    // === Structs ===

    /// DAO configuration
    public struct DAO<phantom T> has key, store {
        id: UID,
        name: String,
        description: String,
        /// Treasury balance
        treasury: Balance<T>,
        /// Minimum tokens to create proposal
        proposal_threshold: u64,
        /// Voting period in epochs
        voting_period: u64,
        /// Execution delay in epochs
        execution_delay: u64,
        /// Total members
        member_count: u64,
        /// Total proposals created
        proposal_count: u64,
        /// Is DAO paused
        paused: bool,
    }

    /// Member of DAO
    public struct DAOMember<phantom T> has key, store {
        id: UID,
        dao_id: ID,
        owner: address,
        /// Staked tokens for voting power
        staked: Balance<T>,
        /// Delegated voting power received
        delegated_power: u64,
        /// Join epoch
        joined_epoch: u64,
    }

    /// Admin capability
    public struct DAOAdminCap<phantom T> has key, store {
        id: UID,
        dao_id: ID,
    }

    // === Events ===

    public struct DAOCreated has copy, drop {
        dao_id: ID,
        name: String,
        proposal_threshold: u64,
    }

    public struct MemberJoined has copy, drop {
        dao_id: ID,
        member: address,
        staked_amount: u64,
    }

    public struct MemberLeft has copy, drop {
        dao_id: ID,
        member: address,
        withdrawn_amount: u64,
    }

    public struct TreasuryDeposit has copy, drop {
        dao_id: ID,
        depositor: address,
        amount: u64,
    }

    // === Create Functions ===

    /// Create new DAO
    public fun new<T>(
        name: String,
        description: String,
        proposal_threshold: u64,
        voting_period: u64,
        execution_delay: u64,
        ctx: &mut TxContext,
    ): (DAO<T>, DAOAdminCap<T>) {
        let dao = DAO {
            id: object::new(ctx),
            name,
            description,
            treasury: balance::zero(),
            proposal_threshold,
            voting_period,
            execution_delay,
            member_count: 0,
            proposal_count: 0,
            paused: false,
        };

        let dao_id = object::id(&dao);

        let admin_cap = DAOAdminCap {
            id: object::new(ctx),
            dao_id,
        };

        event::emit(DAOCreated {
            dao_id,
            name: dao.name,
            proposal_threshold,
        });

        (dao, admin_cap)
    }

    // === Member Functions ===

    /// Join DAO by staking tokens
    public fun join<T>(
        dao: &mut DAO<T>,
        stake: Coin<T>,
        ctx: &mut TxContext,
    ): DAOMember<T> {
        assert!(!dao.paused, EDAOPaused);

        let staked_amount = coin::value(&stake);
        let stake_balance = coin::into_balance(stake);

        let member = DAOMember {
            id: object::new(ctx),
            dao_id: object::id(dao),
            owner: ctx.sender(),
            staked: stake_balance,
            delegated_power: 0,
            joined_epoch: ctx.epoch(),
        };

        dao.member_count = dao.member_count + 1;

        event::emit(MemberJoined {
            dao_id: object::id(dao),
            member: ctx.sender(),
            staked_amount,
        });

        member
    }

    /// Leave DAO and withdraw stake
    public fun leave<T>(
        dao: &mut DAO<T>,
        member: DAOMember<T>,
        ctx: &mut TxContext,
    ): Coin<T> {
        let DAOMember {
            id,
            dao_id: _,
            owner,
            staked,
            delegated_power: _,
            joined_epoch: _,
        } = member;

        let withdrawn_amount = balance::value(&staked);
        let coin = coin::from_balance(staked, ctx);

        dao.member_count = dao.member_count - 1;

        event::emit(MemberLeft {
            dao_id: object::id(dao),
            member: owner,
            withdrawn_amount,
        });

        object::delete(id);
        coin
    }

    /// Add more stake
    public fun add_stake<T>(
        member: &mut DAOMember<T>,
        stake: Coin<T>,
    ) {
        let stake_balance = coin::into_balance(stake);
        balance::join(&mut member.staked, stake_balance);
    }

    /// Remove stake (partial withdrawal)
    public fun remove_stake<T>(
        member: &mut DAOMember<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        let withdrawn = balance::split(&mut member.staked, amount);
        coin::from_balance(withdrawn, ctx)
    }

    // === Treasury Functions ===

    /// Deposit to treasury
    public fun deposit_treasury<T>(
        dao: &mut DAO<T>,
        deposit: Coin<T>,
        ctx: &TxContext,
    ) {
        let amount = coin::value(&deposit);
        let deposit_balance = coin::into_balance(deposit);
        balance::join(&mut dao.treasury, deposit_balance);

        event::emit(TreasuryDeposit {
            dao_id: object::id(dao),
            depositor: ctx.sender(),
            amount,
        });
    }

    /// Withdraw from treasury (admin only)
    public fun withdraw_treasury<T>(
        dao: &mut DAO<T>,
        _admin: &DAOAdminCap<T>,
        amount: u64,
        ctx: &mut TxContext,
    ): Coin<T> {
        let withdrawn = balance::split(&mut dao.treasury, amount);
        coin::from_balance(withdrawn, ctx)
    }

    // === Admin Functions ===

    /// Set DAO paused
    public fun set_paused<T>(
        dao: &mut DAO<T>,
        _admin: &DAOAdminCap<T>,
        paused: bool,
    ) {
        dao.paused = paused;
    }

    /// Update proposal threshold
    public fun set_proposal_threshold<T>(
        dao: &mut DAO<T>,
        _admin: &DAOAdminCap<T>,
        threshold: u64,
    ) {
        dao.proposal_threshold = threshold;
    }

    /// Update voting period
    public fun set_voting_period<T>(
        dao: &mut DAO<T>,
        _admin: &DAOAdminCap<T>,
        period: u64,
    ) {
        dao.voting_period = period;
    }

    /// Increment proposal count (called by proposal module)
    public fun increment_proposal_count<T>(dao: &mut DAO<T>): u64 {
        dao.proposal_count = dao.proposal_count + 1;
        dao.proposal_count
    }

    // === View Functions ===

    /// Get voting power
    public fun voting_power<T>(member: &DAOMember<T>): u64 {
        balance::value(&member.staked) + member.delegated_power
    }

    /// Get staked amount
    public fun staked_amount<T>(member: &DAOMember<T>): u64 {
        balance::value(&member.staked)
    }

    /// Get delegated power
    public fun delegated_power<T>(member: &DAOMember<T>): u64 {
        member.delegated_power
    }

    /// Can create proposal
    public fun can_propose<T>(dao: &DAO<T>, member: &DAOMember<T>): bool {
        !dao.paused && voting_power(member) >= dao.proposal_threshold
    }

    /// Get treasury balance
    public fun treasury_balance<T>(dao: &DAO<T>): u64 {
        balance::value(&dao.treasury)
    }

    /// Get member count
    public fun member_count<T>(dao: &DAO<T>): u64 {
        dao.member_count
    }

    /// Get proposal count
    public fun proposal_count<T>(dao: &DAO<T>): u64 {
        dao.proposal_count
    }

    /// Get voting period
    public fun voting_period<T>(dao: &DAO<T>): u64 {
        dao.voting_period
    }

    /// Get execution delay
    public fun execution_delay<T>(dao: &DAO<T>): u64 {
        dao.execution_delay
    }

    /// Get proposal threshold
    public fun proposal_threshold<T>(dao: &DAO<T>): u64 {
        dao.proposal_threshold
    }

    /// Is DAO paused
    public fun is_paused<T>(dao: &DAO<T>): bool {
        dao.paused
    }

    /// Get DAO name
    public fun name<T>(dao: &DAO<T>): String {
        dao.name
    }

    /// Add delegated power to member (called by delegation module)
    public fun add_delegated_power<T>(member: &mut DAOMember<T>, amount: u64) {
        member.delegated_power = member.delegated_power + amount;
    }

    /// Remove delegated power from member (called by delegation module)
    public fun remove_delegated_power<T>(member: &mut DAOMember<T>, amount: u64) {
        member.delegated_power = member.delegated_power - amount;
    }

    // === Tests ===

    #[test_only]
    use sui::sui::SUI;
    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use std::string;

    #[test]
    fun test_create_dao() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let (dao, admin_cap) = new<SUI>(
                string::utf8(b"Test DAO"),
                string::utf8(b"A test DAO"),
                100,
                7,
                2,
                scenario.ctx(),
            );

            assert!(member_count(&dao) == 0, 0);
            assert!(proposal_count(&dao) == 0, 1);
            assert!(!is_paused(&dao), 2);

            transfer::public_share_object(dao);
            transfer::public_transfer(admin_cap, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_join_leave_dao() {
        let admin = @0xAD;
        let user = @0x1;
        let mut scenario = test_scenario::begin(admin);

        // Create DAO
        {
            let (dao, admin_cap) = new<SUI>(
                string::utf8(b"Test DAO"),
                string::utf8(b"A test DAO"),
                100,
                7,
                2,
                scenario.ctx(),
            );
            transfer::public_share_object(dao);
            transfer::public_transfer(admin_cap, admin);
        };

        // User joins
        scenario.next_tx(user);
        {
            let mut dao = scenario.take_shared<DAO<SUI>>();
            let stake = coin::mint_for_testing<SUI>(1000, scenario.ctx());

            let member = join(&mut dao, stake, scenario.ctx());
            assert!(voting_power(&member) == 1000, 0);
            assert!(member_count(&dao) == 1, 1);

            transfer::public_transfer(member, user);
            test_scenario::return_shared(dao);
        };

        // User leaves
        scenario.next_tx(user);
        {
            let mut dao = scenario.take_shared<DAO<SUI>>();
            let member = scenario.take_from_sender<DAOMember<SUI>>();

            let coin = leave(&mut dao, member, scenario.ctx());
            assert!(coin::value(&coin) == 1000, 2);
            assert!(member_count(&dao) == 0, 3);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(dao);
        };

        scenario.end();
    }
}
