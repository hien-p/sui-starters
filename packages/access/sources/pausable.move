/// @title Pausable Pattern
/// @notice Emergency pause/unpause functionality
/// @dev Part of @sui-starters/access package
module sui_starters_access::pausable {
    use sui::event;

    // === Errors ===

    /// Contract is paused
    const EPaused: u64 = 0;

    /// Contract is not paused
    const ENotPaused: u64 = 1;

    // === Structs ===

    /// Pause state that can be embedded in other objects
    public struct PauseState has store, drop {
        paused: bool,
    }

    /// Standalone pausable object
    public struct Pausable<phantom T> has key, store {
        id: UID,
        state: PauseState,
    }

    // === Events ===

    /// Emitted when contract is paused
    public struct Paused has copy, drop {
        pauser: address,
    }

    /// Emitted when contract is unpaused
    public struct Unpaused has copy, drop {
        unpauser: address,
    }

    // === PauseState (Embeddable) Functions ===

    /// Create new pause state (unpaused by default)
    public fun new_state(): PauseState {
        PauseState {
            paused: false,
        }
    }

    /// Create new pause state with initial value
    public fun new_state_with(paused: bool): PauseState {
        PauseState {
            paused,
        }
    }

    /// Check if paused
    public fun is_paused(state: &PauseState): bool {
        state.paused
    }

    /// Pause the contract
    public fun pause(state: &mut PauseState, ctx: &TxContext) {
        assert!(!state.paused, EPaused);
        state.paused = true;

        event::emit(Paused {
            pauser: ctx.sender(),
        });
    }

    /// Unpause the contract
    public fun unpause(state: &mut PauseState, ctx: &TxContext) {
        assert!(state.paused, ENotPaused);
        state.paused = false;

        event::emit(Unpaused {
            unpauser: ctx.sender(),
        });
    }

    /// Assert contract is not paused
    public fun require_not_paused(state: &PauseState) {
        assert!(!state.paused, EPaused);
    }

    /// Assert contract is paused
    public fun require_paused(state: &PauseState) {
        assert!(state.paused, ENotPaused);
    }

    // === Pausable Object Functions ===

    /// Create a new pausable object
    public fun new<T>(ctx: &mut TxContext): Pausable<T> {
        Pausable<T> {
            id: object::new(ctx),
            state: new_state(),
        }
    }

    /// Create a new pausable object with initial state
    public fun new_with<T>(paused: bool, ctx: &mut TxContext): Pausable<T> {
        Pausable<T> {
            id: object::new(ctx),
            state: new_state_with(paused),
        }
    }

    /// Check if pausable object is paused
    public fun pausable_is_paused<T>(pausable: &Pausable<T>): bool {
        is_paused(&pausable.state)
    }

    /// Pause the pausable object
    public fun pausable_pause<T>(pausable: &mut Pausable<T>, ctx: &TxContext) {
        pause(&mut pausable.state, ctx);
    }

    /// Unpause the pausable object
    public fun pausable_unpause<T>(pausable: &mut Pausable<T>, ctx: &TxContext) {
        unpause(&mut pausable.state, ctx);
    }

    /// Assert pausable object is not paused
    public fun pausable_require_not_paused<T>(pausable: &Pausable<T>) {
        require_not_paused(&pausable.state);
    }

    /// Destroy pausable object
    public fun destroy<T>(pausable: Pausable<T>) {
        let Pausable { id, state: _ } = pausable;
        object::delete(id);
    }

    // === Modifier Pattern Functions ===

    /// Execute function only when not paused (returns unit for chaining)
    public fun when_not_paused(state: &PauseState) {
        require_not_paused(state);
    }

    /// Execute function only when paused
    public fun when_paused(state: &PauseState) {
        require_paused(state);
    }

    // === Tests ===

    #[test]
    fun test_pause_state_basic() {
        let state = new_state();
        assert!(!is_paused(&state), 0);
    }

    #[test]
    fun test_pause_unpause() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut state = new_state();
            assert!(!is_paused(&state), 0);

            pause(&mut state, scenario.ctx());
            assert!(is_paused(&state), 1);

            unpause(&mut state, scenario.ctx());
            assert!(!is_paused(&state), 2);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EPaused)]
    fun test_require_not_paused_fails() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut state = new_state();
            pause(&mut state, scenario.ctx());
            require_not_paused(&state); // Should fail
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ENotPaused)]
    fun test_require_paused_fails() {
        let state = new_state();
        require_paused(&state); // Should fail - not paused
    }

    #[test]
    #[expected_failure(abort_code = EPaused)]
    fun test_cannot_pause_twice() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut state = new_state();
            pause(&mut state, scenario.ctx());
            pause(&mut state, scenario.ctx()); // Should fail
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = ENotPaused)]
    fun test_cannot_unpause_when_not_paused() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut state = new_state();
            unpause(&mut state, scenario.ctx()); // Should fail
        };

        scenario.end();
    }

    #[test]
    fun test_pausable_object() {
        use sui::test_scenario;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut pausable = new<PausableTest>(scenario.ctx());
            assert!(!pausable_is_paused(&pausable), 0);

            pausable_pause(&mut pausable, scenario.ctx());
            assert!(pausable_is_paused(&pausable), 1);

            pausable_unpause(&mut pausable, scenario.ctx());
            assert!(!pausable_is_paused(&pausable), 2);

            destroy(pausable);
        };

        scenario.end();
    }

    // Test witness type
    public struct PausableTest has drop {}
}
