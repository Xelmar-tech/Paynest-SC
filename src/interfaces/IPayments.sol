// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

/**
 * @title Payments Interface
 * @dev Interface for interacting with the Payments contract, which handles payments and subscription management.
 */
interface IPayments {
    // Events
    event ScheduleActive(
        string username,
        address token,
        uint40 nextPayout,
        uint256 amount
    );
    event StreamActive(
        string username,
        address token,
        uint40 endDate,
        uint256 amount
    );

    /**
     * @dev Emitted when a payout is successfully processed.
     * @param username The username associated with the stream or schedule.
     * @param token The token address used for the payout.
     * @param amount The amount paid out.
     */
    event Payout(string username, address token, uint256 amount);

    /**
     * @dev Emitted when a payment stream is canceled.
     * @param username The username associated with the canceled stream.
     */
    event PaymentStreamCancelled(string username);

    /**
     * @dev Emitted when a payment schedule is canceled.
     * @param username The username associated with the canceled schedule.
     */
    event PaymentScheduleCancelled(string username);

    /**
     * @dev Emitted when a stream is updated with a new amount.
     * This event logs the updated stream information for a given username.
     *
     * @param username The username of the user whose stream has been updated.
     * @param amount The new amount set for the stream.
     */
    event StreamUpdated(string username, uint amount);

    /**
     * @dev Emitted when a payment schedule is updated with a new amount.
     * This event logs the updated schedule information for a given username.
     *
     * @param username The username of the user whose schedule has been updated.
     * @param amount The new amount set for the schedule.
     */
    event ScheduleUpdated(string username, uint amount);

    enum IntervalType {
        None,
        Weekly,
        Monthly,
        Quarterly,
        Yearly
    }

    /**
     * @dev Represents a scheduled payment, including both recurring and one-time payments.
        A mapping of username to this struct defines the payment
     * @param token The token address used for the payment.
     * @param nextPayout The timestamp when the next payment is due.
     * @param interval The interval between each payment is due.
     * @param isOneTime Indicates whether the payment is a one-time occurrence.
     * @param active Indicates whether the payment is active 
     * @param amount The amount to be paid per interval (e.g., monthly).
     */
    struct Schedule {
        address token;
        uint40 nextPayout;
        IntervalType interval;
        bool isOneTime;
        bool active;
        uint256 amount;
    }

    /**
     * @dev Represents a stream payment.
        A mapping of username to this struct defines the payment stream
     * @param token The token address used for the payment.
     * @param endDate The timestamp when the stream ends.
     * @param active Indicates whether the stream is active.
     * @param amount The amount to be streamed per second.
     * @param lastPayout The timestamp of the last payout.
     */
    struct Stream {
        address token;
        uint40 endDate;
        bool active;
        uint256 amount;
        uint40 lastPayout;
    }

    /**
     * @notice Creates a scheduled payment for a username
     * @param username The username to create the schedule for
     * @param amount The amount to be paid
     * @param token The token address to be used for payment
     * @param interval The interval between each scheduled payout
     * @param isOneTime A check to set schedule to go out once
     * @param firstPaymentDate Date of first payment
     */
    function createSchedule(
        string calldata username,
        uint256 amount,
        address token,
        IntervalType interval,
        bool isOneTime,
        uint40 firstPaymentDate
    ) external;

    /**
     * @notice Creates a stream payment for a username
     * @param username The username to create the stream for
     * @param amount The amount to be streamed
     * @param token The token address to be used for payment
     * @param endStream The timestamp when the stream should end
     */
    function createStream(
        string calldata username,
        uint256 amount,
        address token,
        uint40 endStream
    ) external;

    /**
     * @notice Retrieves the current stream details for a user.
     * @param username The username to query stream against.
     * @return stream The stream information.
     */
    function getStream(
        string calldata username
    ) external view returns (Stream memory stream);

    /**
     * @notice Retrieves the current schedule payment details for a user.
     * @param username The username to query schedule against.
     * @return schedule The schedule information.
     */
    function getSchedule(
        string calldata username
    ) external view returns (Schedule memory schedule);

    /**
     * @notice Requests a payout of accumulated funds.
     * @dev Allows anyone to request a payout of funds from the contract.
     * @param username The username of the recipient who will receive the payment.
     * @return payoutAmount The stream payout value.
     */
    function requestStreamPayout(
        string calldata username
    ) external payable returns (uint256 payoutAmount);

    /**
     * @notice Requests a payout of scheduled funds.
     * @dev Allows anyone to request a payout of funds from the contract.
     * @param username The username of the recipient who will receive the payment.
     */
    function requestSchedulePayout(string calldata username) external payable;

    /**
     * @notice Cancels an active payment stream.
     * @dev Disables the specified stream and stops further payouts.
     * @param username The username associated with the payment stream.
     */
    function cancelStream(string calldata username) external;

    /**
     * @notice Cancels an active payment schedule with prorated payout for the current interval.
     * @dev Computes and transfers the prorated amount for the current interval, then disables the schedule.
     * @param username The username associated with the payment schedule.
     * @param payIncomplete A check to tell contract to pay username according to prorated schedule.
     */
    function cancelSchedule(
        string calldata username,
        bool payIncomplete
    ) external;

    /**
     * @dev Edits the amount for an active stream for a given user.
     * Only the owner can call this function.
     * Reverts if the amount is zero or the payment stream is not active.
     *
     * @param username The username of the user whose stream is to be edited.
     * @param amount The new amount to set for the stream.
     *
     * Requirements:
     * - The caller must be the owner of the contract.
     * - The amount must be non-zero.
     * - The stream for the given username must be active.
     *
     * Emits:
     * - A `StreamUpdated` event with the updated stream information.
     */
    function editStream(string calldata username, uint amount) external;

    /**
     * @dev Edits the amount for a schedule payment for a given user.
     * Only the owner can call this function.
     * Reverts if the amount is zero, the payment schedule is not active, or the next payout is within 3 days.
     *
     * @param username The username of the user whose schedule is to be edited.
     * @param amount The new amount to set for the schedule.
     *
     * Requirements:
     * - The caller must be the owner of the contract.
     * - The amount must be non-zero.
     * - The schedule for the given username must be active.
     * - The time difference between the current timestamp and the next payout must be greater than 3 days.
     *
     * Emits:
     * - A `ScheduleUpdated` event with the updated schedule information.
     */
    function editSchedule(string calldata username, uint amount) external;
}

interface IPaynest {
    function getRegistry() external returns (address);
}
