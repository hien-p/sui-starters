/// @title Vector utilities for Sui Move
/// @notice Vector manipulation functions including find, remove, deduplicate, slice
/// @dev Part of @sui-starters/core package
module sui_starters_core::vectors {
    use std::vector;
    use std::option::{Self, Option};

    // === Errors ===

    /// Index out of bounds
    const EIndexOutOfBounds: u64 = 0;

    /// Element not found
    const EElementNotFound: u64 = 1;

    /// Invalid range
    const EInvalidRange: u64 = 2;

    // === Search Functions ===

    /// Find index of element in vector
    /// @return Some(index) if found, None otherwise
    public fun find<T: copy + drop>(v: &vector<T>, elem: &T): Option<u64> {
        let len = vector::length(v);
        let mut i = 0;
        while (i < len) {
            if (vector::borrow(v, i) == elem) {
                return option::some(i)
            };
            i = i + 1;
        };
        option::none()
    }

    /// Check if vector contains element
    public fun contains<T: copy + drop>(v: &vector<T>, elem: &T): bool {
        option::is_some(&find(v, elem))
    }

    /// Count occurrences of element in vector
    public fun count<T: copy + drop>(v: &vector<T>, elem: &T): u64 {
        let len = vector::length(v);
        let mut count = 0;
        let mut i = 0;
        while (i < len) {
            if (vector::borrow(v, i) == elem) {
                count = count + 1;
            };
            i = i + 1;
        };
        count
    }

    // === Remove Functions ===

    /// Remove first occurrence of element from vector
    /// @return true if element was found and removed
    public fun remove_value<T: copy + drop>(v: &mut vector<T>, elem: &T): bool {
        let idx_opt = find(v, elem);
        if (option::is_some(&idx_opt)) {
            let idx = option::destroy_some(idx_opt);
            vector::remove(v, idx);
            true
        } else {
            false
        }
    }

    /// Remove all occurrences of element from vector
    /// @return number of elements removed
    public fun remove_all<T: copy + drop>(v: &mut vector<T>, elem: &T): u64 {
        let mut removed = 0;
        while (remove_value(v, elem)) {
            removed = removed + 1;
        };
        removed
    }

    /// Remove element at index and return it (swap with last element for O(1))
    public fun swap_remove<T>(v: &mut vector<T>, idx: u64): T {
        let len = vector::length(v);
        assert!(idx < len, EIndexOutOfBounds);
        vector::swap_remove(v, idx)
    }

    // === Deduplication ===

    /// Remove duplicate elements, keeping first occurrence
    public fun deduplicate<T: copy + drop>(v: &mut vector<T>) {
        let len = vector::length(v);
        if (len <= 1) {
            return
        };

        let mut i = 0;
        while (i < vector::length(v)) {
            let elem = *vector::borrow(v, i);
            let mut j = i + 1;
            while (j < vector::length(v)) {
                if (vector::borrow(v, j) == &elem) {
                    vector::remove(v, j);
                } else {
                    j = j + 1;
                };
            };
            i = i + 1;
        };
    }

    /// Check if vector has duplicates
    public fun has_duplicates<T: copy + drop>(v: &vector<T>): bool {
        let len = vector::length(v);
        let mut i = 0;
        while (i < len) {
            let mut j = i + 1;
            while (j < len) {
                if (vector::borrow(v, i) == vector::borrow(v, j)) {
                    return true
                };
                j = j + 1;
            };
            i = i + 1;
        };
        false
    }

    // === Slicing ===

    /// Get a slice of vector from start to end (exclusive)
    public fun slice<T: copy>(v: &vector<T>, start: u64, end: u64): vector<T> {
        let len = vector::length(v);
        assert!(start <= end, EInvalidRange);
        assert!(end <= len, EIndexOutOfBounds);

        let mut result: vector<T> = vector[];
        let mut i = start;
        while (i < end) {
            vector::push_back(&mut result, *vector::borrow(v, i));
            i = i + 1;
        };
        result
    }

    /// Get first n elements
    public fun take<T: copy>(v: &vector<T>, n: u64): vector<T> {
        let len = vector::length(v);
        let end = if (n > len) { len } else { n };
        slice(v, 0, end)
    }

    /// Skip first n elements and return the rest
    public fun skip<T: copy>(v: &vector<T>, n: u64): vector<T> {
        let len = vector::length(v);
        let start = if (n > len) { len } else { n };
        slice(v, start, len)
    }

    // === Access Functions ===

    /// Get first element
    public fun first<T>(v: &vector<T>): &T {
        assert!(!vector::is_empty(v), EIndexOutOfBounds);
        vector::borrow(v, 0)
    }

    /// Get last element
    public fun last<T>(v: &vector<T>): &T {
        let len = vector::length(v);
        assert!(len > 0, EIndexOutOfBounds);
        vector::borrow(v, len - 1)
    }

    /// Get first element or None
    public fun first_opt<T: copy>(v: &vector<T>): Option<T> {
        if (vector::is_empty(v)) {
            option::none()
        } else {
            option::some(*vector::borrow(v, 0))
        }
    }

    /// Get last element or None
    public fun last_opt<T: copy>(v: &vector<T>): Option<T> {
        let len = vector::length(v);
        if (len == 0) {
            option::none()
        } else {
            option::some(*vector::borrow(v, len - 1))
        }
    }

    // === Transformation Functions ===

    /// Reverse vector in place
    public fun reverse<T>(v: &mut vector<T>) {
        vector::reverse(v);
    }

    /// Create a reversed copy
    public fun reversed<T: copy>(v: &vector<T>): vector<T> {
        let mut result = *v;
        vector::reverse(&mut result);
        result
    }

    /// Append all elements from other vector
    public fun extend<T: copy>(v: &mut vector<T>, other: &vector<T>) {
        let len = vector::length(other);
        let mut i = 0;
        while (i < len) {
            vector::push_back(v, *vector::borrow(other, i));
            i = i + 1;
        };
    }

    /// Flatten vector of vectors into single vector
    public fun flatten<T: copy + drop>(nested: vector<vector<T>>): vector<T> {
        let mut result: vector<T> = vector[];
        let len = vector::length(&nested);
        let mut i = 0;
        while (i < len) {
            let inner = vector::borrow(&nested, i);
            extend(&mut result, inner);
            i = i + 1;
        };
        result
    }

    // === Utility Functions ===

    /// Check if two vectors are equal
    public fun equals<T: copy + drop>(a: &vector<T>, b: &vector<T>): bool {
        let len_a = vector::length(a);
        let len_b = vector::length(b);

        if (len_a != len_b) {
            return false
        };

        let mut i = 0;
        while (i < len_a) {
            if (vector::borrow(a, i) != vector::borrow(b, i)) {
                return false
            };
            i = i + 1;
        };
        true
    }

    /// Create vector with n copies of element
    public fun repeat<T: copy + drop>(elem: T, n: u64): vector<T> {
        let mut result: vector<T> = vector[];
        let mut i = 0;
        while (i < n) {
            vector::push_back(&mut result, elem);
            i = i + 1;
        };
        result
    }

    /// Create vector from range [start, end)
    public fun range(start: u64, end: u64): vector<u64> {
        assert!(start <= end, EInvalidRange);
        let mut result: vector<u64> = vector[];
        let mut i = start;
        while (i < end) {
            vector::push_back(&mut result, i);
            i = i + 1;
        };
        result
    }

    /// Zip two vectors into vector of pairs (truncates to shorter length)
    public fun zip<T: copy, U: copy>(a: &vector<T>, b: &vector<U>): vector<ZipPair<T, U>> {
        let len_a = vector::length(a);
        let len_b = vector::length(b);
        let len = if (len_a < len_b) { len_a } else { len_b };

        let mut result: vector<ZipPair<T, U>> = vector[];
        let mut i = 0;
        while (i < len) {
            vector::push_back(&mut result, ZipPair {
                first: *vector::borrow(a, i),
                second: *vector::borrow(b, i),
            });
            i = i + 1;
        };
        result
    }

    /// Pair struct for zip function
    public struct ZipPair<T, U> has copy, drop, store {
        first: T,
        second: U,
    }

    /// Get first element of pair
    public fun pair_first<T: copy, U>(pair: &ZipPair<T, U>): T {
        pair.first
    }

    /// Get second element of pair
    public fun pair_second<T, U: copy>(pair: &ZipPair<T, U>): U {
        pair.second
    }

    // === Tests ===

    #[test]
    fun test_find() {
        let v = vector[1, 2, 3, 4, 5];
        assert!(find(&v, &3) == option::some(2), 0);
        assert!(find(&v, &10) == option::none(), 1);
    }

    #[test]
    fun test_contains() {
        let v = vector[1, 2, 3];
        assert!(contains(&v, &2) == true, 0);
        assert!(contains(&v, &5) == false, 1);
    }

    #[test]
    fun test_count() {
        let v = vector[1, 2, 2, 3, 2];
        assert!(count(&v, &2) == 3, 0);
        assert!(count(&v, &5) == 0, 1);
    }

    #[test]
    fun test_remove_value() {
        let mut v = vector[1, 2, 3, 2, 4];
        assert!(remove_value(&mut v, &2) == true, 0);
        assert!(v == vector[1, 3, 2, 4], 1);
    }

    #[test]
    fun test_remove_all() {
        let mut v = vector[1, 2, 2, 3, 2];
        let removed = remove_all(&mut v, &2);
        assert!(removed == 3, 0);
        assert!(v == vector[1, 3], 1);
    }

    #[test]
    fun test_deduplicate() {
        let mut v = vector[1, 2, 2, 3, 1, 4];
        deduplicate(&mut v);
        assert!(v == vector[1, 2, 3, 4], 0);
    }

    #[test]
    fun test_has_duplicates() {
        assert!(has_duplicates(&vector[1, 2, 2, 3]) == true, 0);
        assert!(has_duplicates(&vector[1, 2, 3, 4]) == false, 1);
    }

    #[test]
    fun test_slice() {
        let v = vector[1, 2, 3, 4, 5];
        assert!(slice(&v, 1, 4) == vector[2, 3, 4], 0);
    }

    #[test]
    fun test_take() {
        let v = vector[1, 2, 3, 4, 5];
        assert!(take(&v, 3) == vector[1, 2, 3], 0);
        assert!(take(&v, 10) == vector[1, 2, 3, 4, 5], 1);
    }

    #[test]
    fun test_skip() {
        let v = vector[1, 2, 3, 4, 5];
        assert!(skip(&v, 2) == vector[3, 4, 5], 0);
    }

    #[test]
    fun test_first_last() {
        let v = vector[1, 2, 3];
        assert!(*first(&v) == 1, 0);
        assert!(*last(&v) == 3, 1);
    }

    #[test]
    fun test_reversed() {
        let v = vector[1, 2, 3];
        assert!(reversed(&v) == vector[3, 2, 1], 0);
    }

    #[test]
    fun test_equals() {
        assert!(equals(&vector[1, 2, 3], &vector[1, 2, 3]) == true, 0);
        assert!(equals(&vector[1, 2, 3], &vector[1, 2]) == false, 1);
        assert!(equals(&vector[1, 2, 3], &vector[1, 2, 4]) == false, 2);
    }

    #[test]
    fun test_repeat() {
        assert!(repeat(5, 3) == vector[5, 5, 5], 0);
    }

    #[test]
    fun test_range() {
        assert!(range(1, 5) == vector[1, 2, 3, 4], 0);
    }

    #[test]
    fun test_flatten() {
        let nested = vector[vector[1, 2], vector[3, 4], vector[5]];
        assert!(flatten(nested) == vector[1, 2, 3, 4, 5], 0);
    }
}
