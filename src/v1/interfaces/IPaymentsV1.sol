// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

/// @title IPaymentsV1
/// @notice Interface for the PayNest payments plugin functionality
/// @dev Defines the core functions for managing streaming and scheduled payments with username resolution
interface IPaymentsV1 {
    /// @notice Possible intervals for scheduled payments
    enum IntervalType {
        Weekly,
        Monthly,
        Quarterly,
        Yearly
    }

    /// @notice Stream data structure
    struct Stream {
        address token;
        uint40 endDate;
        bool active;
        uint216 amount; // LlamaPay amountPerSec
        uint40 lastPayout;
    }

    /// @notice Schedule data structure
    struct Schedule {
        address token;
        uint256 amount;
        IntervalType interval;
        bool isOneTime;
        bool active;
        uint40 firstPaymentDate;
        uint40 nextPayout;
    }

    /// @notice Emitted when a new stream is created
    /// @param username The username receiving the stream
    /// @param token The token being streamed
    /// @param endDate When the stream ends
    /// @param totalAmount Total amount to be streamed
    event StreamActive(string indexed username, address indexed token, uint40 endDate, uint256 totalAmount);

    /// @notice Emitted when a stream is updated
    /// @param username The username receiving the stream
    /// @param token The token being streamed
    /// @param newAmount New total amount for the stream
    event StreamUpdated(string indexed username, address indexed token, uint256 newAmount);

    /// @notice Emitted when a stream is cancelled
    /// @param username The username that had the stream
    /// @param token The token that was being streamed
    event PaymentStreamCancelled(string indexed username, address indexed token);

    /// @notice Emitted when a stream payout is requested
    /// @param username The username receiving the payout
    /// @param token The token being paid out
    /// @param amount Amount paid out
    event StreamPayout(string indexed username, address indexed token, uint256 amount);

    /// @notice Emitted when a new schedule is created
    /// @param username The username receiving scheduled payments
    /// @param token The token for scheduled payments
    /// @param amount Amount per payment
    /// @param interval Payment interval
    /// @param isOneTime Whether this is a one-time payment
    /// @param firstPaymentDate When the first payment is due
    event ScheduleActive(
        string indexed username,
        address indexed token,
        uint256 amount,
        IntervalType interval,
        bool isOneTime,
        uint40 firstPaymentDate
    );

    /// @notice Emitted when a schedule is updated
    /// @param username The username receiving scheduled payments
    /// @param token The token for scheduled payments
    /// @param newAmount New amount per payment
    event ScheduleUpdated(string indexed username, address indexed token, uint256 newAmount);

    /// @notice Emitted when a schedule is cancelled
    /// @param username The username that had the schedule
    /// @param token The token that was being scheduled
    event PaymentScheduleCancelled(string indexed username, address indexed token);

    /// @notice Emitted when a scheduled payment is made
    /// @param username The username receiving the payment
    /// @param token The token being paid
    /// @param amount Amount paid
    /// @param periodsPayingFor Number of periods this payment covers
    event SchedulePayout(string indexed username, address indexed token, uint256 amount, uint256 periodsPayingFor);

    /// @notice Create a new streaming payment
    /// @param username The username to stream to
    /// @param amount Total amount to stream over the duration
    /// @param token Token contract address
    /// @param endStream Timestamp when stream should end
    function createStream(string calldata username, uint256 amount, address token, uint40 endStream) external;

    /// @notice Cancel an existing stream
    /// @param username The username to cancel stream for
    function cancelStream(string calldata username) external;

    /// @notice Edit an existing stream amount
    /// @param username The username to edit stream for
    /// @param amount New total amount for the stream
    function editStream(string calldata username, uint256 amount) external;

    /// @notice Request payout from a stream
    /// @param username The username to request payout for
    /// @return amount The amount paid out
    function requestStreamPayout(string calldata username) external payable returns (uint256 amount);

    /// @notice Create a new scheduled payment
    /// @param username The username to schedule payments for
    /// @param amount Amount per payment
    /// @param token Token contract address
    /// @param interval Payment interval
    /// @param isOneTime Whether this is a one-time payment
    /// @param firstPaymentDate When the first payment should occur
    function createSchedule(
        string calldata username,
        uint256 amount,
        address token,
        IntervalType interval,
        bool isOneTime,
        uint40 firstPaymentDate
    ) external;

    /// @notice Cancel an existing schedule
    /// @param username The username to cancel schedule for
    function cancelSchedule(string calldata username) external;

    /// @notice Edit an existing schedule amount
    /// @param username The username to edit schedule for
    /// @param amount New amount per payment
    function editSchedule(string calldata username, uint256 amount) external;

    /// @notice Request payout from a schedule
    /// @param username The username to request payout for
    function requestSchedulePayout(string calldata username) external payable;

    /// @notice Get stream data for a username
    /// @param username The username to get stream for
    /// @return stream The stream data
    function getStream(string calldata username) external view returns (Stream memory stream);

    /// @notice Get schedule data for a username
    /// @param username The username to get schedule for
    /// @return schedule The schedule data
    function getSchedule(string calldata username) external view returns (Schedule memory schedule);
}
