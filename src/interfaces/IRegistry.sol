// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Address Registry Interface
 * @dev Interface for interacting with the Registry contract that updates user wallet addresses.
 */
interface IRegistry {

    // Event for address update
    event UserAddressUpdated(string indexed username, address newAddress);

    /**
     * @notice Updates the wallet address for a given username.
     * @dev This function allows an authorized address to update the mapping of username to wallet address.
     *      Only specific addresses (e.g., admin or authorized addresses) can call this function.
     * @param username The username whose wallet address needs to be updated.
     * @param userAddress The new wallet address to associate with the username.
     */
    function updateUserAddress(string calldata username, address userAddress) external;

    /**
     * @notice Retrieves the wallet address associated with a given username.
     * @dev This function allows anyone to check the wallet address associated with a specific username.
     * @param username The username whose wallet address is to be retrieved.
     * @return The wallet address associated with the username.
     */
    function getUserAddress(string calldata username) external view returns (address);
    
}
