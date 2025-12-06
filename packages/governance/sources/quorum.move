/// @title Quorum
/// @notice Quorum calculation and validation
/// @dev Part of @sui-starters/governance package
module sui_starters_governance::quorum {
    use sui::event;

    // === Errors ===

    const EQuorumNotMet: u64 = 0;
    const EInvalidPercentage: u64 = 1;

    // === Constants ===

    /// Basis points (10000 = 100%)
    const BPS_MAX: u64 = 10000;

    // === Structs ===

    /// Quorum configuration
    public struct QuorumConfig has store, copy, drop {
        /// Minimum participation percentage (in bps)
        min_participation_bps: u64,
        /// Minimum approval percentage (in bps)
        min_approval_bps: u64,
        /// Dynamic quorum enabled
        dynamic_enabled: bool,
        /// Base quorum for dynamic calculation
        base_quorum_bps: u64,
        /// Quorum adjustment factor
        adjustment_factor: u64,
    }

    /// Quorum result
    public struct QuorumResult has store, copy, drop {
        /// Required quorum
        required: u64,
        /// Actual participation
        actual_participation: u64,
        /// Is quorum met
        met: bool,
        /// Approval percentage in bps
        approval_bps: u64,
    }

    // === Events ===

    public struct QuorumChecked has copy, drop {
        required: u64,
        actual: u64,
        met: bool,
    }

    // === Create Functions ===

    /// Create simple quorum config
    public fun new_simple(
        min_participation_bps: u64,
        min_approval_bps: u64,
    ): QuorumConfig {
        assert!(min_participation_bps <= BPS_MAX, EInvalidPercentage);
        assert!(min_approval_bps <= BPS_MAX, EInvalidPercentage);

        QuorumConfig {
            min_participation_bps,
            min_approval_bps,
            dynamic_enabled: false,
            base_quorum_bps: 0,
            adjustment_factor: 0,
        }
    }

    /// Create dynamic quorum config
    public fun new_dynamic(
        base_quorum_bps: u64,
        min_approval_bps: u64,
        adjustment_factor: u64,
    ): QuorumConfig {
        assert!(base_quorum_bps <= BPS_MAX, EInvalidPercentage);
        assert!(min_approval_bps <= BPS_MAX, EInvalidPercentage);

        QuorumConfig {
            min_participation_bps: base_quorum_bps,
            min_approval_bps,
            dynamic_enabled: true,
            base_quorum_bps,
            adjustment_factor,
        }
    }

    // === Core Functions ===

    /// Calculate required quorum
    public fun calculate_quorum(
        config: &QuorumConfig,
        total_voting_power: u64,
    ): u64 {
        if (config.dynamic_enabled) {
            // Dynamic quorum can adjust based on factors
            (total_voting_power * config.base_quorum_bps) / BPS_MAX
        } else {
            // Fixed quorum
            (total_voting_power * config.min_participation_bps) / BPS_MAX
        }
    }

    /// Check if quorum is met
    public fun check_quorum(
        config: &QuorumConfig,
        total_voting_power: u64,
        votes_for: u64,
        votes_against: u64,
        votes_abstain: u64,
    ): QuorumResult {
        let total_votes = votes_for + votes_against + votes_abstain;
        let required = calculate_quorum(config, total_voting_power);

        let participation_met = total_votes >= required;

        // Calculate approval percentage
        let approval_bps = if (votes_for + votes_against > 0) {
            (votes_for * BPS_MAX) / (votes_for + votes_against)
        } else {
            0
        };

        let approval_met = approval_bps >= config.min_approval_bps;

        let met = participation_met && approval_met;

        event::emit(QuorumChecked {
            required,
            actual: total_votes,
            met,
        });

        QuorumResult {
            required,
            actual_participation: total_votes,
            met,
            approval_bps,
        }
    }

    /// Assert quorum is met
    public fun assert_quorum_met(result: &QuorumResult) {
        assert!(result.met, EQuorumNotMet);
    }

    // === View Functions ===

    /// Get min participation
    public fun min_participation(config: &QuorumConfig): u64 {
        config.min_participation_bps
    }

    /// Get min approval
    public fun min_approval(config: &QuorumConfig): u64 {
        config.min_approval_bps
    }

    /// Is dynamic quorum
    public fun is_dynamic(config: &QuorumConfig): bool {
        config.dynamic_enabled
    }

    /// Get result info
    public fun result_info(result: &QuorumResult): (u64, u64, bool, u64) {
        (result.required, result.actual_participation, result.met, result.approval_bps)
    }

    /// Is result met
    public fun is_met(result: &QuorumResult): bool {
        result.met
    }

    /// BPS max constant
    public fun bps_max(): u64 { BPS_MAX }

    // === Tests ===

    #[test]
    fun test_simple_quorum() {
        let config = new_simple(2000, 5000); // 20% participation, 50% approval

        assert!(min_participation(&config) == 2000, 0);
        assert!(min_approval(&config) == 5000, 1);
        assert!(!is_dynamic(&config), 2);
    }

    #[test]
    fun test_calculate_quorum() {
        let config = new_simple(2000, 5000); // 20% participation

        let required = calculate_quorum(&config, 10000);
        assert!(required == 2000, 0); // 20% of 10000
    }

    #[test]
    fun test_check_quorum_pass() {
        let config = new_simple(2000, 5000); // 20% participation, 50% approval

        // Total power 10000, need 2000 votes and 50% approval
        let result = check_quorum(&config, 10000, 1500, 1000, 500); // 3000 total, 60% approval

        let (required, actual, met, approval) = result_info(&result);
        assert!(required == 2000, 0);
        assert!(actual == 3000, 1);
        assert!(met, 2);
        assert!(approval == 6000, 3); // 60% in bps
    }

    #[test]
    fun test_check_quorum_fail_participation() {
        let config = new_simple(2000, 5000);

        // Only 1000 votes out of needed 2000
        let result = check_quorum(&config, 10000, 600, 300, 100);

        assert!(!is_met(&result), 0);
    }

    #[test]
    fun test_check_quorum_fail_approval() {
        let config = new_simple(2000, 5000);

        // Enough participation but not enough approval
        let result = check_quorum(&config, 10000, 800, 1200, 500); // 40% approval

        assert!(!is_met(&result), 0);
    }

    #[test]
    fun test_dynamic_quorum() {
        let config = new_dynamic(1500, 5000, 100); // 15% base, 50% approval

        assert!(is_dynamic(&config), 0);

        let required = calculate_quorum(&config, 10000);
        assert!(required == 1500, 1);
    }
}
