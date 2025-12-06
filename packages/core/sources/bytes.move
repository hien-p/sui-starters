/// @title Byte Utilities
/// @notice Byte manipulation and conversion utilities
/// @dev Part of @sui-starters/core package
module sui_starters_core::bytes {
    use std::vector;

    // === Errors ===

    /// Invalid length
    const EInvalidLength: u64 = 0;

    /// Index out of bounds
    const EOutOfBounds: u64 = 1;

    // === Conversion Functions ===

    /// Convert u64 to big-endian bytes (8 bytes)
    public fun u64_to_bytes(value: u64): vector<u8> {
        let mut result = vector::empty<u8>();
        let mut i = 0;
        while (i < 8) {
            let shift = (7 - i) * 8;
            vector::push_back(&mut result, ((value >> (shift as u8)) & 0xFF) as u8);
            i = i + 1;
        };
        result
    }

    /// Convert big-endian bytes to u64
    public fun bytes_to_u64(bytes: &vector<u8>): u64 {
        assert!(vector::length(bytes) >= 8, EInvalidLength);
        let mut result: u64 = 0;
        let mut i = 0;
        while (i < 8) {
            result = (result << 8) | (*vector::borrow(bytes, i) as u64);
            i = i + 1;
        };
        result
    }

    /// Convert u128 to big-endian bytes (16 bytes)
    public fun u128_to_bytes(value: u128): vector<u8> {
        let mut result = vector::empty<u8>();
        let mut i = 0;
        while (i < 16) {
            let shift = (15 - i) * 8;
            vector::push_back(&mut result, ((value >> (shift as u8)) & 0xFF) as u8);
            i = i + 1;
        };
        result
    }

    /// Convert big-endian bytes to u128
    public fun bytes_to_u128(bytes: &vector<u8>): u128 {
        assert!(vector::length(bytes) >= 16, EInvalidLength);
        let mut result: u128 = 0;
        let mut i = 0;
        while (i < 16) {
            result = (result << 8) | (*vector::borrow(bytes, i) as u128);
            i = i + 1;
        };
        result
    }

    /// Convert u256 to big-endian bytes (32 bytes)
    public fun u256_to_bytes(value: u256): vector<u8> {
        let mut result = vector::empty<u8>();
        let mut i = 0;
        while (i < 32) {
            let shift = (31 - i) * 8;
            vector::push_back(&mut result, ((value >> (shift as u8)) & 0xFF) as u8);
            i = i + 1;
        };
        result
    }

    /// Convert big-endian bytes to u256
    public fun bytes_to_u256(bytes: &vector<u8>): u256 {
        assert!(vector::length(bytes) >= 32, EInvalidLength);
        let mut result: u256 = 0;
        let mut i = 0;
        while (i < 32) {
            result = (result << 8) | (*vector::borrow(bytes, i) as u256);
            i = i + 1;
        };
        result
    }

    // === Manipulation Functions ===

    /// Concatenate two byte vectors
    public fun concat(a: &vector<u8>, b: &vector<u8>): vector<u8> {
        let mut result = *a;
        vector::append(&mut result, *b);
        result
    }

    /// Slice bytes from start to end (exclusive)
    public fun slice(bytes: &vector<u8>, start: u64, end: u64): vector<u8> {
        let len = vector::length(bytes);
        assert!(start <= end && end <= len, EOutOfBounds);

        let mut result = vector::empty<u8>();
        let mut i = start;
        while (i < end) {
            vector::push_back(&mut result, *vector::borrow(bytes, i));
            i = i + 1;
        };
        result
    }

    /// Pad bytes to target length with zeros (left padding)
    public fun pad_left(bytes: &vector<u8>, target_len: u64): vector<u8> {
        let len = vector::length(bytes);
        if (len >= target_len) {
            return *bytes
        };

        let mut result = vector::empty<u8>();
        let padding = target_len - len;
        let mut i = 0;
        while (i < padding) {
            vector::push_back(&mut result, 0);
            i = i + 1;
        };
        vector::append(&mut result, *bytes);
        result
    }

    /// Pad bytes to target length with zeros (right padding)
    public fun pad_right(bytes: &vector<u8>, target_len: u64): vector<u8> {
        let len = vector::length(bytes);
        if (len >= target_len) {
            return *bytes
        };

        let mut result = *bytes;
        let padding = target_len - len;
        let mut i = 0;
        while (i < padding) {
            vector::push_back(&mut result, 0);
            i = i + 1;
        };
        result
    }

    /// Reverse bytes
    public fun reverse(bytes: &vector<u8>): vector<u8> {
        let len = vector::length(bytes);
        let mut result = vector::empty<u8>();
        let mut i = len;
        while (i > 0) {
            i = i - 1;
            vector::push_back(&mut result, *vector::borrow(bytes, i));
        };
        result
    }

    /// XOR two byte vectors of equal length
    public fun xor(a: &vector<u8>, b: &vector<u8>): vector<u8> {
        let len = vector::length(a);
        assert!(len == vector::length(b), EInvalidLength);

        let mut result = vector::empty<u8>();
        let mut i = 0;
        while (i < len) {
            let byte_a = *vector::borrow(a, i);
            let byte_b = *vector::borrow(b, i);
            vector::push_back(&mut result, byte_a ^ byte_b);
            i = i + 1;
        };
        result
    }

    /// Check if bytes are all zeros
    public fun is_zero(bytes: &vector<u8>): bool {
        let len = vector::length(bytes);
        let mut i = 0;
        while (i < len) {
            if (*vector::borrow(bytes, i) != 0) {
                return false
            };
            i = i + 1;
        };
        true
    }

    /// Compare two byte vectors
    public fun compare(a: &vector<u8>, b: &vector<u8>): u8 {
        let len_a = vector::length(a);
        let len_b = vector::length(b);
        let min_len = if (len_a < len_b) { len_a } else { len_b };

        let mut i = 0;
        while (i < min_len) {
            let byte_a = *vector::borrow(a, i);
            let byte_b = *vector::borrow(b, i);
            if (byte_a < byte_b) {
                return 1 // a < b
            };
            if (byte_a > byte_b) {
                return 2 // a > b
            };
            i = i + 1;
        };

        if (len_a < len_b) {
            1 // a < b
        } else if (len_a > len_b) {
            2 // a > b
        } else {
            0 // equal
        }
    }

    // === Tests ===

    #[test]
    fun test_u64_conversion() {
        let value: u64 = 0x0102030405060708;
        let bytes = u64_to_bytes(value);
        assert!(vector::length(&bytes) == 8, 0);
        assert!(*vector::borrow(&bytes, 0) == 0x01, 1);
        assert!(*vector::borrow(&bytes, 7) == 0x08, 2);

        let restored = bytes_to_u64(&bytes);
        assert!(restored == value, 3);
    }

    #[test]
    fun test_u128_conversion() {
        let value: u128 = 0x0102030405060708090A0B0C0D0E0F10;
        let bytes = u128_to_bytes(value);
        assert!(vector::length(&bytes) == 16, 0);

        let restored = bytes_to_u128(&bytes);
        assert!(restored == value, 1);
    }

    #[test]
    fun test_concat() {
        let a = vector[1u8, 2, 3];
        let b = vector[4u8, 5, 6];
        let result = concat(&a, &b);
        assert!(vector::length(&result) == 6, 0);
        assert!(*vector::borrow(&result, 0) == 1, 1);
        assert!(*vector::borrow(&result, 5) == 6, 2);
    }

    #[test]
    fun test_slice() {
        let bytes = vector[1u8, 2, 3, 4, 5];
        let sliced = slice(&bytes, 1, 4);
        assert!(vector::length(&sliced) == 3, 0);
        assert!(*vector::borrow(&sliced, 0) == 2, 1);
        assert!(*vector::borrow(&sliced, 2) == 4, 2);
    }

    #[test]
    fun test_pad_left() {
        let bytes = vector[1u8, 2, 3];
        let padded = pad_left(&bytes, 5);
        assert!(vector::length(&padded) == 5, 0);
        assert!(*vector::borrow(&padded, 0) == 0, 1);
        assert!(*vector::borrow(&padded, 1) == 0, 2);
        assert!(*vector::borrow(&padded, 2) == 1, 3);
    }

    #[test]
    fun test_reverse() {
        let bytes = vector[1u8, 2, 3, 4];
        let reversed = reverse(&bytes);
        assert!(*vector::borrow(&reversed, 0) == 4, 0);
        assert!(*vector::borrow(&reversed, 3) == 1, 1);
    }

    #[test]
    fun test_xor() {
        let a = vector[0xFFu8, 0x00, 0xAA];
        let b = vector[0xFFu8, 0xFF, 0x55];
        let result = xor(&a, &b);
        assert!(*vector::borrow(&result, 0) == 0x00, 0);
        assert!(*vector::borrow(&result, 1) == 0xFF, 1);
        assert!(*vector::borrow(&result, 2) == 0xFF, 2);
    }

    #[test]
    fun test_is_zero() {
        let zeros = vector[0u8, 0, 0];
        assert!(is_zero(&zeros), 0);

        let non_zeros = vector[0u8, 1, 0];
        assert!(!is_zero(&non_zeros), 1);
    }

    #[test]
    fun test_compare() {
        let a = vector[1u8, 2, 3];
        let b = vector[1u8, 2, 4];
        let c = vector[1u8, 2, 3];

        assert!(compare(&a, &b) == 1, 0); // a < b
        assert!(compare(&b, &a) == 2, 1); // b > a
        assert!(compare(&a, &c) == 0, 2); // a == c
    }
}
