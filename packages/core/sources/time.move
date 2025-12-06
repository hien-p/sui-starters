/// @title Time utilities for Sui Move
/// @notice Epoch-based time utilities for deadlines, durations, and scheduling
/// @dev Part of @sui-starters/core package
module sui_starters_core::time {
    use sui::clock::Clock;

    // === Constants ===

    /// Milliseconds in one second
    const MS_PER_SECOND: u64 = 1000;

    /// Milliseconds in one minute
    const MS_PER_MINUTE: u64 = 60000;

    /// Milliseconds in one hour
    const MS_PER_HOUR: u64 = 3600000;

    /// Milliseconds in one day
    const MS_PER_DAY: u64 = 86400000;

    /// Milliseconds in one week
    const MS_PER_WEEK: u64 = 604800000;

    // === Errors ===

    /// Deadline has passed
    const EDeadlinePassed: u64 = 0;

    /// Duration not yet passed
    const EDurationNotPassed: u64 = 1;

    /// Invalid timestamp
    const EInvalidTimestamp: u64 = 2;

    // === Epoch-based Functions (using TxContext) ===

    /// Get current epoch from transaction context
    public fun current_epoch(ctx: &TxContext): u64 {
        sui::tx_context::epoch(ctx)
    }

    /// Check if deadline epoch has passed
    public fun is_epoch_expired(deadline_epoch: u64, ctx: &TxContext): bool {
        current_epoch(ctx) >= deadline_epoch
    }

    /// Check if duration in epochs has passed since start
    public fun epoch_duration_passed(start_epoch: u64, duration_epochs: u64, ctx: &TxContext): bool {
        current_epoch(ctx) >= start_epoch + duration_epochs
    }

    /// Calculate epochs remaining until deadline
    public fun epochs_until(deadline_epoch: u64, ctx: &TxContext): u64 {
        let current = current_epoch(ctx);
        if (deadline_epoch > current) {
            deadline_epoch - current
        } else {
            0
        }
    }

    /// Calculate epochs elapsed since start
    public fun epochs_since(start_epoch: u64, ctx: &TxContext): u64 {
        let current = current_epoch(ctx);
        if (current > start_epoch) {
            current - start_epoch
        } else {
            0
        }
    }

    /// Assert deadline has not passed
    public fun require_not_expired(deadline_epoch: u64, ctx: &TxContext) {
        assert!(!is_epoch_expired(deadline_epoch, ctx), EDeadlinePassed);
    }

    /// Assert duration has passed
    public fun require_duration_passed(start_epoch: u64, duration_epochs: u64, ctx: &TxContext) {
        assert!(epoch_duration_passed(start_epoch, duration_epochs, ctx), EDurationNotPassed);
    }

    // === Clock-based Functions (using sui::clock::Clock) ===

    /// Get current timestamp in milliseconds from Clock
    public fun current_timestamp_ms(clock: &Clock): u64 {
        sui::clock::timestamp_ms(clock)
    }

    /// Check if deadline timestamp has passed
    public fun is_timestamp_expired(deadline_ms: u64, clock: &Clock): bool {
        current_timestamp_ms(clock) >= deadline_ms
    }

    /// Check if duration has passed since start timestamp
    public fun timestamp_duration_passed(start_ms: u64, duration_ms: u64, clock: &Clock): bool {
        current_timestamp_ms(clock) >= start_ms + duration_ms
    }

    /// Calculate time remaining until deadline in milliseconds
    public fun time_until_ms(deadline_ms: u64, clock: &Clock): u64 {
        let current = current_timestamp_ms(clock);
        if (deadline_ms > current) {
            deadline_ms - current
        } else {
            0
        }
    }

    /// Calculate time elapsed since start in milliseconds
    public fun time_since_ms(start_ms: u64, clock: &Clock): u64 {
        let current = current_timestamp_ms(clock);
        if (current > start_ms) {
            current - start_ms
        } else {
            0
        }
    }

    /// Assert deadline timestamp has not passed
    public fun require_timestamp_not_expired(deadline_ms: u64, clock: &Clock) {
        assert!(!is_timestamp_expired(deadline_ms, clock), EDeadlinePassed);
    }

    /// Assert duration has passed since timestamp
    public fun require_timestamp_duration_passed(start_ms: u64, duration_ms: u64, clock: &Clock) {
        assert!(timestamp_duration_passed(start_ms, duration_ms, clock), EDurationNotPassed);
    }

    // === Time Conversion Utilities ===

    /// Convert seconds to milliseconds
    public fun seconds_to_ms(seconds: u64): u64 {
        seconds * MS_PER_SECOND
    }

    /// Convert minutes to milliseconds
    public fun minutes_to_ms(minutes: u64): u64 {
        minutes * MS_PER_MINUTE
    }

    /// Convert hours to milliseconds
    public fun hours_to_ms(hours: u64): u64 {
        hours * MS_PER_HOUR
    }

    /// Convert days to milliseconds
    public fun days_to_ms(days: u64): u64 {
        days * MS_PER_DAY
    }

    /// Convert weeks to milliseconds
    public fun weeks_to_ms(weeks: u64): u64 {
        weeks * MS_PER_WEEK
    }

    /// Convert milliseconds to seconds (truncates)
    public fun ms_to_seconds(ms: u64): u64 {
        ms / MS_PER_SECOND
    }

    /// Convert milliseconds to minutes (truncates)
    public fun ms_to_minutes(ms: u64): u64 {
        ms / MS_PER_MINUTE
    }

    /// Convert milliseconds to hours (truncates)
    public fun ms_to_hours(ms: u64): u64 {
        ms / MS_PER_HOUR
    }

    /// Convert milliseconds to days (truncates)
    public fun ms_to_days(ms: u64): u64 {
        ms / MS_PER_DAY
    }

    // === Deadline Builders ===

    /// Create deadline timestamp from current time + duration
    public fun deadline_from_now(duration_ms: u64, clock: &Clock): u64 {
        current_timestamp_ms(clock) + duration_ms
    }

    /// Create deadline timestamp from current time + seconds
    public fun deadline_in_seconds(seconds: u64, clock: &Clock): u64 {
        deadline_from_now(seconds_to_ms(seconds), clock)
    }

    /// Create deadline timestamp from current time + minutes
    public fun deadline_in_minutes(minutes: u64, clock: &Clock): u64 {
        deadline_from_now(minutes_to_ms(minutes), clock)
    }

    /// Create deadline timestamp from current time + hours
    public fun deadline_in_hours(hours: u64, clock: &Clock): u64 {
        deadline_from_now(hours_to_ms(hours), clock)
    }

    /// Create deadline timestamp from current time + days
    public fun deadline_in_days(days: u64, clock: &Clock): u64 {
        deadline_from_now(days_to_ms(days), clock)
    }

    /// Create deadline epoch from current epoch + duration
    public fun deadline_epoch_from_now(duration_epochs: u64, ctx: &TxContext): u64 {
        current_epoch(ctx) + duration_epochs
    }

    // === Progress Calculation ===

    /// Calculate progress percentage (0-10000 basis points)
    /// Returns 10000 (100%) if duration is 0 or elapsed >= duration
    public fun calculate_progress_bps(start_ms: u64, duration_ms: u64, clock: &Clock): u64 {
        if (duration_ms == 0) {
            return 10000
        };

        let elapsed = time_since_ms(start_ms, clock);
        if (elapsed >= duration_ms) {
            10000
        } else {
            ((elapsed as u128) * 10000 / (duration_ms as u128) as u64)
        }
    }

    /// Calculate vested/unlocked amount based on linear schedule
    public fun calculate_linear_unlock(
        total_amount: u64,
        start_ms: u64,
        cliff_ms: u64,
        duration_ms: u64,
        clock: &Clock
    ): u64 {
        let current = current_timestamp_ms(clock);

        // Before cliff: nothing unlocked
        if (current < start_ms + cliff_ms) {
            return 0
        };

        // After full duration: everything unlocked
        if (current >= start_ms + duration_ms) {
            return total_amount
        };

        // Linear unlock
        let elapsed = current - start_ms;
        ((total_amount as u128) * (elapsed as u128) / (duration_ms as u128) as u64)
    }

    // === Constants Getters ===

    public fun ms_per_second(): u64 { MS_PER_SECOND }
    public fun ms_per_minute(): u64 { MS_PER_MINUTE }
    public fun ms_per_hour(): u64 { MS_PER_HOUR }
    public fun ms_per_day(): u64 { MS_PER_DAY }
    public fun ms_per_week(): u64 { MS_PER_WEEK }

    // === Tests ===

    #[test]
    fun test_time_conversions() {
        assert!(seconds_to_ms(1) == 1000, 0);
        assert!(minutes_to_ms(1) == 60000, 1);
        assert!(hours_to_ms(1) == 3600000, 2);
        assert!(days_to_ms(1) == 86400000, 3);
        assert!(weeks_to_ms(1) == 604800000, 4);
    }

    #[test]
    fun test_ms_to_conversions() {
        assert!(ms_to_seconds(5500) == 5, 0);
        assert!(ms_to_minutes(90000) == 1, 1);
        assert!(ms_to_hours(7200000) == 2, 2);
        assert!(ms_to_days(172800000) == 2, 3);
    }
}
