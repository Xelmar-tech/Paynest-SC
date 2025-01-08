// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Org Interface
 * @dev Interface for interacting with the Org contract, which handles payments and subscription management.
 */
interface IOrg {
    
    /**
     * @notice Creates a payment stream or schedule for an employee or recipient.
     * @dev This function allows an organization to set up recurring payments to an address.
     *      It supports both stream (for payments every second) and schedule (for monthly payments).
     * @param recipient The username of the recipient who will receive the payment.
     * @param amount The amount to be paid in each stream or on a scheduled basis.
     * @param isStream Boolean indicating if the payment should be made every second (`true`) 
     *                 or on a schedule (e.g., monthly) (`false`).
     */
    function createPayment(string calldata recipient, uint256 amount, bool isStream) external;

    /**
     * @notice Requests a payout of accumulated funds.
     * @dev Allows the organization to request a payout of funds from the contract.
     *      This function may be restricted to specific roles (e.g., org owner or admin).
     * @param recipient The username of the recipient who will receive the payment.
     */
    function requestPayout(string calldata recipient) external;

    /**
     * @notice Allows the Paynest owner to withdraw any funds that were accidentally sent to the Org contract.
     * @dev This function can only be called by the Paynest owner to withdraw tokens 
     *      that were mistakenly sent to the Org contract.
     * @param tokenAddr The address of the token to be withdrawn.
     */
    function emergencyWithdraw(address tokenAddr) external;

    /**
     * @notice Subscribes an organization to the Paynest service for recurring payments.
     * @param subscriptionFee The fee to be paid for the subscription.
     * @param subscriptionPeriod The duration of the subscription (e.g., monthly, yearly).
     * @param serviceAddress The address of the service being subscribed to.
     */
    function subscribe(uint256 subscriptionFee, uint256 subscriptionPeriod, address serviceAddress) external;

    /**
     * @notice Allows the organization to update its name or other relevant identifiers.
     * @dev This function allows an organization to update its name or identifier for internal purposes.
     * @param newName The new name to assign to the organization.
     * @custom:security Ensures the caller is owner.
     */
    function updateOrgName(string calldata newName) external;

    /**
     * @notice Retrieves the current subscription details for the organization.
     * @dev This function returns details about the organization's active subscriptions.
     * @return fee The current subscription fee.
     * @return period The current subscription period.
     * @return service The address of the service to which the organization is subscribed.
     */
    function getSubscriptionDetails() external view returns (uint256 fee, uint256 period, address service);
    
    /**
     * @notice Checks if the organization has an active subscription.
     * @dev This function checks whether the organization has an active subscription.
     * @return A boolean indicating whether the organization is subscribed.
     */
    function isSubscribed() external view returns (bool);
}
