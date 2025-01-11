// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Org Interface
 * @dev Interface for interacting with the Org contract, which handles payments and subscription management.
 */
interface IOrg {
    /**
     * @dev Represents a scheduled payment, including both recurring and one-time payments.
        A mapping of username to this struct defines the payment
     * @param token The token address used for the payment.
     * @param nextPayout The timestamp when the next payment is due.
     * @param isOneTime Indicates whether the payment is a one-time occurrence.
     * @param active Indicates whether the payment is active 
     * @param amount The amount to be paid per interval (e.g., monthly).
     */
    struct Schedule {
        address token;
        uint40 nextPayout;
        bool isOneTime;
        bool active;
        uint256 amount;
    }

    /**
     * @dev Represents a real-time payment stream.
     * @param amount The rate of payment in tokens per second.
     * @param token The token address used for the stream payments.
     * @param lastPayout The timestamp of the last payment update.
     * @param endStream The timestamp when the stream ends.
     * @param active Indicates whether the stream is currently active.
     */
    struct Stream {
        uint256 amount;
        address token;
        uint40 lastPayout;
        uint40 endStream;
        bool active;
    }

    /**
     * @dev Emitted when a payment schedule becomes active.
     * @param username The username associated with the payment schedule.
      * @param token The address of the token used for the payments.
     * @param nextPayout The timestamp of the next scheduled payout.
     * @param amount The amount to be paid at the next payout.
     */
    event PaymentScheduleActive(
        string indexed username,
        address indexed token,
        uint40 indexed nextPayout,
        uint256 amount
    );
    
    /**
     * @dev Emitted when a payment stream becomes active.
     * @param username The username associated with the payment stream.
     * @param token The address of the token used for the payments.
     * @param startStream The timestamp of the stream payout.
     * @param amount The amount to be paid at the next payout.
     */
    event PaymentStreamActive(
        string indexed username,
        address indexed token,
        uint40 indexed startStream,
        uint256 amount
    );


    /**
     * @dev Emitted when a payout is successfully processed.
     * @param username The username associated with the stream.
     * @param token The token address used for the payout.
     * @param amount The amount paid out.
     */
    event Payout(string indexed username, address indexed token, uint256 amount);

    /**
     * @dev Emitted when a payment stream is canceled.
     * @param username The username associated with the canceled stream.
     */
    event PaymentStreamCancelled(string indexed username);

    /**
     * @dev Emitted when a payment schedule is canceled.
     * @param username The username associated with the canceled schedule.
     */
    event PaymentScheduleCancelled(string indexed username);

    /**
     * @notice Event for Organization Name tracking Off chain
     * @param name The new name of the org
     */
    event OrgNameChange(string name);
    event ETHReceived(string name, uint amount);

    
    /**
     * @notice Creates a payment stream or schedule for an employee or recipient.
     * @dev This function allows an organization to set up recurring payments to an address.
     *      It supports both stream (for payments every second) and schedule (for monthly payments).
     * @param username The username of the recipient who will receive the payment.
     * @param amount The amount to be paid on a scheduled basis.
     * @param token Address of token to pay in
     * @param oneTimePayoutDate Timestamp of a payment to be made once
            As would a contractor payment would be made.
     */
    function createSchedule(string calldata username, uint256 amount, address token, uint40 oneTimePayoutDate) external payable;

    /**
     * @notice Creates a real-time payment stream for a recipient.
     * @dev Sets up a stream that pays tokens to a recipient every second, starting immediately and ending at a specified time.
     * @param username The username of the recipient who will receive the stream.
     * @param amount The amount of tokens paid to the recipient every second.
     * @param token The address of the token to be streamed.
     * @param endStream The timestamp when the stream ends.
     */
    function createStream(string calldata username, uint256 amount, address token, uint40 endStream) external payable;

    /**
     * @notice Requests a payout of accumulated funds.
     * @dev Allows anyone to request a payout of funds from the contract.
     * @param username The username of the recipient who will receive the payment.
     */
    function requestStreamPayout(string calldata username) external payable;

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
     */
    function cancelSchedule(string calldata username) external;


    /**
     * @notice Allows the Paynest owner to withdraw any funds that were accidentally sent to the Org contract.
     * @dev This function can only be called by the Paynest owner to withdraw tokens 
     *      that were mistakenly sent to the Org contract.
     * @param tokenAddr The address of the token to be withdrawn.
     */
    function emergencyWithdraw(address tokenAddr) external;

    /**
     * @notice Allows the organization to update its name or other relevant identifiers.
     * @dev This function allows an organization to update its name or identifier for internal purposes.
     * @param newName The new name to assign to the organization.
     * @custom:security Ensures the caller is owner.
     */
    function updateOrgName(string calldata newName) external;

    /**
     * @notice Retrieves the current subscription details for the organization.
     * @dev This function returns details about the organization's active subscription.
     * @return period The current subscription period.
     */
    function getSubscriptionDetails() external view returns (uint256 period);
}
