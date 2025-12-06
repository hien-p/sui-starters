/// @title Event Emitter Helpers
/// @notice Helper functions for common event emission patterns
/// @dev Part of @sui-starters/events package
module sui_starters_events::emitter {
    use std::string::String;
    use std::type_name::{Self, TypeName};
    use sui::event;
    use sui::clock::Clock;

    // === Simple Events ===

    /// Simple log event (for debugging/tracking)
    public struct LogEvent has copy, drop {
        message: String,
        timestamp: u64,
    }

    /// Key-value event
    public struct KeyValueEvent has copy, drop {
        key: String,
        value: String,
        timestamp: u64,
    }

    /// Numeric event
    public struct NumericEvent has copy, drop {
        name: String,
        value: u64,
        timestamp: u64,
    }

    /// Address event
    public struct AddressEvent has copy, drop {
        name: String,
        addr: address,
        timestamp: u64,
    }

    /// ID event
    public struct IDEvent has copy, drop {
        name: String,
        id: ID,
        timestamp: u64,
    }

    // === Lifecycle Events ===

    /// Object created event
    public struct ObjectCreatedEvent has copy, drop {
        object_id: ID,
        object_type: TypeName,
        creator: address,
        timestamp: u64,
    }

    /// Object destroyed event
    public struct ObjectDestroyedEvent has copy, drop {
        object_id: ID,
        object_type: TypeName,
        destroyer: address,
        timestamp: u64,
    }

    /// Object updated event
    public struct ObjectUpdatedEvent has copy, drop {
        object_id: ID,
        object_type: TypeName,
        updater: address,
        field: String,
        timestamp: u64,
    }

    // === State Change Events ===

    /// State changed event
    public struct StateChangedEvent has copy, drop {
        object_id: ID,
        previous_state: u8,
        new_state: u8,
        changer: address,
        timestamp: u64,
    }

    /// Flag toggled event
    public struct FlagToggledEvent has copy, drop {
        object_id: ID,
        flag_name: String,
        new_value: bool,
        toggler: address,
        timestamp: u64,
    }

    // === Emit Functions ===

    /// Emit a simple log event
    public fun log(message: String, clock: &Clock) {
        event::emit(LogEvent {
            message,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Emit a log event with manual timestamp
    public fun log_with_timestamp(message: String, timestamp: u64) {
        event::emit(LogEvent {
            message,
            timestamp,
        });
    }

    /// Emit a key-value event
    public fun emit_kv(key: String, value: String, clock: &Clock) {
        event::emit(KeyValueEvent {
            key,
            value,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Emit a numeric event
    public fun emit_numeric(name: String, value: u64, clock: &Clock) {
        event::emit(NumericEvent {
            name,
            value,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Emit an address event
    public fun emit_address(name: String, addr: address, clock: &Clock) {
        event::emit(AddressEvent {
            name,
            addr,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Emit an ID event
    public fun emit_id(name: String, id: ID, clock: &Clock) {
        event::emit(IDEvent {
            name,
            id,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Emit object created event
    public fun emit_created<T>(
        object_id: ID,
        creator: address,
        clock: &Clock,
    ) {
        event::emit(ObjectCreatedEvent {
            object_id,
            object_type: type_name::get<T>(),
            creator,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Emit object created event with manual timestamp
    public fun emit_created_with_timestamp<T>(
        object_id: ID,
        creator: address,
        timestamp: u64,
    ) {
        event::emit(ObjectCreatedEvent {
            object_id,
            object_type: type_name::get<T>(),
            creator,
            timestamp,
        });
    }

    /// Emit object destroyed event
    public fun emit_destroyed<T>(
        object_id: ID,
        destroyer: address,
        clock: &Clock,
    ) {
        event::emit(ObjectDestroyedEvent {
            object_id,
            object_type: type_name::get<T>(),
            destroyer,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Emit object updated event
    public fun emit_updated<T>(
        object_id: ID,
        updater: address,
        field: String,
        clock: &Clock,
    ) {
        event::emit(ObjectUpdatedEvent {
            object_id,
            object_type: type_name::get<T>(),
            updater,
            field,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Emit state changed event
    public fun emit_state_changed(
        object_id: ID,
        previous_state: u8,
        new_state: u8,
        changer: address,
        clock: &Clock,
    ) {
        event::emit(StateChangedEvent {
            object_id,
            previous_state,
            new_state,
            changer,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    /// Emit flag toggled event
    public fun emit_flag_toggled(
        object_id: ID,
        flag_name: String,
        new_value: bool,
        toggler: address,
        clock: &Clock,
    ) {
        event::emit(FlagToggledEvent {
            object_id,
            flag_name,
            new_value,
            toggler,
            timestamp: sui::clock::timestamp_ms(clock),
        });
    }

    // === Batch Emit Functions ===

    /// Emit multiple log events
    public fun log_batch(messages: vector<String>, clock: &Clock) {
        let timestamp = sui::clock::timestamp_ms(clock);
        let len = vector::length(&messages);
        let mut i = 0;
        while (i < len) {
            event::emit(LogEvent {
                message: *vector::borrow(&messages, i),
                timestamp,
            });
            i = i + 1;
        };
    }

    // === Type Helpers ===

    /// Get type name for event emission
    public fun get_type<T>(): TypeName {
        type_name::get<T>()
    }

    /// Get type name as ascii string
    public fun get_type_ascii<T>(): std::ascii::String {
        type_name::into_string(type_name::get<T>())
    }

    // === Tests ===

    #[test]
    fun test_log_with_timestamp() {
        use std::string;

        log_with_timestamp(string::utf8(b"Test log message"), 1000);
    }

    #[test]
    fun test_emit_created_with_timestamp() {
        emit_created_with_timestamp<u64>(
            object::id_from_address(@0x123),
            @0x1,
            1000,
        );
    }

    #[test]
    fun test_get_type() {
        let type_name = get_type<u64>();
        let type_ascii = get_type_ascii<u64>();
        assert!(std::type_name::into_string(type_name) == type_ascii, 0);
    }
}
