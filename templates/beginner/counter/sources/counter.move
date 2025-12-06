/// @title Counter
/// @notice A simple counter example - perfect for learning Sui Move basics
/// @dev Demonstrates shared objects, entry functions, and basic state management
module counter::counter {
    use sui::event;

    // === Structs ===

    /// A shared counter that anyone can increment
    public struct Counter has key {
        id: UID,
        /// Current count value
        value: u64,
        /// Owner who created the counter
        owner: address,
    }

    // === Events ===

    public struct CounterCreated has copy, drop {
        counter_id: ID,
        owner: address,
    }

    public struct CounterIncremented has copy, drop {
        counter_id: ID,
        new_value: u64,
        by: address,
    }

    public struct CounterDecremented has copy, drop {
        counter_id: ID,
        new_value: u64,
        by: address,
    }

    public struct CounterReset has copy, drop {
        counter_id: ID,
        by: address,
    }

    // === Entry Functions ===

    /// Create a new shared counter
    public entry fun create(ctx: &mut TxContext) {
        let counter = Counter {
            id: object::new(ctx),
            value: 0,
            owner: ctx.sender(),
        };

        event::emit(CounterCreated {
            counter_id: object::id(&counter),
            owner: ctx.sender(),
        });

        transfer::share_object(counter);
    }

    /// Increment the counter by 1
    public entry fun increment(counter: &mut Counter, ctx: &TxContext) {
        counter.value = counter.value + 1;

        event::emit(CounterIncremented {
            counter_id: object::id(counter),
            new_value: counter.value,
            by: ctx.sender(),
        });
    }

    /// Increment the counter by a specific amount
    public entry fun increment_by(counter: &mut Counter, amount: u64, ctx: &TxContext) {
        counter.value = counter.value + amount;

        event::emit(CounterIncremented {
            counter_id: object::id(counter),
            new_value: counter.value,
            by: ctx.sender(),
        });
    }

    /// Decrement the counter by 1 (only if value > 0)
    public entry fun decrement(counter: &mut Counter, ctx: &TxContext) {
        assert!(counter.value > 0, 0);
        counter.value = counter.value - 1;

        event::emit(CounterDecremented {
            counter_id: object::id(counter),
            new_value: counter.value,
            by: ctx.sender(),
        });
    }

    /// Reset counter to 0 (only owner can reset)
    public entry fun reset(counter: &mut Counter, ctx: &TxContext) {
        assert!(counter.owner == ctx.sender(), 1);
        counter.value = 0;

        event::emit(CounterReset {
            counter_id: object::id(counter),
            by: ctx.sender(),
        });
    }

    // === View Functions ===

    /// Get current counter value
    public fun value(counter: &Counter): u64 {
        counter.value
    }

    /// Get counter owner
    public fun owner(counter: &Counter): address {
        counter.owner
    }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;

    #[test]
    fun test_create_counter() {
        let owner = @0x1;
        let mut scenario = test_scenario::begin(owner);

        {
            create(scenario.ctx());
        };

        scenario.next_tx(owner);
        {
            let counter = scenario.take_shared<Counter>();
            assert!(value(&counter) == 0, 0);
            assert!(owner(&counter) == owner, 1);
            test_scenario::return_shared(counter);
        };

        scenario.end();
    }

    #[test]
    fun test_increment() {
        let owner = @0x1;
        let user = @0x2;
        let mut scenario = test_scenario::begin(owner);

        // Create counter
        {
            create(scenario.ctx());
        };

        // User increments
        scenario.next_tx(user);
        {
            let mut counter = scenario.take_shared<Counter>();
            increment(&mut counter, scenario.ctx());
            assert!(value(&counter) == 1, 0);
            test_scenario::return_shared(counter);
        };

        // Increment again
        scenario.next_tx(user);
        {
            let mut counter = scenario.take_shared<Counter>();
            increment(&mut counter, scenario.ctx());
            assert!(value(&counter) == 2, 1);
            test_scenario::return_shared(counter);
        };

        scenario.end();
    }

    #[test]
    fun test_increment_by() {
        let owner = @0x1;
        let mut scenario = test_scenario::begin(owner);

        {
            create(scenario.ctx());
        };

        scenario.next_tx(owner);
        {
            let mut counter = scenario.take_shared<Counter>();
            increment_by(&mut counter, 5, scenario.ctx());
            assert!(value(&counter) == 5, 0);
            test_scenario::return_shared(counter);
        };

        scenario.end();
    }

    #[test]
    fun test_decrement() {
        let owner = @0x1;
        let mut scenario = test_scenario::begin(owner);

        {
            create(scenario.ctx());
        };

        scenario.next_tx(owner);
        {
            let mut counter = scenario.take_shared<Counter>();
            increment_by(&mut counter, 5, scenario.ctx());
            decrement(&mut counter, scenario.ctx());
            assert!(value(&counter) == 4, 0);
            test_scenario::return_shared(counter);
        };

        scenario.end();
    }

    #[test]
    fun test_reset() {
        let owner = @0x1;
        let mut scenario = test_scenario::begin(owner);

        {
            create(scenario.ctx());
        };

        scenario.next_tx(owner);
        {
            let mut counter = scenario.take_shared<Counter>();
            increment_by(&mut counter, 100, scenario.ctx());
            reset(&mut counter, scenario.ctx());
            assert!(value(&counter) == 0, 0);
            test_scenario::return_shared(counter);
        };

        scenario.end();
    }
}
