// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

/// @title IRegistryV1
/// @notice Interface for username-to-address registry functionality
/// @dev Defines the core functions for managing username registrations and address resolution
interface IRegistryV1 {
    /// @notice Address history structure for tracking current and previous addresses
    struct AddressHistory {
        address currentAddress;
        address previousAddress;
        uint256 lastChangeTime;
    }

    /// @notice Emitted when a username is claimed by an address
    /// @param username The username that was claimed
    /// @param claimor The address that claimed the username
    event UsernameClaimed(string indexed username, address indexed claimor);

    /// @notice Emitted when a username's associated address is updated
    /// @param username The username whose address was updated
    /// @param newAddress The new address associated with the username
    event UserAddressUpdated(string indexed username, address indexed newAddress);

    /// @notice Get the address associated with a username
    /// @param username The username to resolve
    /// @return The address associated with the username, or zero address if not found
    function getUserAddress(string calldata username) external view returns (address);

    /// @notice Get the address history for a username
    /// @param username The username to get history for
    /// @return The complete address history
    function getAddressHistory(string calldata username) external view returns (AddressHistory memory);

    /// @notice Update the address associated with a username
    /// @param username The username to update
    /// @param userAddress The new address to associate with the username
    /// @dev Only the current owner of the username can call this function
    function updateUserAddress(string calldata username, address userAddress) external;
}
