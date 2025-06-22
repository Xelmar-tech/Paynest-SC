// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

/// @title IPayments
/// @notice Interface for PayNest payments plugin with multiple payment support and flow-based streaming
/// @dev V2.0 interface supporting unlimited streams and schedules per user with enhanced migration
interface IPayments {
    /// @notice Enhanced interval types for scheduled payments
    enum IntervalType {
        Daily, // 24 hours
        Weekly, // 7 days
        BiWeekly, // 14 days
        Monthly, // 30 days
        Quarterly, // 90 days
        SemiAnnual, // 180 days
        Yearly // 365 days

    }

    /// @notice Stream lifecycle states
    enum StreamState {
        Active, // Normal flow operation
        Paused, // Temporarily stopped (flow rate = 0, metadata preserved)
        Cancelled // Permanently terminated (metadata cleared)

    }

    /// @notice Stream data structure for flow-based streaming
    struct Stream {
        address token; // ERC20 token for payments
        uint216 amountPerSec; // Flow rate in LlamaPay's 20-decimal precision
        StreamState state; // Stream state (active/paused/cancelled)
        uint40 startTime; // When flow began (for calculations)
    }

    /// @notice Schedule data structure for multiple schedules
    struct Schedule {
        address token; // ERC20 token for payments
        uint256 amount; // Amount per interval
        IntervalType interval; // Payment frequency
        bool isOneTime; // One-time vs recurring
        bool active; // Schedule state
        uint40 firstPaymentDate; // Initial payment timestamp
        uint40 nextPayout; // Next scheduled payment
    }

    /// @notice Payment summary structure for user overview
    struct PaymentSummary {
        uint256 totalActiveStreams;
        uint256 totalActiveSchedules;
        address[] uniqueTokens;
        uint256[] monthlyStreamAmounts; // Estimated monthly flow
        uint256[] pendingScheduleAmounts;
    }

    /// @notice Migration preview structure for safety
    struct MigrationPreview {
        address currentRecipient;
        bytes32[] streamsNeedingMigration;
        bytes32[] schedulesNeedingMigration;
        uint256 estimatedGasCost;
        bool migrationRequired;
    }

    /// @notice Stream lifecycle events
    event StreamCreated(
        string indexed username,
        bytes32 indexed streamId,
        address indexed token,
        uint216 amountPerSec,
        address recipient
    );

    event FlowRateUpdated(
        string indexed username, bytes32 indexed streamId, uint216 oldAmountPerSec, uint216 newAmountPerSec
    );

    event StreamStateChanged(
        string indexed username, bytes32 indexed streamId, StreamState oldState, StreamState newState
    );

    event StreamMigrated(string indexed username, bytes32 indexed streamId, address oldRecipient, address newRecipient);

    /// @notice Schedule events
    event ScheduleCreated(
        string indexed username,
        bytes32 indexed scheduleId,
        address indexed token,
        uint256 amount,
        IntervalType interval,
        bool isOneTime,
        uint40 firstPaymentDate
    );

    event ScheduleExecuted(
        string indexed username, bytes32 indexed scheduleId, address indexed token, uint256 amount, uint256 periods
    );

    event ScheduleCancelled(string indexed username, bytes32 indexed scheduleId);

    /// @notice Create indefinite flow rate stream without artificial end dates
    /// @param username Target username for payment
    /// @param token ERC20 token address
    /// @param amountPerSec Flow rate in LlamaPay's 20-decimal precision
    /// @return streamId Unique stream identifier for future operations
    function createStream(string calldata username, address token, uint216 amountPerSec)
        external
        returns (bytes32 streamId);

    /// @notice Efficiently update stream flow rate using LlamaPay's native capabilities
    /// @param username Stream owner username
    /// @param streamId Unique stream identifier
    /// @param newAmountPerSec New flow rate in LlamaPay precision
    function updateFlowRate(string calldata username, bytes32 streamId, uint216 newAmountPerSec) external;

    /// @notice Temporarily stop flow (set flow rate to 0, maintain metadata)
    /// @param username Stream owner username
    /// @param streamId Unique stream identifier
    function pauseStream(string calldata username, bytes32 streamId) external;

    /// @notice Restore previous flow rate from metadata
    /// @param username Stream owner username
    /// @param streamId Unique stream identifier
    function resumeStream(string calldata username, bytes32 streamId) external;

    /// @notice Permanently terminate stream and clear metadata
    /// @param username Stream owner username
    /// @param streamId Unique stream identifier
    function cancelStream(string calldata username, bytes32 streamId) external;

    /// @notice Create additional scheduled payments for users
    /// @param username Target username for payment
    /// @param token ERC20 token address
    /// @param amount Amount per interval
    /// @param interval Payment frequency
    /// @param isOneTime Whether this is a one-time or recurring payment
    /// @param firstPaymentDate Initial payment timestamp
    /// @return scheduleId Unique schedule identifier for management
    function createSchedule(
        string calldata username,
        address token,
        uint256 amount,
        IntervalType interval,
        bool isOneTime,
        uint40 firstPaymentDate
    ) external returns (bytes32 scheduleId);

    /// @notice Update schedule amount
    /// @param username Schedule owner username
    /// @param scheduleId Unique schedule identifier
    /// @param newAmount New amount per interval
    function updateScheduleAmount(string calldata username, bytes32 scheduleId, uint256 newAmount) external;

    /// @notice Update schedule interval
    /// @param username Schedule owner username
    /// @param scheduleId Unique schedule identifier
    /// @param newInterval New payment frequency
    function updateScheduleInterval(string calldata username, bytes32 scheduleId, IntervalType newInterval) external;

    /// @notice Cancel scheduled payment
    /// @param username Schedule owner username
    /// @param scheduleId Unique schedule identifier
    function cancelSchedule(string calldata username, bytes32 scheduleId) external;

    /// @notice Execute due scheduled payment
    /// @param username Schedule owner username
    /// @param scheduleId Unique schedule identifier
    function executeSchedule(string calldata username, bytes32 scheduleId) external;

    /// @notice Get all streams for a user
    /// @param username Target username
    /// @return streamIds Array of stream identifiers
    /// @return streamData Array of stream data
    function getUserStreams(string calldata username)
        external
        view
        returns (bytes32[] memory streamIds, Stream[] memory streamData);

    /// @notice Get all schedules for a user
    /// @param username Target username
    /// @return scheduleIds Array of schedule identifiers
    /// @return scheduleData Array of schedule data
    function getUserSchedules(string calldata username)
        external
        view
        returns (bytes32[] memory scheduleIds, Schedule[] memory scheduleData);

    /// @notice Get active payments overview for a user
    /// @param username Target username
    /// @return activeStreamIds Array of active stream identifiers
    /// @return activeScheduleIds Array of active schedule identifiers
    /// @return totalActiveStreams Total number of active streams
    /// @return totalActiveSchedules Total number of active schedules
    function getUserActivePayments(string calldata username)
        external
        view
        returns (
            bytes32[] memory activeStreamIds,
            bytes32[] memory activeScheduleIds,
            uint256 totalActiveStreams,
            uint256 totalActiveSchedules
        );

    /// @notice Get comprehensive payment summary for a user
    /// @param username Target username
    /// @return Payment summary with totals and estimates
    function getUserPaymentSummary(string calldata username) external view returns (PaymentSummary memory);

    /// @notice Pause all active streams for a user
    /// @param username Target username
    /// @return pausedStreamIds Array of paused stream identifiers
    function pauseAllUserStreams(string calldata username) external returns (bytes32[] memory pausedStreamIds);

    /// @notice Resume all paused streams for a user
    /// @param username Target username
    /// @return resumedStreamIds Array of resumed stream identifiers
    function resumeAllUserStreams(string calldata username) external returns (bytes32[] memory resumedStreamIds);

    /// @notice Migrate specific stream to current recipient address
    /// @param username Target username
    /// @param streamId Stream to migrate
    function migrateStream(string calldata username, bytes32 streamId) external;

    /// @notice Migrate all streams for a user
    /// @param username Target username
    /// @return migratedStreamIds Array of migrated stream identifiers
    function migrateAllStreams(string calldata username) external returns (bytes32[] memory migratedStreamIds);

    /// @notice Migrate only streams for specific token
    /// @param username Target username
    /// @param token Token address to filter by
    /// @return migratedStreamIds Array of migrated stream identifiers
    function migrateStreamsForToken(string calldata username, address token)
        external
        returns (bytes32[] memory migratedStreamIds);

    /// @notice Migrate only specified stream IDs
    /// @param username Target username
    /// @param streamIds Array of stream IDs to migrate
    /// @return migratedStreamIds Array of successfully migrated stream identifiers
    function migrateSelectedStreams(string calldata username, bytes32[] calldata streamIds)
        external
        returns (bytes32[] memory migratedStreamIds);

    /// @notice Preview migration requirements for a user
    /// @param username Target username
    /// @return Migration preview with details and cost estimates
    function getMigrationPreview(string calldata username) external view returns (MigrationPreview memory);

    /// @notice Get individual stream data
    /// @param username Stream owner username
    /// @param streamId Unique stream identifier
    /// @return Stream data
    function getStream(string calldata username, bytes32 streamId) external view returns (Stream memory);

    /// @notice Get individual schedule data
    /// @param username Schedule owner username
    /// @param scheduleId Unique schedule identifier
    /// @return Schedule data
    function getSchedule(string calldata username, bytes32 scheduleId) external view returns (Schedule memory);
}
