// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IRegistry.sol";
import "./util/Errors.sol";

contract Registry is IRegistry, Errors {
    mapping(string => address) private userDirectory;
    mapping(string => address) private userWalletDirectory;

    function isContract(address addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function claimUsername(string calldata _username) public {
        if (!isUsernameAvailable(_username)) {
            revert UsernameAlreadyClaimed(_username);
        }
        userDirectory[_username] = msg.sender;
        emit UsernameClaimed(_username, msg.sender);
    }

    function isUsernameAvailable(
        string calldata _username
    ) public view returns (bool) {
        if (bytes(_username).length == 0) {
            revert EmptyUsernameNotAllowed();
        }
        return userDirectory[_username] == address(0);
    }

    function updateUserAddress(
        string calldata username,
        address userAddress
    ) external override {
        if (isContract(userAddress)) revert IncompatibleUserAddress();
        if (userAddress == address(0)) revert IncompatibleUserAddress();
        address claimor = userDirectory[username];
        if (msg.sender != claimor) revert UserNotClaimor();
        userWalletDirectory[username] = userAddress;
        emit UserAddressUpdated(username, userAddress);
    }

    function getUserAddress(
        string calldata username
    ) external view override returns (address) {
        address userAddress = userWalletDirectory[username];
        if (userAddress == address(0)) revert UserNotFound(username);
        return userAddress;
    }
}
