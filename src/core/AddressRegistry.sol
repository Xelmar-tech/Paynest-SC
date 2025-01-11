// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/IRegistry.sol";
import "../utils/Errors.sol";
import "../utils/Owner.sol";

contract Oracle is IRegistry, Owner, Errors {
    mapping(string => address) private userDirectory;

    constructor() Owner(msg.sender)  {}

    function isContract(address addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }


    function updateUserAddress(string calldata username, address userAddress) external override {
        onlyOwner();
        if (isContract(userAddress)) revert IncompatibleUserAddress();
        userDirectory[username] = userAddress;
        emit UserAddressUpdated(username, userAddress);
    }
    function getUserAddress(string calldata username) external view override returns (address) {
        address userAddress = userDirectory[username];
        if (userAddress == address(0)) revert UserNotFound(username);
        return userAddress;
    }
}
