/// @title NFT Attributes
/// @notice Dynamic and static attribute management for NFTs
/// @dev Part of @sui-starters/nft package
module sui_starters_nft::attributes {
    use std::string::String;
    use sui::event;
    use sui::vec_map::{Self, VecMap};

    // === Errors ===

    /// Attribute not found
    const EAttributeNotFound: u64 = 0;

    /// Attribute already exists
    const EAttributeExists: u64 = 1;

    /// Attributes are locked
    const EAttributesLocked: u64 = 2;

    /// Invalid attribute value
    const EInvalidValue: u64 = 3;

    // === Structs ===

    /// Typed attribute value
    public enum AttributeValue has copy, drop, store {
        String { value: String },
        U64 { value: u64 },
        Bool { value: bool },
        Address { value: address },
    }

    /// Attribute set using VecMap (ordered, small collections)
    public struct Attributes has store, copy, drop {
        /// String key -> String value (simple)
        data: VecMap<String, String>,
    }

    /// Typed attribute set
    public struct TypedAttributes has store, copy, drop {
        /// String key -> typed value
        data: VecMap<String, AttributeValue>,
    }

    /// Mutable attributes that can be locked
    public struct MutableAttributes has store, drop {
        /// Attribute data
        data: VecMap<String, String>,
        /// Is locked (no more changes)
        locked: bool,
    }

    /// Attribute with display info
    public struct DisplayAttribute has store, copy, drop {
        /// Attribute key
        key: String,
        /// Attribute value
        value: String,
        /// Display type (e.g., "string", "number", "boost_percentage")
        display_type: String,
    }

    /// Rich attributes for marketplaces
    public struct RichAttributes has store, drop {
        /// Display attributes
        attributes: vector<DisplayAttribute>,
        /// Is locked
        locked: bool,
    }

    // === Events ===

    /// Emitted when attribute is set
    public struct AttributeSet has copy, drop {
        key: String,
        value: String,
    }

    /// Emitted when attribute is removed
    public struct AttributeRemoved has copy, drop {
        key: String,
    }

    /// Emitted when attributes are locked
    public struct AttributesLocked has copy, drop {
        by: address,
    }

    // === Attributes Functions ===

    /// Create empty attributes
    public fun empty(): Attributes {
        Attributes {
            data: vec_map::empty(),
        }
    }

    /// Create attributes from vectors
    public fun from_vectors(keys: vector<String>, values: vector<String>): Attributes {
        let mut attrs = empty();
        let len = vector::length(&keys);
        let mut i = 0;
        while (i < len) {
            let key = *vector::borrow(&keys, i);
            let value = *vector::borrow(&values, i);
            vec_map::insert(&mut attrs.data, key, value);
            i = i + 1;
        };
        attrs
    }

    /// Set attribute (insert or update)
    public fun set(attrs: &mut Attributes, key: String, value: String) {
        if (vec_map::contains(&attrs.data, &key)) {
            let v = vec_map::get_mut(&mut attrs.data, &key);
            *v = value;
        } else {
            vec_map::insert(&mut attrs.data, key, value);
        };

        event::emit(AttributeSet { key, value });
    }

    /// Get attribute value
    public fun get(attrs: &Attributes, key: &String): String {
        assert!(vec_map::contains(&attrs.data, key), EAttributeNotFound);
        *vec_map::get(&attrs.data, key)
    }

    /// Get attribute value or default
    public fun get_or_default(attrs: &Attributes, key: &String, default: String): String {
        if (vec_map::contains(&attrs.data, key)) {
            *vec_map::get(&attrs.data, key)
        } else {
            default
        }
    }

    /// Check if attribute exists
    public fun contains(attrs: &Attributes, key: &String): bool {
        vec_map::contains(&attrs.data, key)
    }

    /// Remove attribute
    public fun remove(attrs: &mut Attributes, key: &String) {
        assert!(vec_map::contains(&attrs.data, key), EAttributeNotFound);
        vec_map::remove(&mut attrs.data, key);

        event::emit(AttributeRemoved { key: *key });
    }

    /// Get number of attributes
    public fun size(attrs: &Attributes): u64 {
        vec_map::length(&attrs.data)
    }

    /// Check if empty
    public fun is_empty(attrs: &Attributes): bool {
        vec_map::is_empty(&attrs.data)
    }

    /// Get all keys
    public fun keys(attrs: &Attributes): vector<String> {
        vec_map::keys(&attrs.data)
    }

    // === TypedAttributes Functions ===

    /// Create empty typed attributes
    public fun typed_empty(): TypedAttributes {
        TypedAttributes {
            data: vec_map::empty(),
        }
    }

    /// Set string attribute
    public fun set_string(attrs: &mut TypedAttributes, key: String, value: String) {
        let attr_value = AttributeValue::String { value };
        if (vec_map::contains(&attrs.data, &key)) {
            let v = vec_map::get_mut(&mut attrs.data, &key);
            *v = attr_value;
        } else {
            vec_map::insert(&mut attrs.data, key, attr_value);
        };
    }

    /// Set u64 attribute
    public fun set_u64(attrs: &mut TypedAttributes, key: String, value: u64) {
        let attr_value = AttributeValue::U64 { value };
        if (vec_map::contains(&attrs.data, &key)) {
            let v = vec_map::get_mut(&mut attrs.data, &key);
            *v = attr_value;
        } else {
            vec_map::insert(&mut attrs.data, key, attr_value);
        };
    }

    /// Set bool attribute
    public fun set_bool(attrs: &mut TypedAttributes, key: String, value: bool) {
        let attr_value = AttributeValue::Bool { value };
        if (vec_map::contains(&attrs.data, &key)) {
            let v = vec_map::get_mut(&mut attrs.data, &key);
            *v = attr_value;
        } else {
            vec_map::insert(&mut attrs.data, key, attr_value);
        };
    }

    /// Set address attribute
    public fun set_address(attrs: &mut TypedAttributes, key: String, value: address) {
        let attr_value = AttributeValue::Address { value };
        if (vec_map::contains(&attrs.data, &key)) {
            let v = vec_map::get_mut(&mut attrs.data, &key);
            *v = attr_value;
        } else {
            vec_map::insert(&mut attrs.data, key, attr_value);
        };
    }

    /// Get typed attribute
    public fun get_typed(attrs: &TypedAttributes, key: &String): AttributeValue {
        assert!(vec_map::contains(&attrs.data, key), EAttributeNotFound);
        *vec_map::get(&attrs.data, key)
    }

    /// Get string value
    public fun get_string_value(attrs: &TypedAttributes, key: &String): String {
        let attr = get_typed(attrs, key);
        match (attr) {
            AttributeValue::String { value } => value,
            _ => abort EInvalidValue
        }
    }

    /// Get u64 value
    public fun get_u64_value(attrs: &TypedAttributes, key: &String): u64 {
        let attr = get_typed(attrs, key);
        match (attr) {
            AttributeValue::U64 { value } => value,
            _ => abort EInvalidValue
        }
    }

    /// Get bool value
    public fun get_bool_value(attrs: &TypedAttributes, key: &String): bool {
        let attr = get_typed(attrs, key);
        match (attr) {
            AttributeValue::Bool { value } => value,
            _ => abort EInvalidValue
        }
    }

    /// Check if typed attribute exists
    public fun typed_contains(attrs: &TypedAttributes, key: &String): bool {
        vec_map::contains(&attrs.data, key)
    }

    /// Get typed attributes size
    public fun typed_size(attrs: &TypedAttributes): u64 {
        vec_map::length(&attrs.data)
    }

    // === MutableAttributes Functions ===

    /// Create mutable attributes
    public fun mutable_empty(): MutableAttributes {
        MutableAttributes {
            data: vec_map::empty(),
            locked: false,
        }
    }

    /// Set mutable attribute
    public fun mutable_set(attrs: &mut MutableAttributes, key: String, value: String) {
        assert!(!attrs.locked, EAttributesLocked);

        if (vec_map::contains(&attrs.data, &key)) {
            let v = vec_map::get_mut(&mut attrs.data, &key);
            *v = value;
        } else {
            vec_map::insert(&mut attrs.data, key, value);
        };
    }

    /// Get mutable attribute
    public fun mutable_get(attrs: &MutableAttributes, key: &String): String {
        assert!(vec_map::contains(&attrs.data, key), EAttributeNotFound);
        *vec_map::get(&attrs.data, key)
    }

    /// Lock mutable attributes
    public fun mutable_lock(attrs: &mut MutableAttributes, ctx: &TxContext) {
        assert!(!attrs.locked, EAttributesLocked);
        attrs.locked = true;

        event::emit(AttributesLocked {
            by: ctx.sender(),
        });
    }

    /// Check if mutable attributes are locked
    public fun mutable_is_locked(attrs: &MutableAttributes): bool {
        attrs.locked
    }

    /// Get mutable attributes size
    public fun mutable_size(attrs: &MutableAttributes): u64 {
        vec_map::length(&attrs.data)
    }

    // === RichAttributes Functions ===

    /// Create empty rich attributes
    public fun rich_empty(): RichAttributes {
        RichAttributes {
            attributes: vector[],
            locked: false,
        }
    }

    /// Add rich attribute
    public fun rich_add(
        attrs: &mut RichAttributes,
        key: String,
        value: String,
        display_type: String,
    ) {
        assert!(!attrs.locked, EAttributesLocked);

        let attr = DisplayAttribute { key, value, display_type };
        vector::push_back(&mut attrs.attributes, attr);
    }

    /// Add string attribute
    public fun rich_add_string(attrs: &mut RichAttributes, key: String, value: String) {
        rich_add(attrs, key, value, std::string::utf8(b"string"));
    }

    /// Add number attribute
    public fun rich_add_number(attrs: &mut RichAttributes, key: String, value: String) {
        rich_add(attrs, key, value, std::string::utf8(b"number"));
    }

    /// Add boost percentage attribute
    public fun rich_add_boost_percentage(attrs: &mut RichAttributes, key: String, value: String) {
        rich_add(attrs, key, value, std::string::utf8(b"boost_percentage"));
    }

    /// Add boost number attribute
    public fun rich_add_boost_number(attrs: &mut RichAttributes, key: String, value: String) {
        rich_add(attrs, key, value, std::string::utf8(b"boost_number"));
    }

    /// Get rich attribute at index
    public fun rich_get_at(attrs: &RichAttributes, index: u64): DisplayAttribute {
        *vector::borrow(&attrs.attributes, index)
    }

    /// Get rich attributes count
    public fun rich_size(attrs: &RichAttributes): u64 {
        vector::length(&attrs.attributes)
    }

    /// Lock rich attributes
    public fun rich_lock(attrs: &mut RichAttributes, ctx: &TxContext) {
        assert!(!attrs.locked, EAttributesLocked);
        attrs.locked = true;

        event::emit(AttributesLocked {
            by: ctx.sender(),
        });
    }

    /// Check if rich attributes are locked
    public fun rich_is_locked(attrs: &RichAttributes): bool {
        attrs.locked
    }

    /// Get all display attributes
    public fun rich_all(attrs: &RichAttributes): vector<DisplayAttribute> {
        attrs.attributes
    }

    // === DisplayAttribute Accessors ===

    /// Get display attribute key
    public fun display_key(attr: &DisplayAttribute): String {
        attr.key
    }

    /// Get display attribute value
    public fun display_value(attr: &DisplayAttribute): String {
        attr.value
    }

    /// Get display attribute type
    public fun display_type(attr: &DisplayAttribute): String {
        attr.display_type
    }

    // === Tests ===

    #[test]
    fun test_attributes_basic() {
        use std::string;

        let mut attrs = empty();
        assert!(is_empty(&attrs), 0);

        let key = string::utf8(b"color");
        let value = string::utf8(b"blue");

        set(&mut attrs, key, value);
        assert!(size(&attrs) == 1, 1);
        assert!(contains(&attrs, &key), 2);
        assert!(get(&attrs, &key) == value, 3);
    }

    #[test]
    fun test_attributes_from_vectors() {
        use std::string;

        let keys = vector[
            string::utf8(b"color"),
            string::utf8(b"size"),
            string::utf8(b"rarity"),
        ];
        let values = vector[
            string::utf8(b"blue"),
            string::utf8(b"large"),
            string::utf8(b"rare"),
        ];

        let attrs = from_vectors(keys, values);
        assert!(size(&attrs) == 3, 0);
        assert!(get(&attrs, &string::utf8(b"color")) == string::utf8(b"blue"), 1);
        assert!(get(&attrs, &string::utf8(b"rarity")) == string::utf8(b"rare"), 2);
    }

    #[test]
    fun test_attributes_update() {
        use std::string;

        let mut attrs = empty();
        let key = string::utf8(b"level");

        set(&mut attrs, key, string::utf8(b"1"));
        assert!(get(&attrs, &key) == string::utf8(b"1"), 0);

        set(&mut attrs, key, string::utf8(b"2"));
        assert!(get(&attrs, &key) == string::utf8(b"2"), 1);
        assert!(size(&attrs) == 1, 2); // Still only one attribute
    }

    #[test]
    fun test_attributes_remove() {
        use std::string;

        let mut attrs = empty();
        let key = string::utf8(b"temp");

        set(&mut attrs, key, string::utf8(b"value"));
        assert!(contains(&attrs, &key), 0);

        remove(&mut attrs, &key);
        assert!(!contains(&attrs, &key), 1);
        assert!(is_empty(&attrs), 2);
    }

    #[test]
    fun test_get_or_default() {
        use std::string;

        let attrs = empty();
        let key = string::utf8(b"missing");
        let default = string::utf8(b"default_value");

        let value = get_or_default(&attrs, &key, default);
        assert!(value == default, 0);
    }

    #[test]
    fun test_typed_attributes() {
        use std::string;

        let mut attrs = typed_empty();

        set_string(&mut attrs, string::utf8(b"name"), string::utf8(b"Dragon"));
        set_u64(&mut attrs, string::utf8(b"level"), 50);
        set_bool(&mut attrs, string::utf8(b"legendary"), true);

        assert!(typed_size(&attrs) == 3, 0);
        assert!(get_string_value(&attrs, &string::utf8(b"name")) == string::utf8(b"Dragon"), 1);
        assert!(get_u64_value(&attrs, &string::utf8(b"level")) == 50, 2);
        assert!(get_bool_value(&attrs, &string::utf8(b"legendary")) == true, 3);
    }

    #[test]
    fun test_mutable_attributes() {
        use sui::test_scenario;
        use std::string;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut attrs = mutable_empty();
            assert!(!mutable_is_locked(&attrs), 0);

            mutable_set(&mut attrs, string::utf8(b"key"), string::utf8(b"value"));
            assert!(mutable_size(&attrs) == 1, 1);

            mutable_lock(&mut attrs, scenario.ctx());
            assert!(mutable_is_locked(&attrs), 2);
        };

        scenario.end();
    }

    #[test]
    #[expected_failure(abort_code = EAttributesLocked)]
    fun test_mutable_locked_fails() {
        use sui::test_scenario;
        use std::string;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut attrs = mutable_empty();
            mutable_lock(&mut attrs, scenario.ctx());
            mutable_set(&mut attrs, string::utf8(b"key"), string::utf8(b"value")); // Should fail
        };

        scenario.end();
    }

    #[test]
    fun test_rich_attributes() {
        use sui::test_scenario;
        use std::string;

        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let mut attrs = rich_empty();

            rich_add_string(&mut attrs, string::utf8(b"Background"), string::utf8(b"Blue"));
            rich_add_number(&mut attrs, string::utf8(b"Level"), string::utf8(b"50"));
            rich_add_boost_percentage(&mut attrs, string::utf8(b"Power Boost"), string::utf8(b"10"));

            assert!(rich_size(&attrs) == 3, 0);

            let attr = rich_get_at(&attrs, 0);
            assert!(display_key(&attr) == string::utf8(b"Background"), 1);
            assert!(display_value(&attr) == string::utf8(b"Blue"), 2);
            assert!(display_type(&attr) == string::utf8(b"string"), 3);

            rich_lock(&mut attrs, scenario.ctx());
            assert!(rich_is_locked(&attrs), 4);
        };

        scenario.end();
    }

    #[test]
    fun test_keys() {
        use std::string;

        let mut attrs = empty();
        set(&mut attrs, string::utf8(b"a"), string::utf8(b"1"));
        set(&mut attrs, string::utf8(b"b"), string::utf8(b"2"));
        set(&mut attrs, string::utf8(b"c"), string::utf8(b"3"));

        let all_keys = keys(&attrs);
        assert!(vector::length(&all_keys) == 3, 0);
    }
}
