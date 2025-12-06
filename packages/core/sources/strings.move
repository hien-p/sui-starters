/// @title String utilities for Sui Move
/// @notice String manipulation functions including concat, conversion, and search
/// @dev Part of @sui-starters/core package
module sui_starters_core::strings {
    use std::string::{Self, String};

    // === Errors ===

    /// Index out of bounds
    const EIndexOutOfBounds: u64 = 0;

    /// Empty string error
    const EEmptyString: u64 = 1;

    // === String Concatenation ===

    /// Concatenate two strings
    public fun concat(a: String, b: String): String {
        let mut bytes = *string::as_bytes(&a);
        vector::append(&mut bytes, *string::as_bytes(&b));
        string::utf8(bytes)
    }

    /// Concatenate multiple strings
    public fun concat_all(strings: vector<String>): String {
        let mut result: vector<u8> = vector[];
        let len = vector::length(&strings);
        let mut i = 0;

        while (i < len) {
            let s = vector::borrow(&strings, i);
            vector::append(&mut result, *string::as_bytes(s));
            i = i + 1;
        };

        string::utf8(result)
    }

    /// Concatenate with separator
    public fun join(strings: vector<String>, separator: String): String {
        let len = vector::length(&strings);
        if (len == 0) {
            return string::utf8(vector[])
        };

        let mut result: vector<u8> = vector[];
        let sep_bytes = string::as_bytes(&separator);
        let mut i = 0;

        while (i < len) {
            if (i > 0) {
                vector::append(&mut result, *sep_bytes);
            };
            let s = vector::borrow(&strings, i);
            vector::append(&mut result, *string::as_bytes(s));
            i = i + 1;
        };

        string::utf8(result)
    }

    // === Number to String Conversion ===

    /// Convert u64 to string
    public fun to_string_u64(value: u64): String {
        if (value == 0) {
            return string::utf8(b"0")
        };

        let mut buffer: vector<u8> = vector[];
        let mut n = value;

        while (n > 0) {
            let digit = ((n % 10) as u8) + 48; // 48 is ASCII '0'
            vector::push_back(&mut buffer, digit);
            n = n / 10;
        };

        vector::reverse(&mut buffer);
        string::utf8(buffer)
    }

    /// Convert u128 to string
    public fun to_string_u128(value: u128): String {
        if (value == 0) {
            return string::utf8(b"0")
        };

        let mut buffer: vector<u8> = vector[];
        let mut n = value;

        while (n > 0) {
            let digit = ((n % 10) as u8) + 48;
            vector::push_back(&mut buffer, digit);
            n = n / 10;
        };

        vector::reverse(&mut buffer);
        string::utf8(buffer)
    }

    /// Convert address to hex string (without 0x prefix)
    public fun address_to_hex(addr: address): String {
        let bytes = std::bcs::to_bytes(&addr);
        bytes_to_hex(bytes)
    }

    /// Convert bytes to hex string
    public fun bytes_to_hex(bytes: vector<u8>): String {
        let hex_chars = b"0123456789abcdef";
        let mut result: vector<u8> = vector[];
        let len = vector::length(&bytes);
        let mut i = 0;

        while (i < len) {
            let byte = *vector::borrow(&bytes, i);
            let high = (byte >> 4) & 0x0f;
            let low = byte & 0x0f;
            vector::push_back(&mut result, *vector::borrow(&hex_chars, (high as u64)));
            vector::push_back(&mut result, *vector::borrow(&hex_chars, (low as u64)));
            i = i + 1;
        };

        string::utf8(result)
    }

    // === String Search ===

    /// Check if string starts with prefix
    public fun starts_with(s: &String, prefix: &String): bool {
        let s_bytes = string::as_bytes(s);
        let p_bytes = string::as_bytes(prefix);
        let s_len = vector::length(s_bytes);
        let p_len = vector::length(p_bytes);

        if (p_len > s_len) {
            return false
        };

        let mut i = 0;
        while (i < p_len) {
            if (*vector::borrow(s_bytes, i) != *vector::borrow(p_bytes, i)) {
                return false
            };
            i = i + 1;
        };

        true
    }

    /// Check if string ends with suffix
    public fun ends_with(s: &String, suffix: &String): bool {
        let s_bytes = string::as_bytes(s);
        let suf_bytes = string::as_bytes(suffix);
        let s_len = vector::length(s_bytes);
        let suf_len = vector::length(suf_bytes);

        if (suf_len > s_len) {
            return false
        };

        let offset = s_len - suf_len;
        let mut i = 0;
        while (i < suf_len) {
            if (*vector::borrow(s_bytes, offset + i) != *vector::borrow(suf_bytes, i)) {
                return false
            };
            i = i + 1;
        };

        true
    }

    /// Check if string contains substring
    public fun contains(s: &String, substr: &String): bool {
        index_of(s, substr) != vector::length(string::as_bytes(s)) + 1
    }

    /// Find index of substring (returns length + 1 if not found)
    public fun index_of(s: &String, substr: &String): u64 {
        let s_bytes = string::as_bytes(s);
        let sub_bytes = string::as_bytes(substr);
        let s_len = vector::length(s_bytes);
        let sub_len = vector::length(sub_bytes);

        if (sub_len == 0) {
            return 0
        };

        if (sub_len > s_len) {
            return s_len + 1
        };

        let mut i = 0;
        while (i <= s_len - sub_len) {
            let mut found = true;
            let mut j = 0;
            while (j < sub_len) {
                if (*vector::borrow(s_bytes, i + j) != *vector::borrow(sub_bytes, j)) {
                    found = false;
                    break
                };
                j = j + 1;
            };
            if (found) {
                return i
            };
            i = i + 1;
        };

        s_len + 1
    }

    // === String Properties ===

    /// Get string length (number of bytes)
    public fun length(s: &String): u64 {
        vector::length(string::as_bytes(s))
    }

    /// Check if string is empty
    public fun is_empty(s: &String): bool {
        vector::length(string::as_bytes(s)) == 0
    }

    // === String Manipulation ===

    /// Get substring from start to end (exclusive)
    public fun substring(s: &String, start: u64, end: u64): String {
        let bytes = string::as_bytes(s);
        let len = vector::length(bytes);

        assert!(start <= end, EIndexOutOfBounds);
        assert!(end <= len, EIndexOutOfBounds);

        let mut result: vector<u8> = vector[];
        let mut i = start;
        while (i < end) {
            vector::push_back(&mut result, *vector::borrow(bytes, i));
            i = i + 1;
        };

        string::utf8(result)
    }

    /// Repeat string n times
    public fun repeat(s: &String, n: u64): String {
        let mut result: vector<u8> = vector[];
        let bytes = string::as_bytes(s);
        let mut i = 0;

        while (i < n) {
            vector::append(&mut result, *bytes);
            i = i + 1;
        };

        string::utf8(result)
    }

    /// Pad string on the left to reach target length
    public fun pad_left(s: String, target_len: u64, pad_char: u8): String {
        let current_len = length(&s);
        if (current_len >= target_len) {
            return s
        };

        let mut result: vector<u8> = vector[];
        let pad_count = target_len - current_len;
        let mut i = 0;

        while (i < pad_count) {
            vector::push_back(&mut result, pad_char);
            i = i + 1;
        };

        vector::append(&mut result, *string::as_bytes(&s));
        string::utf8(result)
    }

    /// Pad string on the right to reach target length
    public fun pad_right(s: String, target_len: u64, pad_char: u8): String {
        let current_len = length(&s);
        if (current_len >= target_len) {
            return s
        };

        let mut result = *string::as_bytes(&s);
        let pad_count = target_len - current_len;
        let mut i = 0;

        while (i < pad_count) {
            vector::push_back(&mut result, pad_char);
            i = i + 1;
        };

        string::utf8(result)
    }

    // === Tests ===

    #[test]
    fun test_concat() {
        let a = string::utf8(b"Hello");
        let b = string::utf8(b" World");
        let result = concat(a, b);
        assert!(result == string::utf8(b"Hello World"), 0);
    }

    #[test]
    fun test_concat_all() {
        let strings = vector[
            string::utf8(b"a"),
            string::utf8(b"b"),
            string::utf8(b"c")
        ];
        let result = concat_all(strings);
        assert!(result == string::utf8(b"abc"), 0);
    }

    #[test]
    fun test_join() {
        let strings = vector[
            string::utf8(b"a"),
            string::utf8(b"b"),
            string::utf8(b"c")
        ];
        let result = join(strings, string::utf8(b", "));
        assert!(result == string::utf8(b"a, b, c"), 0);
    }

    #[test]
    fun test_to_string_u64() {
        assert!(to_string_u64(0) == string::utf8(b"0"), 0);
        assert!(to_string_u64(123) == string::utf8(b"123"), 1);
        assert!(to_string_u64(1000000) == string::utf8(b"1000000"), 2);
    }

    #[test]
    fun test_starts_with() {
        let s = string::utf8(b"Hello World");
        let prefix = string::utf8(b"Hello");
        let wrong = string::utf8(b"World");
        assert!(starts_with(&s, &prefix) == true, 0);
        assert!(starts_with(&s, &wrong) == false, 1);
    }

    #[test]
    fun test_ends_with() {
        let s = string::utf8(b"Hello World");
        let suffix = string::utf8(b"World");
        let wrong = string::utf8(b"Hello");
        assert!(ends_with(&s, &suffix) == true, 0);
        assert!(ends_with(&s, &wrong) == false, 1);
    }

    #[test]
    fun test_contains() {
        let s = string::utf8(b"Hello World");
        let substr = string::utf8(b"lo Wo");
        let wrong = string::utf8(b"xyz");
        assert!(contains(&s, &substr) == true, 0);
        assert!(contains(&s, &wrong) == false, 1);
    }

    #[test]
    fun test_substring() {
        let s = string::utf8(b"Hello World");
        let sub = substring(&s, 0, 5);
        assert!(sub == string::utf8(b"Hello"), 0);
    }

    #[test]
    fun test_repeat() {
        let s = string::utf8(b"ab");
        let result = repeat(&s, 3);
        assert!(result == string::utf8(b"ababab"), 0);
    }

    #[test]
    fun test_pad_left() {
        let s = string::utf8(b"42");
        let result = pad_left(s, 5, 48); // 48 = '0'
        assert!(result == string::utf8(b"00042"), 0);
    }

    #[test]
    fun test_pad_right() {
        let s = string::utf8(b"42");
        let result = pad_right(s, 5, 48);
        assert!(result == string::utf8(b"42000"), 0);
    }
}
