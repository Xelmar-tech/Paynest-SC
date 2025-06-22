// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {ForkTestBaseV2} from "../lib/ForkTestBaseV2.sol";
import {PaymentsForkBuilderV2} from "../builders/PaymentsForkBuilderV2.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

import {PaymentsPluginSetup} from "../../../src/v2/setup/PaymentsPluginSetup.sol";
import {PaymentsPlugin} from "../../../src/v2/PaymentsPlugin.sol";
import {AddressRegistry} from "../../../src/v2/AddressRegistry.sol";
import {IRegistry} from "../../../src/v2/interfaces/IRegistry.sol";
import {ILlamaPayFactory} from "../../../src/v2/interfaces/ILlamaPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AddressRegistryForkTest is ForkTestBaseV2 {
    DAO internal dao;
    PaymentsPlugin internal plugin;
    PluginRepo internal repo;
    PaymentsPluginSetup internal setup;
    AddressRegistry internal registry;
    ILlamaPayFactory internal llamaPayFactory;
    IERC20 internal usdc;

    string constant TEST_USERNAME = "alice";
    string constant TEST_USERNAME2 = "bob_test";

    // Events to test
    event UsernameRegistered(string indexed username, address indexed controller, address indexed recipient);
    event RecipientUpdated(string indexed username, address indexed oldRecipient, address indexed newRecipient);
    event ControlTransferred(string indexed username, address indexed oldController, address indexed newController);

    function setUp() public virtual override {
        super.setUp();

        // Build the fork test environment using DAOFactory pattern
        (dao, repo, setup, plugin, registry, llamaPayFactory, usdc) = new PaymentsForkBuilderV2().withManager(bob).build();
    }

    modifier givenTestingRegistryDeployment() {
        _;
    }

    function test_GivenTestingRegistryDeployment() external givenTestingRegistryDeployment {
        // It should deploy registry successfully
        assertTrue(address(registry) != address(0));
        
        // It should integrate with plugin correctly
        assertEq(address(plugin.registry()), address(registry));
    }

    function test_WhenClaimingUsernameOnFork() external givenTestingRegistryDeployment {
        // It should work with real deployment
        vm.expectEmit(true, true, true, true);
        emit UsernameRegistered(TEST_USERNAME, alice, alice);
        
        vm.prank(alice);
        registry.claimUsername(TEST_USERNAME, alice);
        
        // Verify registration worked
        IRegistry.UsernameData memory data = registry.getUsernameData(TEST_USERNAME);
        assertEq(data.controller, alice);
        assertEq(data.recipient, alice);
        assertTrue(data.lastUpdateTime > 0);
        assertFalse(registry.isUsernameAvailable(TEST_USERNAME));
    }

    function test_WhenClaimingUsernameWithControllerRecipientSeparation() external givenTestingRegistryDeployment {
        // It should allow controller/recipient separation
        vm.expectEmit(true, true, true, true);
        emit UsernameRegistered(TEST_USERNAME, alice, bob);
        
        vm.prank(alice);
        registry.claimUsername(TEST_USERNAME, bob, alice);
        
        // Verify separation worked
        IRegistry.UsernameData memory data = registry.getUsernameData(TEST_USERNAME);
        assertEq(data.controller, alice);
        assertEq(data.recipient, bob);
        
        // Verify view functions work correctly
        assertEq(registry.getController(TEST_USERNAME), alice);
        assertEq(registry.getRecipient(TEST_USERNAME), bob);
        assertEq(registry.getUserAddress(TEST_USERNAME), bob); // V1 compatibility
    }

    function test_WhenUpdatingRecipientOnFork() external givenTestingRegistryDeployment {
        // Setup: Alice claims username with herself as recipient
        vm.prank(alice);
        registry.claimUsername(TEST_USERNAME, alice);
        
        // It should update recipient successfully
        vm.expectEmit(true, true, true, true);
        emit RecipientUpdated(TEST_USERNAME, alice, carol);
        
        vm.prank(alice);
        registry.updateRecipient(TEST_USERNAME, carol);
        
        // Verify update worked
        IRegistry.UsernameData memory data = registry.getUsernameData(TEST_USERNAME);
        assertEq(data.controller, alice);
        assertEq(data.recipient, carol);
    }

    function test_WhenTransferringControlOnFork() external givenTestingRegistryDeployment {
        // Setup: Alice claims username
        vm.prank(alice);
        registry.claimUsername(TEST_USERNAME, alice);
        
        // It should transfer control successfully
        vm.expectEmit(true, true, true, true);
        emit ControlTransferred(TEST_USERNAME, alice, bob);
        
        vm.prank(alice);
        registry.transferControl(TEST_USERNAME, bob);
        
        // Verify transfer worked
        IRegistry.UsernameData memory data = registry.getUsernameData(TEST_USERNAME);
        assertEq(data.controller, bob);
        assertEq(data.recipient, alice); // Recipient unchanged
        
        // Bob should now be able to update recipient
        vm.prank(bob);
        registry.updateRecipient(TEST_USERNAME, carol);
        
        data = registry.getUsernameData(TEST_USERNAME);
        assertEq(data.recipient, carol);
    }

    function test_WhenValidatingUsernamesOnFork() external givenTestingRegistryDeployment {
        // It should enforce V2 validation rules
        
        // Valid usernames should work
        vm.prank(alice);
        registry.claimUsername("abc", alice); // Minimum length
        
        vm.prank(bob);
        registry.claimUsername("abcdefghijklmnopqrst", bob); // Maximum length
        
        vm.prank(carol);
        registry.claimUsername("user_123", carol); // Mixed valid chars
        
        // Invalid usernames should fail
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(david);
        registry.claimUsername("ab", david); // Too short
        
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(david);
        registry.claimUsername("abcdefghijklmnopqrstuvwxyz", david); // Too long
        
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(david);
        registry.claimUsername("1alice", david); // Starts with number
        
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(david);
        registry.claimUsername("alice__bob", david); // Consecutive underscores
    }

    function test_WhenMultipleUsersClaimUsernames() external givenTestingRegistryDeployment {
        // It should handle multiple users correctly
        
        // Multiple users claim different usernames
        vm.prank(alice);
        registry.claimUsername("alice", alice);
        
        vm.prank(bob);
        registry.claimUsername("bob_test", bob);
        
        vm.prank(carol);
        registry.claimUsername("carol123", carol);
        
        // Verify all registrations
        assertEq(registry.getController("alice"), alice);
        assertEq(registry.getController("bob_test"), bob);
        assertEq(registry.getController("carol123"), carol);
        
        assertEq(registry.getRecipient("alice"), alice);
        assertEq(registry.getRecipient("bob_test"), bob);
        assertEq(registry.getRecipient("carol123"), carol);
        
        // Verify availability checks
        assertFalse(registry.isUsernameAvailable("alice"));
        assertFalse(registry.isUsernameAvailable("bob_test"));
        assertFalse(registry.isUsernameAvailable("carol123"));
        assertTrue(registry.isUsernameAvailable("david"));
    }

    function test_WhenHandlingComplexWorkflows() external givenTestingRegistryDeployment {
        // It should handle complex real-world scenarios
        
        // 1. Alice claims username with separated controller/recipient
        vm.prank(alice);
        registry.claimUsername("alice", bob, alice);
        
        // 2. Alice transfers control to Bob
        vm.prank(alice);
        registry.transferControl("alice", bob);
        
        // 3. Bob updates recipient to Carol
        vm.prank(bob);
        registry.updateRecipient("alice", carol);
        
        // 4. Bob transfers control back to Alice
        vm.prank(bob);
        registry.transferControl("alice", alice);
        
        // Final verification
        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, alice);
        assertEq(data.recipient, carol);
        assertTrue(data.lastUpdateTime > 0);
    }

    function test_WhenCheckingGasUsageOnFork() external givenTestingRegistryDeployment {
        // It should have reasonable gas usage
        
        uint256 gasBefore = gasleft();
        vm.prank(alice);
        registry.claimUsername("alice", alice);
        uint256 gasUsed = gasBefore - gasleft();
        
        // Gas usage should be reasonable (less than 150k for simple claim)
        assertTrue(gasUsed < 150000, "Gas usage too high for username claim");
        
        // Verify functionality still works
        assertEq(registry.getRecipient("alice"), alice);
    }
}