// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/IOracle.sol";
import {LibString} from "@solmate-utils/LibString.sol";
import "solmate/auth/authorities/RolesAuthority.sol";

contract Oracle is IOracle {
    
    // Mapping from username to wallet address
    mapping(string => address) private userAddresses;
    
    // List of authorized addresses (could be a contract owner or specific admin addresses)
    address public admin;

    modifier onlyAuthorized() {
        require(msg.sender == admin, "Not authorized");
        _;
    }

    constructor(address _admin) {
        admin = _admin;  // Set the contract admin on deployment
    }

    /**
     * @notice Updates the wallet address for a given username.
     * @dev Restricted to authorized addresses only.
     */
    function updateUserAddress(string calldata username, address userAddress) external override onlyAuthorized {
        userAddresses[username] = userAddress;
    }

    /**
     * @notice Retrieves the wallet address associated with a given username.
     */
    function getUserAddress(string calldata username) external view override returns (address) {
        return userAddresses[username];
    }
}
