// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddressRegistry} from "../../../src/v2/AddressRegistry.sol";
import {IRegistry} from "../../../src/v2/interfaces/IRegistry.sol";

contract AddressRegistryExpandedTest is Test {
    AddressRegistry public registry;

    address public constant ALICE = address(0xa);
    address public constant BOB = address(0xb);
    address public constant CAROL = address(0xc);
    address public constant DAVE = address(0xd);

    event UsernameRegistered(string indexed username, address indexed controller, address indexed recipient);
    event RecipientUpdated(string indexed username, address indexed oldRecipient, address indexed newRecipient);
    event ControlTransferred(string indexed username, address indexed oldController, address indexed newController);

    function setUp() public {
        registry = new AddressRegistry();
    }

    // =========================================================================
    // Username Validation Tests (V2 Enhanced Rules)
    // =========================================================================

    function test_claimUsername_TooShort_ShouldRevertWithInvalidUsername() public {
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(ALICE);
        registry.claimUsername("ab", ALICE); // Only 2 characters, minimum is 3
    }

    function test_claimUsername_TooLong_ShouldRevertWithInvalidUsername() public {
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(ALICE);
        registry.claimUsername("abcdefghijklmnopqrstuvwxyz", ALICE); // 26 characters, maximum is 20
    }

    function test_claimUsername_StartsWithNumber_ShouldRevertWithInvalidUsername() public {
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(ALICE);
        registry.claimUsername("1alice", ALICE); // Cannot start with number
    }

    function test_claimUsername_StartsWithUnderscore_ShouldRevertWithInvalidUsername() public {
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(ALICE);
        registry.claimUsername("_alice", ALICE); // Cannot start with underscore
    }

    function test_claimUsername_EndsWithUnderscore_ShouldRevertWithInvalidUsername() public {
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(ALICE);
        registry.claimUsername("alice_", ALICE); // Cannot end with underscore
    }

    function test_claimUsername_ConsecutiveUnderscores_ShouldRevertWithInvalidUsername() public {
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(ALICE);
        registry.claimUsername("alice__bob", ALICE); // No consecutive underscores
    }

    function test_claimUsername_UppercaseLetters_ShouldRevertWithInvalidUsername() public {
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(ALICE);
        registry.claimUsername("Alice", ALICE); // No uppercase letters
    }

    function test_claimUsername_SpecialCharacters_ShouldRevertWithInvalidUsername() public {
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(ALICE);
        registry.claimUsername("alice-bob", ALICE); // No special characters except underscore
    }

    function test_claimUsername_SpaceCharacters_ShouldRevertWithInvalidUsername() public {
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(ALICE);
        registry.claimUsername("alice bob", ALICE); // No spaces
    }

    function test_claimUsername_EmptyString_ShouldRevertWithInvalidUsername() public {
        vm.expectRevert(AddressRegistry.InvalidUsername.selector);
        vm.prank(ALICE);
        registry.claimUsername("", ALICE); // Empty string
    }

    function test_claimUsername_ValidUsername_MinimumLength_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("abc", ALICE); // 3 characters (minimum)
        
        assertEq(registry.getRecipient("abc"), ALICE);
    }

    function test_claimUsername_ValidUsername_MaximumLength_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("abcdefghijklmnopqrst", ALICE); // 20 characters (maximum)
        
        assertEq(registry.getRecipient("abcdefghijklmnopqrst"), ALICE);
    }

    function test_claimUsername_ValidUsername_WithNumbers_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice123", ALICE);
        
        assertEq(registry.getRecipient("alice123"), ALICE);
    }

    function test_claimUsername_ValidUsername_WithUnderscore_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice_bob", ALICE);
        
        assertEq(registry.getRecipient("alice_bob"), ALICE);
    }

    function test_claimUsername_ValidUsername_MixedValid_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("user_123", ALICE);
        
        assertEq(registry.getRecipient("user_123"), ALICE);
    }

    // =========================================================================
    // Registration Success Path Tests
    // =========================================================================

    function test_claimUsername_ValidUsernameAvailable_ShouldClaimSuccessfully() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, ALICE);
        assertEq(data.recipient, ALICE);
        assertTrue(data.lastUpdateTime > 0);
        assertFalse(registry.isUsernameAvailable("alice"));
    }

    function test_claimUsername_ValidUsernameAvailable_ShouldEmitUsernameRegistered() public {
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

    function test_claimUsername_SeparateControllerAndRecipient_ShouldEmitCorrectEvent() public {
        vm.expectEmit(true, true, true, true);
        emit UsernameRegistered("alice", ALICE, BOB);

        vm.prank(ALICE);
        registry.claimUsername("alice", BOB, ALICE);
    }

    // =========================================================================
    // Registration Failure Tests
    // =========================================================================

    function test_claimUsername_UsernameAlreadyTaken_ShouldRevertWithUsernameAlreadyTaken() public {
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

    function test_claimUsername_InvalidRecipientZeroAddress_ShouldRevertWithInvalidRecipient() public {
        vm.expectRevert(AddressRegistry.InvalidRecipient.selector);
        vm.prank(ALICE);
        registry.claimUsername("alice", address(0));
    }

    function test_claimUsername_ExplicitInvalidRecipientZeroAddress_ShouldRevertWithInvalidRecipient() public {
        vm.expectRevert(AddressRegistry.InvalidRecipient.selector);
        vm.prank(ALICE);
        registry.claimUsername("alice", address(0), ALICE);
    }

    // =========================================================================
    // Recipient Update Tests
    // =========================================================================

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

    function test_updateRecipient_ValidUpdate_ShouldUpdateTimestamp() public {
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

    function test_updateRecipient_SameAddress_ShouldStillWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        vm.expectEmit(true, true, true, true);
        emit RecipientUpdated("alice", ALICE, ALICE);

        vm.prank(ALICE);
        registry.updateRecipient("alice", ALICE);
    }

    // =========================================================================
    // Control Transfer Tests
    // =========================================================================

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

    function test_transferControl_ValidTransfer_ShouldUpdateTimestamp() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        IRegistry.UsernameData memory initialData = registry.getUsernameData("alice");
        uint256 initialTime = initialData.lastUpdateTime;

        vm.warp(block.timestamp + 1000);

        vm.prank(ALICE);
        registry.transferControl("alice", BOB);

        IRegistry.UsernameData memory updatedData = registry.getUsernameData("alice");
        assertTrue(updatedData.lastUpdateTime > initialTime);
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

    function test_transferControl_SameController_ShouldStillWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        vm.expectEmit(true, true, true, true);
        emit ControlTransferred("alice", ALICE, ALICE);

        vm.prank(ALICE);
        registry.transferControl("alice", ALICE);
    }

    // =========================================================================
    // View Function Tests
    // =========================================================================

    function test_getUsernameData_ExistingUsername_ShouldReturnCorrectData() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", BOB, ALICE);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, ALICE);
        assertEq(data.recipient, BOB);
        assertTrue(data.lastUpdateTime > 0);
    }

    function test_getUsernameData_NonExistentUsername_ShouldReturnZeroValues() public view {
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

    function test_getRecipient_NonExistentUsername_ShouldReturnZeroAddress() public view {
        assertEq(registry.getRecipient("alice"), address(0));
    }

    function test_getController_ExistingUsername_ShouldReturnController() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", BOB, ALICE);

        assertEq(registry.getController("alice"), ALICE);
    }

    function test_getController_NonExistentUsername_ShouldReturnZeroAddress() public view {
        assertEq(registry.getController("alice"), address(0));
    }

    function test_getUserAddress_ExistingUsername_ShouldReturnRecipient() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", BOB, ALICE);

        assertEq(registry.getUserAddress("alice"), BOB);
    }

    function test_getUserAddress_NonExistentUsername_ShouldReturnZeroAddress() public view {
        assertEq(registry.getUserAddress("alice"), address(0));
    }

    function test_isUsernameAvailable_AvailableUsername_ShouldReturnTrue() public view {
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

    function test_getLastUpdate_NonExistentUsername_ShouldReturnZero() public view {
        assertEq(registry.getLastUpdate("alice"), 0);
    }

    // =========================================================================
    // Complex Workflow Tests
    // =========================================================================

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

    function test_transferControlThenTransferAgain_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        // Transfer control to BOB
        vm.prank(ALICE);
        registry.transferControl("alice", BOB);

        // BOB transfers control to CAROL
        vm.prank(BOB);
        registry.transferControl("alice", CAROL);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, CAROL);
        assertEq(data.recipient, ALICE); // Original recipient unchanged
    }

    function test_multipleUsernamesWithSameRecipient_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", CAROL);

        vm.prank(BOB);
        registry.claimUsername("bob", CAROL);

        assertEq(registry.getRecipient("alice"), CAROL);
        assertEq(registry.getRecipient("bob"), CAROL);
        assertEq(registry.getController("alice"), ALICE);
        assertEq(registry.getController("bob"), BOB);
    }

    function test_multipleUsernamesWithSameController_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE, ALICE);

        vm.prank(ALICE);
        registry.claimUsername("alice2", BOB, ALICE);

        assertEq(registry.getController("alice"), ALICE);
        assertEq(registry.getController("alice2"), ALICE);
        assertEq(registry.getRecipient("alice"), ALICE);
        assertEq(registry.getRecipient("alice2"), BOB);
    }

    function test_sameControllerAndRecipient_ShouldWork() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        IRegistry.UsernameData memory data = registry.getUsernameData("alice");
        assertEq(data.controller, ALICE);
        assertEq(data.recipient, ALICE);
    }

    function test_updateTimestampChanges_ShouldUpdateOnAllOperations() public {
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE);

        IRegistry.UsernameData memory initialData = registry.getUsernameData("alice");
        uint256 initialTime = initialData.lastUpdateTime;

        // Test recipient update
        vm.warp(block.timestamp + 1000);
        vm.prank(ALICE);
        registry.updateRecipient("alice", BOB);

        IRegistry.UsernameData memory afterRecipientUpdate = registry.getUsernameData("alice");
        assertTrue(afterRecipientUpdate.lastUpdateTime > initialTime);

        // Test control transfer
        vm.warp(2001); // Advance to timestamp 2001
        vm.prank(ALICE);
        registry.transferControl("alice", BOB);

        IRegistry.UsernameData memory afterControlTransfer = registry.getUsernameData("alice");
        assertTrue(afterControlTransfer.lastUpdateTime > afterRecipientUpdate.lastUpdateTime);
    }

    // =========================================================================
    // Meta-transaction Tests
    // =========================================================================

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

    function test_nonces_ShouldBeZeroInitially() public view {
        assertEq(registry.nonces(ALICE), 0);
        assertEq(registry.nonces(BOB), 0);
        assertEq(registry.nonces(CAROL), 0);
    }

    // =========================================================================
    // Edge Cases and Boundary Tests
    // =========================================================================

    function test_claimUsername_AllValidCharacters_ShouldWork() public {
        // Test all valid characters: lowercase letters, numbers, underscore (not at start/end)
        vm.prank(ALICE);
        registry.claimUsername("abcdefghijklmnopqrst", ALICE); // 20 characters with letters
        
        vm.prank(BOB);
        registry.claimUsername("test_123", BOB);
        
        assertEq(registry.getRecipient("test_123"), BOB);
        assertEq(registry.getRecipient("abcdefghijklmnopqrst"), ALICE);
    }

    function test_claimUsername_BoundaryLengths_ShouldWork() public {
        // Test exactly 3 characters
        vm.prank(ALICE);
        registry.claimUsername("abc", ALICE);
        
        // Test exactly 20 characters
        vm.prank(BOB);
        registry.claimUsername("abcdefghijklmnopqrst", BOB);
        
        assertEq(registry.getRecipient("abc"), ALICE);
        assertEq(registry.getRecipient("abcdefghijklmnopqrst"), BOB);
    }

    function test_claimUsername_CommonUsernamePatterns_ShouldWork() public {
        string[5] memory commonPatterns = ["user123", "alice_bob", "test_user", "dev_account", "main_wallet"];
        
        for (uint i = 0; i < commonPatterns.length; i++) {
            address user = address(uint160(0x100 + i));
            vm.prank(user);
            registry.claimUsername(commonPatterns[i], user);
            assertEq(registry.getRecipient(commonPatterns[i]), user);
        }
    }
}