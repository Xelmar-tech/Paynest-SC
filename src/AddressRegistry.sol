// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {IRegistry} from "./interfaces/IRegistry.sol";

/// @title AddressRegistry
/// @notice A simple, global contract that manages username-to-address mappings for the PayNest ecosystem
/// @dev Implements the IRegistry interface and provides basic username claiming and address resolution functionality
contract AddressRegistry is IRegistry {
    /// @notice Maps usernames to their address history
    mapping(string => AddressHistory) public userAddresses;

    /// @notice Maps addresses to their claimed username
    mapping(address => string) public addressToUsername;

    /// @notice Custom errors for gas-efficient error handling

    error UsernameAlreadyClaimed();
    error AddressAlreadyHasUsername();
    error NotUsernameOwner();
    error UsernameEmpty();
    error UsernameTooLong();
    error InvalidAddress();
    error UsernameCannotStartWithUnderscore();
    error UsernameCannotStartWithNumber();
    error InvalidCharacterInUsername(bytes1 char, uint256 position);

    /// @notice Claim a username for the calling address
    /// @param username The username to claim (1-32 chars, alphanumeric + underscore, must start with letter)
    /// @dev Each address can only claim one username, and each username can only be claimed once
    function claimUsername(string calldata username) external {
        _validateUsername(username);

        if (userAddresses[username].currentAddress != address(0)) {
            revert UsernameAlreadyClaimed();
        }

        if (bytes(addressToUsername[msg.sender]).length != 0) {
            revert AddressAlreadyHasUsername();
        }

        // Store address history and bidirectional mapping
        userAddresses[username] =
            AddressHistory({currentAddress: msg.sender, previousAddress: address(0), lastChangeTime: block.timestamp});
        addressToUsername[msg.sender] = username;

        emit UsernameClaimed(username, msg.sender);
    }

    /// @notice Update the address associated with a username
    /// @param username The username to update
    /// @param userAddress The new address to associate with the username
    /// @dev Only the current owner of the username can call this function
    function updateUserAddress(string calldata username, address userAddress) external {
        if (userAddresses[username].currentAddress != msg.sender) {
            revert NotUsernameOwner();
        }

        if (userAddress == address(0)) {
            revert InvalidAddress();
        }

        if (bytes(addressToUsername[userAddress]).length != 0) {
            revert AddressAlreadyHasUsername();
        }

        address previousAddress = userAddresses[username].currentAddress;

        // Clear old address mapping
        delete addressToUsername[msg.sender];

        // Update address history
        userAddresses[username] = AddressHistory({
            currentAddress: userAddress,
            previousAddress: previousAddress,
            lastChangeTime: block.timestamp
        });

        // Update new address mapping
        addressToUsername[userAddress] = username;

        emit UserAddressUpdated(username, userAddress);
    }

    /// @notice Get the address associated with a username
    /// @param username The username to resolve
    /// @return The address associated with the username, or zero address if not found
    function getUserAddress(string calldata username) external view returns (address) {
        return userAddresses[username].currentAddress;
    }

    /// @notice Get the address history for a username
    /// @param username The username to get history for
    /// @return The complete address history
    function getAddressHistory(string calldata username) external view returns (AddressHistory memory) {
        return userAddresses[username];
    }

    /// @notice Check if a username is available for claiming
    /// @param username The username to check
    /// @return True if the username is available, false otherwise
    function isUsernameAvailable(string calldata username) external view returns (bool) {
        return userAddresses[username].currentAddress == address(0);
    }

    /// @notice Get the username claimed by an address
    /// @param userAddress The address to look up
    /// @return The username claimed by the address, or empty string if none
    function getUsernameByAddress(address userAddress) external view returns (string memory) {
        return addressToUsername[userAddress];
    }

    /// @notice Check if an address has claimed a username
    /// @param userAddress The address to check
    /// @return True if the address has claimed a username, false otherwise
    function hasUsername(address userAddress) external view returns (bool) {
        return bytes(addressToUsername[userAddress]).length != 0;
    }

    /// @notice Validate username format according to PayNest rules
    /// @param username The username to validate
    /// @dev Internal function that enforces all username validation rules
    function _validateUsername(string calldata username) internal pure {
        bytes memory usernameBytes = bytes(username);
        uint256 length = usernameBytes.length;

        if (length == 0) {
            revert UsernameEmpty();
        }

        if (length > 32) {
            revert UsernameTooLong();
        }

        // Check first character must be a letter
        bytes1 firstChar = usernameBytes[0];
        if (!_isLetter(firstChar)) {
            if (firstChar == "_") {
                revert UsernameCannotStartWithUnderscore();
            } else if (_isDigit(firstChar)) {
                revert UsernameCannotStartWithNumber();
            } else {
                revert InvalidCharacterInUsername(firstChar, 0);
            }
        }

        // Check all characters are valid (alphanumeric + underscore)
        for (uint256 i = 0; i < length; i++) {
            bytes1 char = usernameBytes[i];
            if (!_isValidUsernameChar(char)) {
                revert InvalidCharacterInUsername(char, i);
            }
        }
    }

    /// @notice Check if a character is a letter (a-z, A-Z)
    /// @param char The character to check
    /// @return True if the character is a letter
    function _isLetter(bytes1 char) internal pure returns (bool) {
        return (char >= "a" && char <= "z") || (char >= "A" && char <= "Z");
    }

    /// @notice Check if a character is a digit (0-9)
    /// @param char The character to check
    /// @return True if the character is a digit
    function _isDigit(bytes1 char) internal pure returns (bool) {
        return char >= "0" && char <= "9";
    }

    /// @notice Check if a character is valid for usernames (alphanumeric + underscore)
    /// @param char The character to check
    /// @return True if the character is valid
    function _isValidUsernameChar(bytes1 char) internal pure returns (bool) {
        return _isLetter(char) || _isDigit(char) || char == "_";
    }
}
