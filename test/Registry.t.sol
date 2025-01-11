// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import "../src/core/AddressRegistry.sol";
import "../src/utils/Errors.sol";

contract RegistryTest is Test {
    Registry public registry;
    address public owner;
    address public nonOwner;
    address public userAddress;

    function setUp() public {
        owner = address(this); // The test contract is the owner
        nonOwner = address(0x1); // An arbitrary non-owner address
        userAddress = address(0x2); // A valid EOA address
        registry = new Registry();
    }

    function test_OnlyOwnerCanUpdateUserAddress() public {
        string memory username = "testuser";
        vm.prank(owner);
        registry.updateUserAddress(username, userAddress);
    }

    function test_SuccessfulUpdateAndRetrieveUserAddress() public {
        string memory username = "testuser";
        
        vm.prank(owner);
        registry.updateUserAddress(username, userAddress);

        address retrievedAddress = registry.getUserAddress(username);
        assertEq(retrievedAddress, userAddress, "User address mismatch");
    }

    function test_FailWhenUpdatingWithContractAddress() public {
        address contractAddress = address(new MockContract());

        vm.prank(owner);
        vm.expectRevert(Errors.IncompatibleUserAddress.selector);
        registry.updateUserAddress("testuser", contractAddress);
    }

    function test_FailWhenGettingUnregisteredUserAddress() public {
        string memory unregisteredUsername = "nonexistentuser";

        // Attempt to retrieve a user address that doesn't exist (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.UserNotFound.selector,
                unregisteredUsername
            )
        );
        registry.getUserAddress(unregisteredUsername);
    }
}

contract MockContract {
    // A mock contract to use its address in tests
}