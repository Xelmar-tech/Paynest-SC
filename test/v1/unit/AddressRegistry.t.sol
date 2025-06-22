// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddressRegistryV1} from "../../../src/v1/AddressRegistryV1.sol";
import {IRegistryV1} from "../../../src/v1/interfaces/IRegistryV1.sol";
import {TestBase} from "../lib/TestBase.sol";

contract AddressRegistryTest is TestBase {
    AddressRegistryV1 public registry;

    // Events to test
    event UsernameClaimed(string indexed username, address indexed claimor);
    event UserAddressUpdated(string indexed username, address indexed newAddress);

    function setUp() public {
        registry = new AddressRegistryV1();
    }

    // =========================================================================
    // Username Claiming Tests
    // =========================================================================

    function test_claimUsername_ValidUsernameAvailableNoExistingUsername_ShouldClaimSuccessfully() public {
        string memory username = "alice";

        vm.expectEmit(true, true, false, true);
        emit UsernameClaimed(username, alice);

        vm.prank(alice);
        registry.claimUsername(username);

        assertEq(registry.getUserAddress(username), alice);
        assertEq(registry.getUsernameByAddress(alice), username);
        assertTrue(registry.hasUsername(alice));
        assertFalse(registry.isUsernameAvailable(username));
    }

    function test_claimUsername_ValidUsernameAvailableNoExistingUsername_ShouldEmitUsernameClaimed() public {
        string memory username = "alice";

        vm.expectEmit(true, true, false, true);
        emit UsernameClaimed(username, alice);

        vm.prank(alice);
        registry.claimUsername(username);
    }

    function test_claimUsername_ValidUsernameAvailableNoExistingUsername_ShouldUpdateBothMappings() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        assertEq(registry.getUserAddress(username), alice);
        assertEq(registry.addressToUsername(alice), username);
    }

    function test_claimUsername_ValidUsernameAvailableNoExistingUsername_ShouldMakeUsernameUnavailable() public {
        string memory username = "alice";

        assertTrue(registry.isUsernameAvailable(username));

        vm.prank(alice);
        registry.claimUsername(username);

        assertFalse(registry.isUsernameAvailable(username));
    }

    function test_claimUsername_UsernameAlreadyClaimed_ShouldRevertWithUsernameAlreadyClaimed() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        vm.expectRevert(AddressRegistryV1.UsernameAlreadyClaimed.selector);
        vm.prank(bob);
        registry.claimUsername(username);
    }

    function test_claimUsername_CallerAlreadyHasUsername_ShouldRevertWithAddressAlreadyHasUsername() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        vm.expectRevert(AddressRegistryV1.AddressAlreadyHasUsername.selector);
        vm.prank(alice);
        registry.claimUsername("alice2");
    }

    function test_claimUsername_EmptyUsername_ShouldRevertWithUsernameEmpty() public {
        vm.expectRevert(AddressRegistryV1.UsernameEmpty.selector);
        vm.prank(alice);
        registry.claimUsername("");
    }

    function test_claimUsername_UsernameTooLong_ShouldRevertWithUsernameTooLong() public {
        string memory longUsername = "abcdefghijklmnopqrstuvwxyz1234567"; // 33 characters

        vm.expectRevert(AddressRegistryV1.UsernameTooLong.selector);
        vm.prank(alice);
        registry.claimUsername(longUsername);
    }

    function test_claimUsername_UsernameStartsWithUnderscore_ShouldRevertWithUsernameCannotStartWithUnderscore()
        public
    {
        vm.expectRevert(AddressRegistryV1.UsernameCannotStartWithUnderscore.selector);
        vm.prank(alice);
        registry.claimUsername("_alice");
    }

    function test_claimUsername_UsernameStartsWithNumber_ShouldRevertWithUsernameCannotStartWithNumber() public {
        vm.expectRevert(AddressRegistryV1.UsernameCannotStartWithNumber.selector);
        vm.prank(alice);
        registry.claimUsername("1alice");
    }

    function test_claimUsername_UsernameContainsInvalidCharacter_ShouldRevertWithInvalidCharacterInUsername() public {
        vm.expectRevert(abi.encodeWithSelector(AddressRegistryV1.InvalidCharacterInUsername.selector, bytes1("@"), 0));
        vm.prank(alice);
        registry.claimUsername("@alice");
    }

    // =========================================================================
    // Address Updates Tests
    // =========================================================================

    function test_updateUserAddress_UserOwnsUsernameValidAvailableAddress_ShouldUpdateUsernameToNewAddress() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        vm.expectEmit(true, true, false, true);
        emit UserAddressUpdated(username, bob);

        vm.prank(alice);
        registry.updateUserAddress(username, bob);

        assertEq(registry.getUserAddress(username), bob);
    }

    function test_updateUserAddress_UserOwnsUsernameValidAvailableAddress_ShouldEmitUserAddressUpdated() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        vm.expectEmit(true, true, false, true);
        emit UserAddressUpdated(username, bob);

        vm.prank(alice);
        registry.updateUserAddress(username, bob);
    }

    function test_updateUserAddress_UserOwnsUsernameValidAvailableAddress_ShouldClearOldAddressMapping() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        vm.prank(alice);
        registry.updateUserAddress(username, bob);

        assertEq(registry.addressToUsername(alice), "");
        assertFalse(registry.hasUsername(alice));
    }

    function test_updateUserAddress_UserOwnsUsernameValidAvailableAddress_ShouldUpdateNewAddressMapping() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        vm.prank(alice);
        registry.updateUserAddress(username, bob);

        assertEq(registry.addressToUsername(bob), username);
        assertTrue(registry.hasUsername(bob));
    }

    function test_updateUserAddress_NewAddressIsZeroAddress_ShouldRevertWithInvalidAddress() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        vm.expectRevert(AddressRegistryV1.InvalidAddress.selector);
        vm.prank(alice);
        registry.updateUserAddress(username, address(0));
    }

    function test_updateUserAddress_NewAddressAlreadyHasUsername_ShouldRevertWithAddressAlreadyHasUsername() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        vm.prank(bob);
        registry.claimUsername("bob");

        vm.expectRevert(AddressRegistryV1.AddressAlreadyHasUsername.selector);
        vm.prank(alice);
        registry.updateUserAddress("alice", bob);
    }

    function test_updateUserAddress_UserDoesNotOwnUsername_ShouldRevertWithNotUsernameOwner() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        vm.expectRevert(AddressRegistryV1.NotUsernameOwner.selector);
        vm.prank(bob);
        registry.updateUserAddress("alice", carol);
    }

    // =========================================================================
    // Username Resolution Tests
    // =========================================================================

    function test_getUserAddress_UsernameExists_ShouldReturnCorrectAddress() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        assertEq(registry.getUserAddress(username), alice);
    }

    function test_getUserAddress_UsernameDoesNotExist_ShouldReturnZeroAddress() public {
        assertEq(registry.getUserAddress("nonexistent"), address(0));
    }

    // =========================================================================
    // View Functions Tests
    // =========================================================================

    function test_isUsernameAvailable_AvailableUsername_ShouldReturnTrue() public {
        assertTrue(registry.isUsernameAvailable("available"));
    }

    function test_isUsernameAvailable_ClaimedUsername_ShouldReturnFalse() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        assertFalse(registry.isUsernameAvailable("alice"));
    }

    function test_getUsernameByAddress_AddressWithUsername_ShouldReturnCorrectUsername() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        assertEq(registry.getUsernameByAddress(alice), username);
    }

    function test_getUsernameByAddress_AddressWithoutUsername_ShouldReturnEmptyString() public {
        assertEq(registry.getUsernameByAddress(alice), "");
    }

    function test_hasUsername_AddressWithUsername_ShouldReturnTrue() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        assertTrue(registry.hasUsername(alice));
    }

    function test_hasUsername_AddressWithoutUsername_ShouldReturnFalse() public {
        assertFalse(registry.hasUsername(alice));
    }

    // =========================================================================
    // Username Validation Tests
    // =========================================================================

    function test_claimUsername_ValidFormats_ShouldAcceptValidUsernames() public {
        string[5] memory validUsernames = ["alice", "Bob", "user123", "test_user", "a"];

        address[5] memory users = [alice, bob, carol, david, randomAddress];

        for (uint256 i = 0; i < validUsernames.length; i++) {
            vm.prank(users[i]);
            registry.claimUsername(validUsernames[i]);
            assertEq(registry.getUserAddress(validUsernames[i]), users[i]);
        }
    }

    function test_claimUsername_InvalidLength_ShouldRejectInvalidLengths() public {
        vm.expectRevert(AddressRegistryV1.UsernameEmpty.selector);
        vm.prank(alice);
        registry.claimUsername("");

        string memory tooLong = "thisusernameiswaytoolongandexceedsthirtytwocharacters";
        vm.expectRevert(AddressRegistryV1.UsernameTooLong.selector);
        vm.prank(bob);
        registry.claimUsername(tooLong);
    }

    function test_claimUsername_InvalidStartingCharacter_ShouldRejectInvalidStarts() public {
        vm.expectRevert(AddressRegistryV1.UsernameCannotStartWithUnderscore.selector);
        vm.prank(alice);
        registry.claimUsername("_user");

        vm.expectRevert(AddressRegistryV1.UsernameCannotStartWithNumber.selector);
        vm.prank(bob);
        registry.claimUsername("1user");

        vm.expectRevert(abi.encodeWithSelector(AddressRegistryV1.InvalidCharacterInUsername.selector, bytes1("-"), 0));
        vm.prank(carol);
        registry.claimUsername("-user");
    }

    // =========================================================================
    // Bidirectional Mapping Consistency Tests
    // =========================================================================

    function test_claimUsername_BidirectionalConsistency_ShouldMaintainMappingConsistency() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        // Check bidirectional consistency
        assertEq(registry.getUserAddress(username), alice);
        assertEq(registry.addressToUsername(alice), username);
        assertEq(registry.getUserAddress(username), alice);
        assertEq(registry.getUsernameByAddress(alice), username);
    }

    function test_updateUserAddress_BidirectionalConsistency_ShouldMaintainMappingConsistency() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        vm.prank(alice);
        registry.updateUserAddress(username, bob);

        // Check bidirectional consistency after update
        assertEq(registry.getUserAddress(username), bob);
        assertEq(registry.addressToUsername(bob), username);
        assertEq(registry.getUserAddress(username), bob);
        assertEq(registry.getUsernameByAddress(bob), username);

        // Check old mapping is cleared
        assertEq(registry.addressToUsername(alice), "");
        assertFalse(registry.hasUsername(alice));
    }

    function test_updateUserAddress_BidirectionalConsistency_ShouldProperlyClearOldMappings() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        vm.prank(alice);
        registry.updateUserAddress(username, bob);

        // Old address should have no username
        assertEq(registry.addressToUsername(alice), "");
        assertFalse(registry.hasUsername(alice));
        assertEq(registry.getUsernameByAddress(alice), "");
    }

    // =========================================================================
    // Multi-User Scenarios Tests
    // =========================================================================

    function test_multiUser_DifferentUsernames_ShouldAllowMultipleDifferentClaims() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        vm.prank(bob);
        registry.claimUsername("bob");

        vm.prank(carol);
        registry.claimUsername("carol");

        assertEq(registry.getUserAddress("alice"), alice);
        assertEq(registry.getUserAddress("bob"), bob);
        assertEq(registry.getUserAddress("carol"), carol);
    }

    function test_multiUser_DifferentUsernames_ShouldMaintainSeparateMappings() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        vm.prank(bob);
        registry.claimUsername("bob");

        assertEq(registry.getUsernameByAddress(alice), "alice");
        assertEq(registry.getUsernameByAddress(bob), "bob");
        assertTrue(registry.hasUsername(alice));
        assertTrue(registry.hasUsername(bob));
    }

    function test_multiUser_SameUsername_ShouldOnlyAllowFirstUserToClaim() public {
        string memory username = "popular";

        vm.prank(alice);
        registry.claimUsername(username);

        vm.expectRevert(AddressRegistryV1.UsernameAlreadyClaimed.selector);
        vm.prank(bob);
        registry.claimUsername(username);

        assertEq(registry.getUserAddress(username), alice);
    }

    function test_multiUser_SameUsername_ShouldRejectSubsequentClaims() public {
        string memory username = "test";

        vm.prank(alice);
        registry.claimUsername(username);

        vm.expectRevert(AddressRegistryV1.UsernameAlreadyClaimed.selector);
        vm.prank(bob);
        registry.claimUsername(username);

        vm.expectRevert(AddressRegistryV1.UsernameAlreadyClaimed.selector);
        vm.prank(carol);
        registry.claimUsername(username);
    }

    // =========================================================================
    // Security and Edge Cases Tests
    // =========================================================================

    function test_security_UsernameSquatting_ShouldFollowFirstComeFirstServed() public {
        string memory desiredUsername = "admin";

        // First user claims
        vm.prank(alice);
        registry.claimUsername(desiredUsername);

        // Others cannot claim same username
        vm.expectRevert(AddressRegistryV1.UsernameAlreadyClaimed.selector);
        vm.prank(bob);
        registry.claimUsername(desiredUsername);

        assertEq(registry.getUserAddress(desiredUsername), alice);
    }

    function test_security_MaliciousAddressUpdates_ShouldOnlyAllowOwnerToUpdate() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        // Non-owner cannot update
        vm.expectRevert(AddressRegistryV1.NotUsernameOwner.selector);
        vm.prank(bob);
        registry.updateUserAddress("alice", bob);

        // Owner still controls the username
        assertEq(registry.getUserAddress("alice"), alice);
    }

    function test_security_StateConsistencyAttacks_ShouldMaintainAtomicUpdates() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        // Valid update should succeed atomically
        vm.prank(alice);
        registry.updateUserAddress("alice", bob);

        // State should be consistent
        assertEq(registry.getUserAddress("alice"), bob);
        assertEq(registry.getUsernameByAddress(bob), "alice");
        assertEq(registry.addressToUsername(alice), "");
        assertFalse(registry.hasUsername(alice));
    }

    function test_security_StateConsistencyAttacks_ShouldPreventPartialStateChanges() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        vm.prank(bob);
        registry.claimUsername("bob");

        // This should fail and not change any state
        vm.expectRevert(AddressRegistryV1.AddressAlreadyHasUsername.selector);
        vm.prank(alice);
        registry.updateUserAddress("alice", bob);

        // State should remain unchanged
        assertEq(registry.getUserAddress("alice"), alice);
        assertEq(registry.getUserAddress("bob"), bob);
        assertEq(registry.getUsernameByAddress(alice), "alice");
        assertEq(registry.getUsernameByAddress(bob), "bob");
    }

    // =========================================================================
    // Contract Invariants Tests
    // =========================================================================

    function test_invariant_BidirectionalMappingSync_ShouldMaintainPerfectSync() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        // Check initial sync
        assertEq(registry.getUserAddress("alice"), alice);
        assertEq(registry.addressToUsername(alice), "alice");

        // Update and check sync maintained
        vm.prank(alice);
        registry.updateUserAddress("alice", bob);

        assertEq(registry.getUserAddress("alice"), bob);
        assertEq(registry.addressToUsername(bob), "alice");
        assertEq(registry.addressToUsername(alice), "");
    }

    function test_invariant_OneToOneMappings_ShouldEnsureUniquenessBounds() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        vm.prank(bob);
        registry.claimUsername("bob");

        // Each address has at most one username
        assertTrue(registry.hasUsername(alice));
        assertTrue(registry.hasUsername(bob));
        assertEq(registry.getUsernameByAddress(alice), "alice");
        assertEq(registry.getUsernameByAddress(bob), "bob");

        // Each username has exactly one address
        assertEq(registry.getUserAddress("alice"), alice);
        assertEq(registry.getUserAddress("bob"), bob);
    }

    function test_invariant_NoOrphanedMappings_ShouldNeverHaveOrphanedMappings() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        vm.prank(alice);
        registry.updateUserAddress("alice", bob);

        // No orphaned mappings - if username maps to address, address maps back to username
        address usernameOwner = registry.getUserAddress("alice");
        string memory ownerUsername = registry.addressToUsername(usernameOwner);
        assertEq(ownerUsername, "alice");

        // Old address should not be orphaned
        assertEq(registry.addressToUsername(alice), "");
    }

    function test_invariant_NoEmptyUsernames_ShouldNeverHaveEmptyUsernamesMapped() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        // Active username should never be empty
        string memory username = registry.addressToUsername(alice);
        assertTrue(bytes(username).length > 0);

        vm.prank(alice);
        registry.updateUserAddress("alice", bob);

        // After update, new address should have non-empty username
        string memory newUsername = registry.addressToUsername(bob);
        assertTrue(bytes(newUsername).length > 0);

        // Old address should have empty username
        string memory oldUsername = registry.addressToUsername(alice);
        assertEq(bytes(oldUsername).length, 0);
    }

    function test_invariant_NoZeroAddressMappings_ShouldNeverMapUsernamesToZeroAddress() public {
        vm.prank(alice);
        registry.claimUsername("alice");

        // Username should never map to zero address after claiming
        assertTrue(registry.getUserAddress("alice") != address(0));

        vm.prank(alice);
        registry.updateUserAddress("alice", bob);

        // After update, should still not map to zero address
        assertTrue(registry.getUserAddress("alice") != address(0));
    }

    // =========================================================================
    // Address History Tests
    // =========================================================================

    function test_claimUsername_NewUsername_ShouldInitializeAddressHistory() public {
        string memory username = "alice";

        vm.prank(alice);
        registry.claimUsername(username);

        IRegistryV1.AddressHistory memory history = registry.getAddressHistory(username);
        assertEq(history.currentAddress, alice);
        assertEq(history.previousAddress, address(0));
        assertTrue(history.lastChangeTime > 0);
    }

    function test_updateUserAddress_ValidUpdate_ShouldTrackAddressHistory() public {
        string memory username = "alice";

        // Alice claims username
        vm.prank(alice);
        registry.claimUsername(username);

        // Fast forward time
        vm.warp(block.timestamp + 1 days);

        // Alice updates to bob's address
        vm.prank(alice);
        registry.updateUserAddress(username, bob);

        // Check address history
        IRegistryV1.AddressHistory memory history = registry.getAddressHistory(username);
        assertEq(history.currentAddress, bob);
        assertEq(history.previousAddress, alice);
        assertEq(history.lastChangeTime, block.timestamp);
    }

    function test_updateUserAddress_MultipleUpdates_ShouldTrackLatestChange() public {
        string memory username = "alice";

        // Alice claims username
        vm.prank(alice);
        registry.claimUsername(username);

        // First update: alice -> bob
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        registry.updateUserAddress(username, bob);

        // Second update: bob -> carol
        vm.warp(block.timestamp + 1 days);
        vm.prank(bob);
        registry.updateUserAddress(username, carol);

        // History should track bob -> carol (most recent change)
        IRegistryV1.AddressHistory memory history = registry.getAddressHistory(username);
        assertEq(history.currentAddress, carol);
        assertEq(history.previousAddress, bob); // Not alice
        assertEq(history.lastChangeTime, block.timestamp);
    }

    function test_updateUserAddress_UnauthorizedCaller_ShouldRevertWithUnauthorizedAddressUpdate() public {
        string memory username = "alice";

        // Alice claims username
        vm.prank(alice);
        registry.claimUsername(username);

        // Bob tries to update Alice's username
        vm.expectRevert(AddressRegistryV1.NotUsernameOwner.selector);
        vm.prank(bob);
        registry.updateUserAddress(username, bob);
    }

    function test_getAddressHistory_NonExistentUsername_ShouldReturnZeroValues() public {
        IRegistryV1.AddressHistory memory history = registry.getAddressHistory("nonexistent");

        assertEq(history.currentAddress, address(0));
        assertEq(history.previousAddress, address(0));
        assertEq(history.lastChangeTime, 0);
    }

    function test_getUserAddress_AfterUpdate_ShouldReturnCurrentAddress() public {
        string memory username = "alice";

        // Alice claims username
        vm.prank(alice);
        registry.claimUsername(username);

        // Alice updates to bob's address
        vm.prank(alice);
        registry.updateUserAddress(username, bob);

        // getUserAddress should return current address
        assertEq(registry.getUserAddress(username), bob);
    }

    function test_isUsernameAvailable_UpdatedUsername_ShouldReturnFalse() public {
        string memory username = "alice";

        // Alice claims username
        vm.prank(alice);
        registry.claimUsername(username);

        // Alice updates to bob's address
        vm.prank(alice);
        registry.updateUserAddress(username, bob);

        // Username should still be unavailable
        assertFalse(registry.isUsernameAvailable(username));
    }
}
