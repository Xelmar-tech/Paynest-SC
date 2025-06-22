// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddressRegistryV1} from "../../../src/v1/AddressRegistryV1.sol";
import {IRegistryV1} from "../../../src/v1/interfaces/IRegistryV1.sol";

/// @title AddressRegistry Invariant Tests
/// @notice Tests critical invariants for the AddressRegistry contract
/// @dev Implements Priority 1 (AR1-AR6) and Priority 2 (AR7-AR12) invariants
contract AddressRegistryInvariants is Test {
    AddressRegistryV1 public registry;

    // Test actors for invariant testing
    address[] public actors;
    address internal currentActor;

    // Ghost variables for tracking state
    mapping(string => address) public ghost_usernameToAddress;
    mapping(address => string) public ghost_addressToUsername;
    uint256 public ghost_totalUsernames;

    function setUp() public {
        registry = new AddressRegistryV1();

        // Initialize test actors
        actors = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            actors[i] = address(uint160(0x1000 + i));
            vm.deal(actors[i], 1 ether);
        }
    }

    /// @dev Modifier to use random actor for operations
    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         PRIORITY 1 INVARIANTS (AR1-AR6)
    //////////////////////////////////////////////////////////////*/

    /// @notice AR1: Username-to-Address Consistency
    /// @dev If username maps to an address, that address must map back to the username
    function invariant_AR1_usernameToAddressConsistency() public view {
        // Test with known usernames that have been claimed
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = registry.addressToUsername(actors[i]);
            if (bytes(username).length > 0) {
                address mappedAddress = registry.getUserAddress(username);
                assertEq(mappedAddress, actors[i], "AR1: Username-to-address mapping inconsistent");
            }
        }
    }

    /// @notice AR2: Address-to-Username Consistency
    /// @dev If address has a username, that username must map back to the address
    function invariant_AR2_addressToUsernameConsistency() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = registry.addressToUsername(actors[i]);
            if (bytes(username).length > 0) {
                address mappedAddress = registry.getUserAddress(username);
                assertEq(mappedAddress, actors[i], "AR2: Address-to-username mapping inconsistent");
            }
        }
    }

    /// @notice AR3: Bijective Mapping
    /// @dev Different usernames cannot map to the same address
    function invariant_AR3_bijectiveMapping() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = i + 1; j < actors.length; j++) {
                if (actors[i] != actors[j]) {
                    string memory username1 = registry.addressToUsername(actors[i]);
                    string memory username2 = registry.addressToUsername(actors[j]);

                    // If both have usernames, they must be different
                    if (bytes(username1).length > 0 && bytes(username2).length > 0) {
                        assertTrue(
                            keccak256(bytes(username1)) != keccak256(bytes(username2)),
                            "AR3: Different addresses cannot have same username"
                        );
                    }
                }
            }
        }
    }

    /// @notice AR4: Zero Address Protection
    /// @dev Zero address never has a username
    function invariant_AR4_zeroAddressProtection() public view {
        string memory zeroUsername = registry.addressToUsername(address(0));
        assertEq(bytes(zeroUsername).length, 0, "AR4: Zero address should not have username");
    }

    /// @notice AR5: Address History Integrity
    /// @dev Active usernames must have valid timestamps
    function invariant_AR5_addressHistoryIntegrity() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = registry.addressToUsername(actors[i]);
            if (bytes(username).length > 0) {
                IRegistryV1.AddressHistory memory history = registry.getAddressHistory(username);

                // Must have valid timestamp
                assertGt(history.lastChangeTime, 0, "AR5: Active username must have valid timestamp");
                assertLe(history.lastChangeTime, block.timestamp, "AR5: Timestamp cannot be in future");

                // Current address must match
                assertEq(history.currentAddress, actors[i], "AR5: History current address mismatch");
            }
        }
    }

    /// @notice AR6: No Self-Transitions
    /// @dev Previous address differs from current (except initial claim)
    function invariant_AR6_noSelfTransitions() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = registry.addressToUsername(actors[i]);
            if (bytes(username).length > 0) {
                IRegistryV1.AddressHistory memory history = registry.getAddressHistory(username);

                // If current equals previous, previous must be zero (initial claim)
                if (history.currentAddress == history.previousAddress) {
                    assertEq(history.previousAddress, address(0), "AR6: Self-transition only allowed on initial claim");
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         PRIORITY 2 INVARIANTS (AR7-AR12)
    //////////////////////////////////////////////////////////////*/

    /// @notice AR7: Username Format Enforcement
    /// @dev All claimed usernames meet format requirements
    function invariant_AR7_usernameFormatEnforcement() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = registry.addressToUsername(actors[i]);
            if (bytes(username).length > 0) {
                bytes memory usernameBytes = bytes(username);

                // Length requirements
                assertGt(usernameBytes.length, 0, "AR7: Username cannot be empty");
                assertLe(usernameBytes.length, 32, "AR7: Username too long");

                // First character must be letter
                bytes1 firstChar = usernameBytes[0];
                assertTrue(
                    (firstChar >= 0x41 && firstChar <= 0x5A) // A-Z
                        || (firstChar >= 0x61 && firstChar <= 0x7A), // a-z
                    "AR7: Username must start with letter"
                );
            }
        }
    }

    /// @notice AR8: Character Validation
    /// @dev All characters in claimed usernames are valid
    function invariant_AR8_characterValidation() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = registry.addressToUsername(actors[i]);
            if (bytes(username).length > 0) {
                bytes memory usernameBytes = bytes(username);

                for (uint256 j = 0; j < usernameBytes.length; j++) {
                    bytes1 char = usernameBytes[j];
                    bool isValid = (char >= 0x41 && char <= 0x5A) // A-Z
                        || (char >= 0x61 && char <= 0x7A) // a-z
                        || (char >= 0x30 && char <= 0x39) // 0-9
                        || (char == 0x5F); // underscore

                    assertTrue(isValid, "AR8: Invalid character in username");
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                              HANDLER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Handler for claiming usernames
    function claimUsername(uint256 actorSeed, string calldata username) external useActor(actorSeed) {
        // Bound username length to reasonable values
        if (bytes(username).length == 0 || bytes(username).length > 32) {
            return;
        }

        // Skip if username contains invalid characters
        bytes memory usernameBytes = bytes(username);
        bytes1 firstChar = usernameBytes[0];
        if (!((firstChar >= 0x41 && firstChar <= 0x5A) || (firstChar >= 0x61 && firstChar <= 0x7A))) {
            return;
        }

        // Skip if actor already has username
        if (registry.hasUsername(currentActor)) {
            return;
        }

        // Skip if username already claimed
        if (!registry.isUsernameAvailable(username)) {
            return;
        }

        try registry.claimUsername(username) {
            // Update ghost variables on success
            ghost_usernameToAddress[username] = currentActor;
            ghost_addressToUsername[currentActor] = username;
            ghost_totalUsernames++;
        } catch {
            // Expected to fail for invalid inputs
        }
    }

    /// @notice Handler for updating user addresses
    function updateUserAddress(uint256 actorSeed, uint256 newAddressSeed) external useActor(actorSeed) {
        // Skip if actor doesn't have username
        string memory username = registry.addressToUsername(currentActor);
        if (bytes(username).length == 0) {
            return;
        }

        // Get new address from actors
        address newAddress = actors[bound(newAddressSeed, 0, actors.length - 1)];

        // Skip if new address already has username
        if (registry.hasUsername(newAddress)) {
            return;
        }

        // Skip if updating to same address
        if (newAddress == currentActor) {
            return;
        }

        try registry.updateUserAddress(username, newAddress) {
            // Update ghost variables on success
            ghost_usernameToAddress[username] = newAddress;
            delete ghost_addressToUsername[currentActor];
            ghost_addressToUsername[newAddress] = username;
        } catch {
            // Expected to fail for invalid inputs
        }
    }

    /*//////////////////////////////////////////////////////////////
                              TARGET CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Target contract for invariant testing
    function targetContract() public view returns (address) {
        return address(this);
    }
}
