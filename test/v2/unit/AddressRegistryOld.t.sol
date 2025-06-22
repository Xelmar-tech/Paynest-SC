// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddressRegistry} from "../../../src/v2/AddressRegistry.sol";
import {IRegistry} from "../../../src/v2/interfaces/IRegistry.sol";

contract AddressRegistryV2Test is Test {
    AddressRegistry public registry;

    address public constant ALICE = address(0xa);
    address public constant BOB = address(0xb);
    address public constant CAROL = address(0xc);

    event UsernameRegistered(string indexed username, address indexed controller, address indexed recipient);
    event RecipientUpdated(string indexed username, address indexed oldRecipient, address indexed newRecipient);
    event ControlTransferred(string indexed username, address indexed oldController, address indexed newController);

    function setUp() public {
        registry = new AddressRegistry();
    }

    // Basic Registration Tests

    function test_claimUsername_ValidUsername_ShouldRegisterSuccessfully() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, ALICE);
        assertEq(data.recipient, ALICE);
        assertTrue(data.lastUpdateTime > 0);
    }

    function test_claimUsername_ValidUsername_ShouldEmitUsernameRegistered() public {
        vm.expectEmit(true, true, true, true);
        emit UsernameRegistered("alice", ALICE, ALICE);

        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);
    }

    function test_claimUsername_SeparateControllerAndRecipient_ShouldAllowDifferentAddresses() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", BOB, ALICE);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, ALICE);
        assertEq(data.recipient, BOB);
    }

    function test_claimUsername_UsernameAlreadyExists_ShouldRevertWithUsernameAlreadyTaken() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        vm.expectRevert(AddressRegistry.UsernameAlreadyTaken.selector);
        vm.prank(BOB);
        registry.claimUsername("alice", BOB);
    }

    function test_claimUsername_ExplicitControllerUnauthorized_ShouldRevertWithUnauthorizedController() public {
        vm.expectRevert(AddressRegistry.UnauthorizedController.selector);
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE, BOB); // ALICE trying to set BOB as controller
    }

    function test_claimUsername_InvalidRecipient_ShouldRevertWithInvalidRecipient() public {
        vm.expectRevert(AddressRegistry.InvalidRecipient.selector);
        vm.prank(ALICE);
        registry.claimUsername("alice", address(0));
    }

    // Username Update Tests

    function test_updateRecipient_ValidUpdate_ShouldUpdateSuccessfully() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        vm.expectEmit(true, true, true, true);
        emit RecipientUpdated("alice", ALICE, BOB);

        vm.prank(ALICE);
        registry.updateRecipient("alice", BOB);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, ALICE);
        assertEq(data.recipient, BOB);
    }

    function test_updateRecipient_UnauthorizedCaller_ShouldRevertWithUnauthorizedController() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        vm.expectRevert(AddressRegistry.UnauthorizedController.selector);
        vm.prank(BOB);
        registry.updateRecipient("alice", BOB);
    }

    function test_updateRecipient_UsernameNotFound_ShouldRevertWithUsernameNotFound() public {
        vm.expectRevert(AddressRegistry.UsernameNotFound.selector);
        vm.prank(ALICE);
        registry.updateRecipient("alice", BOB);
    }

    function test_updateRecipient_ZeroAddress_ShouldRevertWithInvalidRecipient() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        vm.expectRevert(AddressRegistry.InvalidRecipient.selector);
        vm.prank(ALICE);
        registry.updateRecipient("alice", address(0));
    }

    // Control Transfer Tests

    function test_transferControl_ValidTransfer_ShouldTransferSuccessfully() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        vm.expectEmit(true, true, true, true);
        emit ControlTransferred("alice", ALICE, BOB);

        vm.prank(ALICE);
        registry.transferControl("alice", BOB);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, BOB);
        assertEq(data.recipient, ALICE); // Recipient should remain unchanged
    }

    function test_transferControl_UnauthorizedCaller_ShouldRevertWithUnauthorizedController() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        vm.expectRevert(AddressRegistry.UnauthorizedController.selector);
        vm.prank(BOB);
        registry.transferControl("alice", BOB);
    }

    function test_transferControl_UsernameNotFound_ShouldRevertWithUsernameNotFound() public {
        vm.expectRevert(AddressRegistry.UsernameNotFound.selector);
        vm.prank(ALICE);
        registry.transferControl("alice", BOB);
    }

    function test_transferControl_ZeroAddress_ShouldRevertWithInvalidController() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        vm.expectRevert(AddressRegistry.InvalidController.selector);
        vm.prank(ALICE);
        registry.transferControl("alice", address(0));
    }

    // View Function Tests

    function test_getUsernameData_ExistingUsername_ShouldReturnCorrectData() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", BOB, ALICE);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, ALICE);
        assertEq(data.recipient, BOB);
        assertTrue(data.lastUpdateTime > 0);
    }

    function test_getUsernameData_NonExistentUsername_ShouldReturnZeroValues() public {
        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, address(0));
        assertEq(data.recipient, address(0));
        assertEq(data.lastUpdateTime, 0);
    }

    function test_getRecipient_ExistingUsername_ShouldReturnRecipient() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", BOB, ALICE);

        assertEq(registry.getRecipient("alice"), BOB);
    }

    function test_getRecipient_NonExistentUsername_ShouldReturnZeroAddress() public {
        assertEq(registry.getRecipient("alice"), address(0));
    }

    function test_getController_ExistingUsername_ShouldReturnController() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", BOB, ALICE);

        assertEq(registry.getController("alice"), ALICE);
    }

    function test_getController_NonExistentUsername_ShouldReturnZeroAddress() public {
        assertEq(registry.getController("alice"), address(0));
    }

    function test_getUserAddress_ExistingUsername_ShouldReturnRecipient() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", BOB, ALICE);

        assertEq(registry.getUserAddress("alice"), BOB);
    }

    function test_getUserAddress_NonExistentUsername_ShouldReturnZeroAddress() public {
        assertEq(registry.getUserAddress("alice"), address(0));
    }

    function test_isUsernameAvailable_AvailableUsername_ShouldReturnTrue() public {
        assertTrue(registry.isUsernameAvailable("alice"));
    }

    function test_isUsernameAvailable_TakenUsername_ShouldReturnFalse() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        assertFalse(registry.isUsernameAvailable("alice"));
    }

    function test_getLastUpdate_ExistingUsername_ShouldReturnTimestamp() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        uint256 lastUpdate = registry.getLastUpdate("alice");
        assertTrue(lastUpdate > 0);
    }

    function test_getLastUpdate_NonExistentUsername_ShouldReturnZero() public {
        assertEq(registry.getLastUpdate("alice"), 0);
    }

    // Edge Case Tests

    function test_sameControllerAndRecipient_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, ALICE);
        assertEq(data.recipient, ALICE);
    }

    function test_multipleUsernamesWithSameRecipient_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", CAROL);

        vm.prank(BOB);
        registry.claimUsername("bob", CAROL);

        assertEq(registry.getRecipient("alice"), CAROL);
        assertEq(registry.getRecipient("bob"), CAROL);
    }

    function test_transferControlThenUpdateRecipient_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        // Transfer control to BOB
        vm.prank(ALICE);
        registry.transferControl("alice", BOB);

        // BOB should now be able to update recipient
        vm.prank(BOB);
        registry.updateRecipient("alice", CAROL);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, BOB);
        assertEq(data.recipient, CAROL);
    }

    function test_updateTimestampChanges_ShouldUpdateLastUpdateTime() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        IRegistry.UsernameData memory initialData = registry.getUsernameData("alice");
        uint256 initialTime = initialData.lastUpdateTime;

        vm.warp(block.timestamp + 1000);

        vm.prank(ALICE);
        registry.updateRecipient("alice", BOB);

        IRegistry.UsernameData memory updatedData = registry.getUsernameData("alice");
        assertTrue(updatedData.lastUpdateTime > initialTime);
    }

    // Meta-transaction Tests (Basic validation)

    function test_claimUsernameWithSignature_ExpiredDeadline_ShouldRevert() public {
        uint256 deadline = block.timestamp - 1; // Already expired

        vm.expectRevert(AddressRegistry.ExpiredSignature.selector);
        registry.claimUsernameWithSignature(
            "alice",
            ALICE,
            ALICE,
            deadline,
            0,
            0,
            0 // Invalid signature (will fail at deadline check first)
        );
    }

    function test_claimUsernameWithSignature_InvalidSignature_ShouldRevert() public {
        uint256 deadline = block.timestamp + 3600;

        vm.expectRevert("ECDSA: invalid signature");
        registry.claimUsernameWithSignature(
            "alice",
            ALICE,
            ALICE,
            deadline,
            0,
            0,
            0 // Invalid signature
        );
    }

    // Nonce Test

    function test_nonces_ShouldBeZeroInitially() public view {
        assertEq(registry.nonces(ALICE), 0);
        assertEq(registry.nonces(BOB), 0);
    }
}
