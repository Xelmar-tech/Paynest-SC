// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddressRegistryV1} from "../../../src/v1/AddressRegistryV1.sol";
import {IRegistryV1} from "../../../src/v1/interfaces/IRegistryV1.sol";
import {TestBase} from "../lib/TestBase.sol";

contract AddressRegistryFuzzTest is TestBase {
    AddressRegistryV1 public registry;

    // Events to test
    event UsernameClaimed(string indexed username, address indexed claimor);
    event UserAddressUpdated(string indexed username, address indexed newAddress);

    function setUp() public {
        registry = new AddressRegistryV1();
    }

    // =========================================================================
    // Username Format Fuzz Tests
    // =========================================================================

    function testFuzz_claimUsername_ValidFormats(string calldata username) public {
        // Only test usernames that should be valid according to our rules
        vm.assume(bytes(username).length > 0 && bytes(username).length <= 32);

        // Check first character is a letter
        bytes1 firstChar = bytes(username)[0];
        vm.assume((firstChar >= "a" && firstChar <= "z") || (firstChar >= "A" && firstChar <= "Z"));

        // Check all characters are valid
        bool allValid = true;
        for (uint256 i = 0; i < bytes(username).length; i++) {
            bytes1 char = bytes(username)[i];
            if (
                !(
                    (char >= "a" && char <= "z") || (char >= "A" && char <= "Z") || (char >= "0" && char <= "9")
                        || char == "_"
                )
            ) {
                allValid = false;
                break;
            }
        }
        vm.assume(allValid);

        // Should successfully claim valid username
        vm.prank(alice);
        registry.claimUsername(username);

        // Verify state
        assertEq(registry.getUserAddress(username), alice);
        assertEq(registry.getUsernameByAddress(alice), username);
        assertTrue(registry.hasUsername(alice));
        assertFalse(registry.isUsernameAvailable(username));
    }

    function testFuzz_claimUsername_InvalidLength(string calldata username) public {
        // Test usernames that are too long
        vm.assume(bytes(username).length > 32 || bytes(username).length == 0);

        vm.expectRevert();
        vm.prank(alice);
        registry.claimUsername(username);
    }

    function testFuzz_claimUsername_InvalidFirstCharacter(uint8 firstCharCode, string calldata rest) public {
        // Generate invalid first characters (not letters)
        vm.assume(firstCharCode != 0); // Avoid null character
        vm.assume(
            // A-Z
            !((firstCharCode >= 65 && firstCharCode <= 90) || (firstCharCode >= 97 && firstCharCode <= 122))
        ); // a-z

        // Create username with invalid first character
        bytes memory usernameBytes = abi.encodePacked(bytes1(firstCharCode), bytes(rest));
        vm.assume(usernameBytes.length <= 32 && usernameBytes.length > 0);

        string memory username = string(usernameBytes);

        vm.expectRevert();
        vm.prank(alice);
        registry.claimUsername(username);
    }

    function testFuzz_claimUsername_InvalidCharacters(string calldata username) public {
        vm.assume(bytes(username).length > 0 && bytes(username).length <= 32);

        // Ensure first character is valid (letter)
        bytes memory usernameBytes = bytes(username);
        bytes1 firstChar = usernameBytes[0];
        vm.assume((firstChar >= "a" && firstChar <= "z") || (firstChar >= "A" && firstChar <= "Z"));

        // Check if username contains any invalid characters
        bool hasInvalidChar = false;
        for (uint256 i = 0; i < usernameBytes.length; i++) {
            bytes1 char = usernameBytes[i];
            if (
                !(
                    (char >= "a" && char <= "z") || (char >= "A" && char <= "Z") || (char >= "0" && char <= "9")
                        || char == "_"
                )
            ) {
                hasInvalidChar = true;
                break;
            }
        }

        // Only test usernames with invalid characters
        vm.assume(hasInvalidChar);

        vm.expectRevert();
        vm.prank(alice);
        registry.claimUsername(username);
    }

    // =========================================================================
    // Address Update Fuzz Tests
    // =========================================================================

    function testFuzz_updateUserAddress_ValidAddresses(address newAddress) public {
        // Ensure new address is valid and different from current
        vm.assume(newAddress != address(0));
        vm.assume(newAddress != alice);
        vm.assume(newAddress.code.length == 0); // EOA only for simplicity

        string memory username = "alice";

        // Claim username first
        vm.prank(alice);
        registry.claimUsername(username);

        // Update to new address
        vm.prank(alice);
        registry.updateUserAddress(username, newAddress);

        // Verify state
        assertEq(registry.getUserAddress(username), newAddress);
        assertEq(registry.getUsernameByAddress(newAddress), username);
        assertTrue(registry.hasUsername(newAddress));
        assertFalse(registry.hasUsername(alice));
        assertEq(registry.getUsernameByAddress(alice), "");
    }

    function testFuzz_updateUserAddress_UnauthorizedCallers(address caller, address newAddress) public {
        vm.assume(caller != alice);
        vm.assume(newAddress != address(0));
        vm.assume(caller != address(0));

        string memory username = "alice";

        // Alice claims username
        vm.prank(alice);
        registry.claimUsername(username);

        // Unauthorized caller tries to update
        vm.expectRevert(AddressRegistryV1.NotUsernameOwner.selector);
        vm.prank(caller);
        registry.updateUserAddress(username, newAddress);

        // State should remain unchanged
        assertEq(registry.getUserAddress(username), alice);
        assertEq(registry.getUsernameByAddress(alice), username);
    }

    function testFuzz_updateUserAddress_ZeroAddress(address caller) public {
        vm.assume(caller != address(0));

        string memory username = "testuser";

        // Caller claims username
        vm.prank(caller);
        registry.claimUsername(username);

        // Try to update to zero address
        vm.expectRevert(AddressRegistryV1.InvalidAddress.selector);
        vm.prank(caller);
        registry.updateUserAddress(username, address(0));

        // State should remain unchanged
        assertEq(registry.getUserAddress(username), caller);
    }

    // =========================================================================
    // Multi-User Fuzz Tests
    // =========================================================================

    function testFuzz_multiUser_ClaimDifferentUsernames(address user1, address user2, uint256 seed1, uint256 seed2)
        public
    {
        vm.assume(user1 != user2);
        vm.assume(user1 != address(0) && user2 != address(0));

        // Generate simple valid usernames from seeds
        string memory username1 = _generateValidUsername(seed1, "user1");
        string memory username2 = _generateValidUsername(seed2, "user2");

        // Both users claim their usernames
        vm.prank(user1);
        registry.claimUsername(username1);

        vm.prank(user2);
        registry.claimUsername(username2);

        // Verify both claims succeeded
        assertEq(registry.getUserAddress(username1), user1);
        assertEq(registry.getUserAddress(username2), user2);
        assertEq(registry.getUsernameByAddress(user1), username1);
        assertEq(registry.getUsernameByAddress(user2), username2);
        assertTrue(registry.hasUsername(user1));
        assertTrue(registry.hasUsername(user2));
    }

    function testFuzz_multiUser_SameUsernameConflict(address user1, address user2, string calldata username) public {
        vm.assume(user1 != user2);
        vm.assume(user1 != address(0) && user2 != address(0));
        _assumeValidUsername(username);

        // First user claims username
        vm.prank(user1);
        registry.claimUsername(username);

        // Second user tries to claim same username
        vm.expectRevert(AddressRegistryV1.UsernameAlreadyClaimed.selector);
        vm.prank(user2);
        registry.claimUsername(username);

        // Only first user should have the username
        assertEq(registry.getUserAddress(username), user1);
        assertEq(registry.getUsernameByAddress(user1), username);
        assertEq(registry.getUsernameByAddress(user2), "");
        assertTrue(registry.hasUsername(user1));
        assertFalse(registry.hasUsername(user2));
    }

    function testFuzz_multiUser_DoubleClaimSameUser(address user, uint256 seed1, uint256 seed2) public {
        vm.assume(user != address(0));

        // Generate different valid usernames from seeds
        string memory username1 = _generateValidUsername(seed1, "first");
        string memory username2 = _generateValidUsername(seed2, "second");

        // User claims first username
        vm.prank(user);
        registry.claimUsername(username1);

        // User tries to claim second username (should fail)
        vm.expectRevert(AddressRegistryV1.AddressAlreadyHasUsername.selector);
        vm.prank(user);
        registry.claimUsername(username2);

        // Only first username should be claimed
        assertEq(registry.getUserAddress(username1), user);
        assertEq(registry.getUserAddress(username2), address(0));
        assertEq(registry.getUsernameByAddress(user), username1);
    }

    // =========================================================================
    // State Consistency Fuzz Tests
    // =========================================================================

    function testFuzz_stateConsistency_ClaimAndUpdate(address originalUser, address newUser, string calldata username)
        public
    {
        vm.assume(originalUser != newUser);
        vm.assume(originalUser != address(0) && newUser != address(0));
        _assumeValidUsername(username);

        // Original user claims username
        vm.prank(originalUser);
        registry.claimUsername(username);

        // Original user updates to new address
        vm.prank(originalUser);
        registry.updateUserAddress(username, newUser);

        // Verify bidirectional consistency
        assertEq(registry.getUserAddress(username), newUser);
        assertEq(registry.getUsernameByAddress(newUser), username);
        assertEq(registry.getUsernameByAddress(originalUser), "");
        assertTrue(registry.hasUsername(newUser));
        assertFalse(registry.hasUsername(originalUser));
        assertFalse(registry.isUsernameAvailable(username));
    }

    function testFuzz_stateConsistency_UpdateToAddressWithUsername(
        address user1,
        address user2,
        uint256 seed1,
        uint256 seed2
    ) public {
        vm.assume(user1 != user2);
        vm.assume(user1 != address(0) && user2 != address(0));

        // Generate different valid usernames from seeds
        string memory username1 = _generateValidUsername(seed1, "alpha");
        string memory username2 = _generateValidUsername(seed2, "beta");

        // Both users claim different usernames
        vm.prank(user1);
        registry.claimUsername(username1);

        vm.prank(user2);
        registry.claimUsername(username2);

        // User1 tries to update to user2's address (should fail)
        vm.expectRevert(AddressRegistryV1.AddressAlreadyHasUsername.selector);
        vm.prank(user1);
        registry.updateUserAddress(username1, user2);

        // State should remain unchanged
        assertEq(registry.getUserAddress(username1), user1);
        assertEq(registry.getUserAddress(username2), user2);
        assertEq(registry.getUsernameByAddress(user1), username1);
        assertEq(registry.getUsernameByAddress(user2), username2);
    }

    // =========================================================================
    // Username Resolution Fuzz Tests
    // =========================================================================

    function testFuzz_getUserAddress_NonExistentUsernames(string calldata username) public {
        _assumeValidUsername(username);

        // Should return zero address for non-existent usernames
        assertEq(registry.getUserAddress(username), address(0));
        assertTrue(registry.isUsernameAvailable(username));
    }

    function testFuzz_getUsernameByAddress_UnregisteredAddresses(address user) public {
        vm.assume(user != address(0));

        // Should return empty string for unregistered addresses
        assertEq(registry.getUsernameByAddress(user), "");
        assertFalse(registry.hasUsername(user));
    }

    // =========================================================================
    // Gas Optimization Fuzz Tests
    // =========================================================================

    function testFuzz_gasUsage_ClaimUsername(string calldata username) public {
        _assumeValidUsername(username);

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        registry.claimUsername(username);
        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable (adjust threshold as needed)
        assertLt(gasUsed, 100000, "Username claiming uses too much gas");
    }

    function testFuzz_gasUsage_UpdateAddress(address newAddress) public {
        vm.assume(newAddress != address(0));
        vm.assume(newAddress != alice);

        string memory username = "alice";

        // Claim username first
        vm.prank(alice);
        registry.claimUsername(username);

        uint256 gasBefore = gasleft();
        vm.prank(alice);
        registry.updateUserAddress(username, newAddress);
        uint256 gasUsed = gasBefore - gasleft();

        // Gas usage should be reasonable
        assertLt(gasUsed, 100000, "Address update uses too much gas");
    }

    // =========================================================================
    // Edge Case Fuzz Tests
    // =========================================================================

    function testFuzz_edgeCase_MaxLengthUsernames(uint256 seed) public {
        // Test usernames at maximum length (32 characters)
        string memory longUsername = _generateLongValidUsername(seed);

        vm.prank(alice);
        registry.claimUsername(longUsername);

        assertEq(registry.getUserAddress(longUsername), alice);
        assertEq(registry.getUsernameByAddress(alice), longUsername);
        assertTrue(bytes(longUsername).length <= 32);
    }

    function testFuzz_edgeCase_MinLengthUsernames(uint256 seed) public {
        // Test single character usernames
        bytes1 char = bytes1(uint8(97 + (seed % 26))); // a-z
        string memory singleChar = string(abi.encodePacked(char));

        vm.prank(alice);
        registry.claimUsername(singleChar);

        assertEq(registry.getUserAddress(singleChar), alice);
        assertEq(registry.getUsernameByAddress(alice), singleChar);
        assertEq(bytes(singleChar).length, 1);
    }

    function testFuzz_edgeCase_SequentialOperations(address user, uint256 seed) public {
        vm.assume(user != address(0));
        vm.assume(user != alice);

        string memory username = _generateValidUsername(seed, "test");

        // Claim, update, and verify multiple times
        vm.prank(alice);
        registry.claimUsername(username);

        vm.prank(alice);
        registry.updateUserAddress(username, user);

        vm.prank(user);
        registry.updateUserAddress(username, alice);

        // Final state should be back to alice
        assertEq(registry.getUserAddress(username), alice);
        assertEq(registry.getUsernameByAddress(alice), username);
        assertFalse(registry.hasUsername(user));
    }

    function testFuzz_edgeCase_MixedCaseUsernames(uint256 seed) public {
        // Test usernames with mixed case
        string memory mixedCase = _generateMixedCaseUsername(seed);

        vm.prank(alice);
        registry.claimUsername(mixedCase);

        // Should preserve exact case
        assertEq(registry.getUsernameByAddress(alice), mixedCase);
        assertEq(registry.getUserAddress(mixedCase), alice);
    }

    // =========================================================================
    // Property-Based Invariant Fuzz Tests
    // =========================================================================

    function testFuzz_invariant_BidirectionalMapping(address user, string calldata username) public {
        vm.assume(user != address(0));
        _assumeValidUsername(username);

        // Claim username
        vm.prank(user);
        registry.claimUsername(username);

        // Invariant: If username maps to address, address must map back to username
        address resolvedAddress = registry.getUserAddress(username);
        string memory resolvedUsername = registry.getUsernameByAddress(resolvedAddress);

        assertEq(resolvedAddress, user);
        assertTrue(_stringsEqual(resolvedUsername, username));
    }

    function testFuzz_invariant_OneToOneMapping(address user1, address user2, uint256 seed1, uint256 seed2) public {
        vm.assume(user1 != user2);
        vm.assume(user1 != address(0) && user2 != address(0));

        // Generate different valid usernames from seeds
        string memory username1 = _generateValidUsername(seed1, "gamma");
        string memory username2 = _generateValidUsername(seed2, "delta");

        // Both users claim different usernames
        vm.prank(user1);
        registry.claimUsername(username1);

        vm.prank(user2);
        registry.claimUsername(username2);

        // Invariant: Different addresses should have different usernames
        string memory user1Username = registry.getUsernameByAddress(user1);
        string memory user2Username = registry.getUsernameByAddress(user2);

        assertFalse(_stringsEqual(user1Username, user2Username));

        // Invariant: Different usernames should map to different addresses
        address username1Address = registry.getUserAddress(username1);
        address username2Address = registry.getUserAddress(username2);

        assertTrue(username1Address != username2Address);
    }

    function testFuzz_invariant_NoZeroAddressMappings(string calldata username) public {
        _assumeValidUsername(username);

        // Username should never map to zero address after any operation
        assertEq(registry.getUserAddress(username), address(0)); // Initially zero

        vm.prank(alice);
        registry.claimUsername(username);

        // After claiming, should never be zero
        assertTrue(registry.getUserAddress(username) != address(0));
    }

    // =========================================================================
    // Helper Functions
    // =========================================================================

    function _assumeValidUsername(string calldata username) internal pure {
        vm.assume(bytes(username).length > 0 && bytes(username).length <= 32);

        // Check first character is a letter
        bytes1 firstChar = bytes(username)[0];
        vm.assume((firstChar >= "a" && firstChar <= "z") || (firstChar >= "A" && firstChar <= "Z"));

        // Check all characters are valid
        for (uint256 i = 0; i < bytes(username).length; i++) {
            bytes1 char = bytes(username)[i];
            vm.assume(
                (char >= "a" && char <= "z") || (char >= "A" && char <= "Z") || (char >= "0" && char <= "9")
                    || char == "_"
            );
        }
    }

    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _generateValidUsername(uint256 seed, string memory prefix) internal pure returns (string memory) {
        // Generate a simple valid username using the seed and prefix
        // This ensures we always get valid usernames without vm.assume rejections
        bytes memory prefixBytes = bytes(prefix);

        // Ensure prefix starts with a letter (already does in our cases)
        require(prefixBytes.length > 0, "Empty prefix");

        // Add some randomness from seed while keeping it valid
        uint256 suffixLength = (seed % 8) + 1; // 1-8 characters
        bytes memory username = new bytes(prefixBytes.length + suffixLength);

        // Copy prefix
        for (uint256 i = 0; i < prefixBytes.length; i++) {
            username[i] = prefixBytes[i];
        }

        // Add valid characters based on seed
        for (uint256 i = 0; i < suffixLength; i++) {
            uint256 charType = (seed >> (i * 8)) % 3;
            if (charType == 0) {
                // Add lowercase letter
                username[prefixBytes.length + i] = bytes1(uint8(97 + ((seed >> (i * 8)) % 26))); // a-z
            } else if (charType == 1) {
                // Add uppercase letter
                username[prefixBytes.length + i] = bytes1(uint8(65 + ((seed >> (i * 8)) % 26))); // A-Z
            } else {
                // Add digit
                username[prefixBytes.length + i] = bytes1(uint8(48 + ((seed >> (i * 8)) % 10))); // 0-9
            }
        }

        return string(username);
    }

    function _generateLongValidUsername(uint256 seed) internal pure returns (string memory) {
        // Generate exactly 32 character username
        bytes memory username = new bytes(32);

        // First character must be a letter
        username[0] = bytes1(uint8(97 + (seed % 26))); // a-z

        // Fill rest with valid characters
        for (uint256 i = 1; i < 32; i++) {
            uint256 charType = (seed >> (i * 4)) % 3;
            if (charType == 0) {
                username[i] = bytes1(uint8(97 + ((seed >> (i * 4)) % 26))); // a-z
            } else if (charType == 1) {
                username[i] = bytes1(uint8(65 + ((seed >> (i * 4)) % 26))); // A-Z
            } else {
                username[i] = bytes1(uint8(48 + ((seed >> (i * 4)) % 10))); // 0-9
            }
        }

        return string(username);
    }

    function _generateMixedCaseUsername(uint256 seed) internal pure returns (string memory) {
        // Generate username with intentionally mixed case
        uint256 length = (seed % 10) + 5; // 5-14 characters
        bytes memory username = new bytes(length);

        // First character must be a letter
        bool upperFirst = (seed % 2) == 0;
        username[0] = upperFirst
            ? bytes1(uint8(65 + (seed % 26))) // A-Z
            : bytes1(uint8(97 + (seed % 26))); // a-z

        // Alternate case for following characters
        for (uint256 i = 1; i < length; i++) {
            uint256 charType = (seed >> (i * 4)) % 4;
            if (charType == 0) {
                username[i] = bytes1(uint8(97 + ((seed >> (i * 4)) % 26))); // a-z
            } else if (charType == 1) {
                username[i] = bytes1(uint8(65 + ((seed >> (i * 4)) % 26))); // A-Z
            } else if (charType == 2) {
                username[i] = bytes1(uint8(48 + ((seed >> (i * 4)) % 10))); // 0-9
            } else {
                username[i] = "_";
            }
        }

        return string(username);
    }
}
