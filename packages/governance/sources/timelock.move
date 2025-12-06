/// @title Timelock
/// @notice Time-delayed execution for governance actions
/// @dev Part of @sui-starters/governance package
module sui_starters_governance::timelock {
    use std::string::String;
    use sui::event;

    // === Errors ===

    const ENotReady: u64 = 0;
    const EExpired: u64 = 1;
    const EAlreadyExecuted: u64 = 2;
    const ECancelled: u64 = 3;
    const EInvalidDelay: u64 = 4;

    // === Constants ===

    const STATUS_PENDING: u8 = 0;
    const STATUS_READY: u8 = 1;
    const STATUS_EXECUTED: u8 = 2;
    const STATUS_CANCELLED: u8 = 3;
    const STATUS_EXPIRED: u8 = 4;

    // === Structs ===

    /// Timelock configuration
    public struct TimelockConfig has store, copy, drop {
        /// Minimum delay in epochs
        min_delay: u64,
        /// Maximum delay in epochs
        max_delay: u64,
        /// Grace period after ready (before expiry)
        grace_period: u64,
    }

    /// Scheduled operation
    public struct TimelockOperation has key, store {
        id: UID,
        /// Operation hash/identifier
        operation_id: vector<u8>,
        /// Description
        description: String,
        /// Target module/function (for reference)
        target: String,
        /// Queued epoch
        queued_epoch: u64,
        /// Ready epoch (when can execute)
        ready_epoch: u64,
        /// Expiry epoch
        expiry_epoch: u64,
        /// Current status
        status: u8,
    }

    /// Execution receipt
    public struct ExecutionReceipt has key, store {
        id: UID,
        operation_id: ID,
        executed_epoch: u64,
        executor: address,
    }

    // === Events ===

    public struct OperationQueued has copy, drop {
        operation_id: ID,
        ready_epoch: u64,
        expiry_epoch: u64,
    }

    public struct OperationExecuted has copy, drop {
        operation_id: ID,
        executor: address,
        epoch: u64,
    }

    public struct OperationCancelled has copy, drop {
        operation_id: ID,
        epoch: u64,
    }

    // === Create Functions ===

    /// Create timelock config
    public fun new_config(
        min_delay: u64,
        max_delay: u64,
        grace_period: u64,
    ): TimelockConfig {
        assert!(max_delay >= min_delay, EInvalidDelay);

        TimelockConfig {
            min_delay,
            max_delay,
            grace_period,
        }
    }

    /// Queue a new operation
    public fun queue(
        config: &TimelockConfig,
        operation_id: vector<u8>,
        description: String,
        target: String,
        delay: u64,
        ctx: &mut TxContext,
    ): TimelockOperation {
        assert!(delay >= config.min_delay && delay <= config.max_delay, EInvalidDelay);

        let current_epoch = ctx.epoch();
        let ready_epoch = current_epoch + delay;
        let expiry_epoch = ready_epoch + config.grace_period;

        let operation = TimelockOperation {
            id: object::new(ctx),
            operation_id,
            description,
            target,
            queued_epoch: current_epoch,
            ready_epoch,
            expiry_epoch,
            status: STATUS_PENDING,
        };

        event::emit(OperationQueued {
            operation_id: object::id(&operation),
            ready_epoch,
            expiry_epoch,
        });

        operation
    }

    // === Core Functions ===

    /// Check and update status based on current epoch
    public fun update_status(
        operation: &mut TimelockOperation,
        current_epoch: u64,
    ) {
        if (operation.status == STATUS_PENDING && current_epoch >= operation.ready_epoch) {
            if (current_epoch <= operation.expiry_epoch) {
                operation.status = STATUS_READY;
            } else {
                operation.status = STATUS_EXPIRED;
            };
        } else if (operation.status == STATUS_READY && current_epoch > operation.expiry_epoch) {
            operation.status = STATUS_EXPIRED;
        };
    }

    /// Execute operation (returns receipt, actual execution is off-chain)
    public fun execute(
        operation: &mut TimelockOperation,
        ctx: &mut TxContext,
    ): ExecutionReceipt {
        let current_epoch = ctx.epoch();

        // Update status first
        update_status(operation, current_epoch);

        assert!(operation.status != STATUS_EXECUTED, EAlreadyExecuted);
        assert!(operation.status != STATUS_CANCELLED, ECancelled);
        assert!(operation.status != STATUS_EXPIRED, EExpired);
        assert!(operation.status == STATUS_READY, ENotReady);

        operation.status = STATUS_EXECUTED;

        event::emit(OperationExecuted {
            operation_id: object::id(operation),
            executor: ctx.sender(),
            epoch: current_epoch,
        });

        ExecutionReceipt {
            id: object::new(ctx),
            operation_id: object::id(operation),
            executed_epoch: current_epoch,
            executor: ctx.sender(),
        }
    }

    /// Cancel operation
    public fun cancel(
        operation: &mut TimelockOperation,
        ctx: &TxContext,
    ) {
        assert!(operation.status == STATUS_PENDING || operation.status == STATUS_READY, EAlreadyExecuted);

        operation.status = STATUS_CANCELLED;

        event::emit(OperationCancelled {
            operation_id: object::id(operation),
            epoch: ctx.epoch(),
        });
    }

    // === View Functions ===

    /// Get operation status
    public fun status(operation: &TimelockOperation): u8 {
        operation.status
    }

    /// Is operation ready to execute
    public fun is_ready(operation: &TimelockOperation, current_epoch: u64): bool {
        current_epoch >= operation.ready_epoch &&
        current_epoch <= operation.expiry_epoch &&
        operation.status != STATUS_EXECUTED &&
        operation.status != STATUS_CANCELLED
    }

    /// Get ready epoch
    public fun ready_epoch(operation: &TimelockOperation): u64 {
        operation.ready_epoch
    }

    /// Get expiry epoch
    public fun expiry_epoch(operation: &TimelockOperation): u64 {
        operation.expiry_epoch
    }

    /// Get time until ready
    public fun time_until_ready(operation: &TimelockOperation, current_epoch: u64): u64 {
        if (current_epoch >= operation.ready_epoch) {
            0
        } else {
            operation.ready_epoch - current_epoch
        }
    }

    /// Get remaining grace period
    public fun remaining_grace(operation: &TimelockOperation, current_epoch: u64): u64 {
        if (current_epoch > operation.expiry_epoch) {
            0
        } else if (current_epoch < operation.ready_epoch) {
            operation.expiry_epoch - operation.ready_epoch
        } else {
            operation.expiry_epoch - current_epoch
        }
    }

    /// Status constants
    public fun status_pending(): u8 { STATUS_PENDING }
    public fun status_ready(): u8 { STATUS_READY }
    public fun status_executed(): u8 { STATUS_EXECUTED }
    public fun status_cancelled(): u8 { STATUS_CANCELLED }
    public fun status_expired(): u8 { STATUS_EXPIRED }

    // === Tests ===

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use std::string;

    #[test]
    fun test_create_config() {
        let config = new_config(2, 14, 7);

        assert!(config.min_delay == 2, 0);
        assert!(config.max_delay == 14, 1);
        assert!(config.grace_period == 7, 2);
    }

    #[test]
    fun test_queue_operation() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let config = new_config(2, 14, 7);

            let operation = queue(
                &config,
                vector[111, 112, 95, 48, 48, 49],
                string::utf8(b"Test Operation"),
                string::utf8(b"governance::execute"),
                5,
                scenario.ctx(),
            );

            assert!(status(&operation) == STATUS_PENDING, 0);
            assert!(ready_epoch(&operation) == 5, 1); // epoch 0 + delay 5
            assert!(time_until_ready(&operation, 0) == 5, 2);

            transfer::public_transfer(operation, admin);
        };

        scenario.end();
    }

    #[test]
    fun test_cancel_operation() {
        let admin = @0xAD;
        let mut scenario = test_scenario::begin(admin);

        {
            let config = new_config(2, 14, 7);

            let mut operation = queue(
                &config,
                vector[111, 112, 95, 48, 48, 50],
                string::utf8(b"Test Cancel"),
                string::utf8(b"governance::execute"),
                5,
                scenario.ctx(),
            );

            cancel(&mut operation, scenario.ctx());
            assert!(status(&operation) == STATUS_CANCELLED, 0);

            transfer::public_transfer(operation, admin);
        };

        scenario.end();
    }
}
