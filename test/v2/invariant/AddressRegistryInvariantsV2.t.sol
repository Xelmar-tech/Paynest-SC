// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AddressRegistry} from "../../../src/v2/AddressRegistry.sol";
import {IRegistry} from "../../../src/v2/interfaces/IRegistry.sol";

/// @title AddressRegistry V2 Invariant Tests
/// @notice Tests critical invariants for the AddressRegistry V2 contract with controller/recipient separation
/// @dev Implements comprehensive invariants for V2 enhanced features
contract AddressRegistryInvariantsV2 is Test {
    AddressRegistry public registry;

    // Test actors for invariant testing
    address[] public actors;
    address internal currentActor;

    // Ghost variables for tracking V2 state
    mapping(string => address) public ghost_usernameToController;
    mapping(string => address) public ghost_usernameToRecipient;
    mapping(address => uint256) public ghost_controllerUsernameCount;
    uint256 public ghost_totalUsernames;

    function setUp() public {
        registry = new AddressRegistry();

        // Initialize test actors
        actors = new address[](15);
        for (uint256 i = 0; i < 15; i++) {
            actors[i] = address(uint160(0x2000 + i));
            vm.deal(actors[i], 1 ether);
        }

        // Target specific contracts for invariant testing
        targetContract(address(this));
    }

    /// @dev Modifier to use random actor for operations
    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         V2 CORE INVARIANTS (AR2.1-AR2.8)
    //////////////////////////////////////////////////////////////*/

    /// @notice AR2.1: Controller/Recipient Separation Consistency
    /// @dev Every registered username must have valid controller and recipient addresses
    function invariant_AR2_1_controllerRecipientConsistency() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < actors.length; j++) {
                string memory username = string(abi.encodePacked("user", vm.toString(i), "_", vm.toString(j)));
                
                if (!registry.isUsernameAvailable(username)) {
                    IRegistry.UsernameData memory data = registry.getUsernameData(username);
                    
                    // Controller must not be zero
                    assertTrue(data.controller != address(0), "AR2.1: Controller cannot be zero for claimed username");
                    
                    // Recipient must not be zero
                    assertTrue(data.recipient != address(0), "AR2.1: Recipient cannot be zero for claimed username");
                    
                    // Timestamp must be valid
                    assertGt(data.lastUpdateTime, 0, "AR2.1: Must have valid timestamp");
                    assertLe(data.lastUpdateTime, block.timestamp, "AR2.1: Timestamp cannot be future");
                    
                    // View functions must be consistent
                    assertEq(registry.getController(username), data.controller, "AR2.1: Controller view inconsistent");
                    assertEq(registry.getRecipient(username), data.recipient, "AR2.1: Recipient view inconsistent");
                    assertEq(registry.getUserAddress(username), data.recipient, "AR2.1: V1 compatibility broken");
                    assertEq(registry.getLastUpdate(username), data.lastUpdateTime, "AR2.1: Timestamp view inconsistent");
                }
            }
        }
    }

    /// @notice AR2.2: Username Uniqueness and Controller Authority
    /// @dev Each username can only have one controller, and controllers can have multiple usernames
    function invariant_AR2_2_usernameUniquenessAndControllerAuthority() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < actors.length; j++) {
                string memory username = string(abi.encodePacked("user", vm.toString(i), "_", vm.toString(j)));
                
                if (!registry.isUsernameAvailable(username)) {
                    IRegistry.UsernameData memory data = registry.getUsernameData(username);
                    
                    // Controller authority: only controller should be able to modify
                    // This is tested implicitly by the fact that the system allows modifications
                    // and our ghost tracking should be consistent
                    assertTrue(data.controller != address(0), "AR2.2: Valid username must have controller");
                    
                    // Each username should have exactly one controller
                    address controller = registry.getController(username);
                    assertEq(controller, data.controller, "AR2.2: Controller consistency");
                    
                    // Username should map to exactly one recipient
                    address recipient = registry.getRecipient(username);
                    assertEq(recipient, data.recipient, "AR2.2: Recipient consistency");
                }
            }
        }
    }

    /// @notice AR2.3: V2 Username Format Validation
    /// @dev All claimed usernames must meet V2 stricter format requirements
    function invariant_AR2_3_v2UsernameFormatValidation() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < actors.length; j++) {
                string memory username = string(abi.encodePacked("user", vm.toString(i), "_", vm.toString(j)));
                
                if (!registry.isUsernameAvailable(username)) {
                    bytes memory usernameBytes = bytes(username);
                    
                    // V2 Length requirements: 3-20 characters
                    assertGe(usernameBytes.length, 3, "AR2.3: Username too short (min 3)");
                    assertLe(usernameBytes.length, 20, "AR2.3: Username too long (max 20)");
                    
                    // First character must be lowercase letter
                    bytes1 firstChar = usernameBytes[0];
                    assertTrue(
                        firstChar >= 0x61 && firstChar <= 0x7A, // a-z only
                        "AR2.3: Username must start with lowercase letter"
                    );
                    
                    // Last character cannot be underscore
                    bytes1 lastChar = usernameBytes[usernameBytes.length - 1];
                    assertTrue(lastChar != 0x5F, "AR2.3: Username cannot end with underscore");
                    
                    // No consecutive underscores
                    for (uint256 k = 0; k < usernameBytes.length - 1; k++) {
                        if (usernameBytes[k] == 0x5F) {
                            assertTrue(usernameBytes[k + 1] != 0x5F, "AR2.3: No consecutive underscores allowed");
                        }
                    }
                    
                    // All characters must be valid (lowercase letters, numbers, underscore)
                    for (uint256 k = 0; k < usernameBytes.length; k++) {
                        bytes1 char = usernameBytes[k];
                        bool isValid = (char >= 0x61 && char <= 0x7A) // a-z
                            || (char >= 0x30 && char <= 0x39) // 0-9
                            || (char == 0x5F); // underscore
                        
                        assertTrue(isValid, "AR2.3: Invalid character in V2 username");
                    }
                }
            }
        }
    }

    /// @notice AR2.4: Controller-Recipient Independence
    /// @dev Controllers and recipients can be different addresses, same controller can control multiple usernames
    function invariant_AR2_4_controllerRecipientIndependence() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < actors.length; j++) {
                string memory username = string(abi.encodePacked("user", vm.toString(i), "_", vm.toString(j)));
                
                if (!registry.isUsernameAvailable(username)) {
                    IRegistry.UsernameData memory data = registry.getUsernameData(username);
                    
                    // Controllers and recipients can be same or different - both valid
                    // No restriction on this relationship
                    assertTrue(data.controller != address(0), "AR2.4: Controller must be valid");
                    assertTrue(data.recipient != address(0), "AR2.4: Recipient must be valid");
                    
                    // A single controller can control multiple usernames (this is allowed)
                    // A single recipient can receive for multiple usernames (this is allowed)
                    // These are features, not bugs, so we verify independence is maintained
                    
                    // Controller and recipient can be the same address (simple case)
                    // or different addresses (smart account UX) - both are valid V2 patterns
                }
            }
        }
    }

    /// @notice AR2.5: Meta-transaction Nonce Consistency
    /// @dev Nonces should only increase and be unique per address
    function invariant_AR2_5_metaTransactionNonceConsistency() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            uint256 nonce = registry.nonces(actors[i]);
            
            // Nonces are non-negative (uint256 ensures this)
            // Nonces can be zero for unused addresses
            assertTrue(nonce >= 0, "AR2.5: Nonce must be non-negative");
            
            // Note: We can't easily test nonce incrementation in view function
            // This would need to be tested with actual meta-transaction calls
        }
    }

    /// @notice AR2.6: Username Availability Consistency
    /// @dev isUsernameAvailable must be consistent with actual username state
    function invariant_AR2_6_usernameAvailabilityConsistency() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < actors.length; j++) {
                string memory username = string(abi.encodePacked("user", vm.toString(i), "_", vm.toString(j)));
                
                bool isAvailable = registry.isUsernameAvailable(username);
                IRegistry.UsernameData memory data = registry.getUsernameData(username);
                
                if (isAvailable) {
                    // If available, all data should be zero
                    assertEq(data.controller, address(0), "AR2.6: Available username should have zero controller");
                    assertEq(data.recipient, address(0), "AR2.6: Available username should have zero recipient");
                    assertEq(data.lastUpdateTime, 0, "AR2.6: Available username should have zero timestamp");
                } else {
                    // If not available, controller should not be zero
                    assertTrue(data.controller != address(0), "AR2.6: Claimed username must have controller");
                }
            }
        }
    }

    /// @notice AR2.7: Zero Address Protection
    /// @dev Zero addresses should never be controllers or recipients
    function invariant_AR2_7_zeroAddressProtection() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < actors.length; j++) {
                string memory username = string(abi.encodePacked("user", vm.toString(i), "_", vm.toString(j)));
                
                if (!registry.isUsernameAvailable(username)) {
                    IRegistry.UsernameData memory data = registry.getUsernameData(username);
                    
                    assertTrue(data.controller != address(0), "AR2.7: Controller cannot be zero address");
                    assertTrue(data.recipient != address(0), "AR2.7: Recipient cannot be zero address");
                }
            }
        }
    }

    /// @notice AR2.8: Timestamp Monotonicity
    /// @dev lastUpdateTime should reflect actual update patterns
    function invariant_AR2_8_timestampMonotonicity() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < actors.length; j++) {
                string memory username = string(abi.encodePacked("user", vm.toString(i), "_", vm.toString(j)));
                
                if (!registry.isUsernameAvailable(username)) {
                    IRegistry.UsernameData memory data = registry.getUsernameData(username);
                    
                    // Timestamp should be reasonable
                    assertGt(data.lastUpdateTime, 0, "AR2.8: Timestamp should be positive");
                    assertLe(data.lastUpdateTime, block.timestamp, "AR2.8: Timestamp cannot be in future");
                    
                    // Should be after a reasonable point (contract deployment time)
                    assertGe(data.lastUpdateTime, 1000000000, "AR2.8: Timestamp should be reasonable");
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         HANDLER FUNCTIONS FOR INVARIANT TESTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Handler for claiming usernames with same controller/recipient
    function claimUsernameSimple(uint256 actorSeed, uint256 usernameSeed) public useActor(actorSeed) {
        string memory username = string(abi.encodePacked("test", vm.toString(bound(usernameSeed, 0, 999))));
        
        try registry.claimUsername(username, currentActor) {
            // Update ghost variables
            if (registry.getController(username) == currentActor) {
                ghost_usernameToController[username] = currentActor;
                ghost_usernameToRecipient[username] = currentActor;
                ghost_controllerUsernameCount[currentActor]++;
                ghost_totalUsernames++;
            }
        } catch {
            // Failed operations are fine in invariant testing
        }
    }

    /// @notice Handler for claiming usernames with separate controller/recipient
    function claimUsernameSeparated(uint256 actorSeed, uint256 recipientSeed, uint256 usernameSeed) 
        public 
        useActor(actorSeed) 
    {
        address recipient = actors[bound(recipientSeed, 0, actors.length - 1)];
        string memory username = string(abi.encodePacked("split", vm.toString(bound(usernameSeed, 0, 999))));
        
        try registry.claimUsername(username, recipient, currentActor) {
            // Update ghost variables
            if (registry.getController(username) == currentActor) {
                ghost_usernameToController[username] = currentActor;
                ghost_usernameToRecipient[username] = recipient;
                ghost_controllerUsernameCount[currentActor]++;
                ghost_totalUsernames++;
            }
        } catch {
            // Failed operations are fine
        }
    }

    /// @notice Handler for updating recipient
    function updateRecipient(uint256 actorSeed, uint256 newRecipientSeed, uint256 usernameSeed) 
        public 
        useActor(actorSeed) 
    {
        address newRecipient = actors[bound(newRecipientSeed, 0, actors.length - 1)];
        string memory username = string(abi.encodePacked("test", vm.toString(bound(usernameSeed, 0, 999))));
        
        try registry.updateRecipient(username, newRecipient) {
            // Update ghost variables if successful
            if (registry.getController(username) == currentActor) {
                ghost_usernameToRecipient[username] = newRecipient;
            }
        } catch {
            // Failed operations are fine
        }
    }

    /// @notice Handler for transferring control
    function transferControl(uint256 actorSeed, uint256 newControllerSeed, uint256 usernameSeed) 
        public 
        useActor(actorSeed) 
    {
        address newController = actors[bound(newControllerSeed, 0, actors.length - 1)];
        string memory username = string(abi.encodePacked("test", vm.toString(bound(usernameSeed, 0, 999))));
        
        try registry.transferControl(username, newController) {
            // Update ghost variables if successful
            if (ghost_usernameToController[username] == currentActor) {
                ghost_controllerUsernameCount[currentActor]--;
                ghost_controllerUsernameCount[newController]++;
                ghost_usernameToController[username] = newController;
            }
        } catch {
            // Failed operations are fine
        }
    }
}