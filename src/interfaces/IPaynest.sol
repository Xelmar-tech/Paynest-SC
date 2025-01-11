// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Paynest Interface
 * @dev Interface for interacting with the Paynest contract.
 * @notice Provides methods for managing supported tokens, deploying organizations, 
 *         and handling subscription fees.
 */
interface IPaynest {

    /**
     * @notice Emitted when a new organization is deployed.
     * @param orgAddress The address of the deployed organization contract.
     * @param orgName The name of the organization.
     */
    event OrgDeployed(address indexed orgAddress, string orgName);

    
    /**
     * @notice Adds support for a new token in the system.
     * @dev Allows the contract owner to add a token address 
     *      that can be used for transactions within the Paynest system.
     * @param tokenAddr The address of the token contract to be added as supported.
     * @custom:access Only callable by authorized addresses, typically the contract owner.
     */
    function addTokenSupport(address tokenAddr) external;

    /**
     * @notice Removes support for a previously added token.
     * @dev Allows the contract owner to remove a token address 
     *      that is no longer supported for transactions within the Paynest system.
     * @param tokenAddr The address of the token contract to be removed.
     * @custom:access Only callable by authorized addresses, typically the contract owner.
     * @custom:warning Ensure all transactions involving this token are settled 
     *                 before removing support to avoid disruptions.
     */
    function removeTokenSupport(address tokenAddr) external;

    /**
     * @notice Deploys a new organization within the Paynest system.
     * @dev Creates a new organization contract instance with the specified name 
     *      and links it to the Paynest system for payroll and subscription management.
     * @param orgName The name of the organization to be deployed.
     * @custom:access Callable by addresses yet to hit the limit of Orgs to create.
     */
    function deployOrganization(string calldata orgName) external;

    /**
     * @notice Claims or redeems accumulated subscription fees.
     * @dev Allows authorized addresses to withdraw fees collected in ETH
     *      from the Paynest system to the contract owner or treasury address.
     * @custom:access Only callable by authorized addresses, typically the contract owner.
     * @custom:security Ensures the caller is authorized and the token is supported.
     */
    function redeemSubscriptionFees() external;

    /**
     * @notice Returns the list of supported tokens.
     * @param token The address of the token contract to be checked.
     * @return Boolean to indicate if token is supported.
     */
    function isSupportedToken(address token) external view returns (bool);

    /**
     * @notice Checks if the caller is authorized for emergency withdrawal from the organization.
     * @dev This function checks whether the Paynest owner is allowed to emergency withdraw tokens
     *      from an organization's address in case of an emergency.
     *      Only a token not supported is allowed to be withdrawn.
     * @param caller The msg.sender from the Org contract.
     * @param tokenAddr The token address to withdraw from
     * @return True if the caller is the Paynest owner or authorized and token is not in list of supportedTokens, otherwise false.
     */
    function canEmergencyWithdraw(address caller, address tokenAddr) external view returns (bool);

    /**
     * @notice Retrieves the fixed subscription fee for the Paynest system.
     * @dev The returned value represents the base fee charged for maintaining active subscriptions.
     *      A value of 0 indicates that no fee is required.
     * @return The fixed subscription fee as an unsigned integer.
     */
    function getFixedFee() external view returns (uint);
}
