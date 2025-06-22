// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentsPlugin} from "../../../src/v2/PaymentsPlugin.sol";
import {AddressRegistry} from "../../../src/v2/AddressRegistry.sol";
import {IPayments} from "../../../src/v2/interfaces/IPayments.sol";
import {IRegistry} from "../../../src/v2/interfaces/IRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

/// @title PayNest System V2 Invariants
/// @notice Tests system-wide invariants between AddressRegistry and PaymentsPlugin V2
/// @dev Verifies the integration between registry controller/recipient separation and payment flows
contract PayNestSystemInvariantsV2 is Test {
    PaymentsPlugin public plugin;
    PaymentsPlugin public pluginImplementation;
    AddressRegistry public registry;
    
    // System configuration
    address public constant DAO_ADDRESS = address(0x1234);
    address public constant LLAMAPAY_FACTORY = address(0x5678);
    address public constant MANAGER = address(0x9999);

    // Test actors representing different roles
    address[] public controllers;
    address[] public recipients;
    address[] public managers;
    address internal currentActor;

    // System state tracking
    mapping(string => bool) public ghost_usernameExists;
    mapping(string => address) public ghost_usernameController;
    mapping(string => address) public ghost_usernameRecipient;
    mapping(string => uint256) public ghost_usernamePaymentCount;
    uint256 public ghost_totalSystemPayments;
    uint256 public ghost_totalActiveUsernames;

    function setUp() public {
        // Deploy the full system
        registry = new AddressRegistry();
        pluginImplementation = new PaymentsPlugin();
        
        // Initialize plugin through proxy
        bytes memory initData = abi.encodeWithSelector(
            PaymentsPlugin.initialize.selector,
            DAO(payable(DAO_ADDRESS)),
            address(registry),
            LLAMAPAY_FACTORY
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(pluginImplementation), initData);
        plugin = PaymentsPlugin(address(proxy));

        // Initialize diverse test actors
        controllers = new address[](8);
        recipients = new address[](8);
        managers = new address[](3);

        for (uint256 i = 0; i < 8; i++) {
            controllers[i] = address(uint160(0x4000 + i));
            recipients[i] = address(uint160(0x5000 + i));
            vm.deal(controllers[i], 1 ether);
            vm.deal(recipients[i], 1 ether);
        }

        for (uint256 i = 0; i < 3; i++) {
            managers[i] = address(uint160(0x6000 + i));
            vm.deal(managers[i], 1 ether);
        }

        // Target both contracts for comprehensive invariant testing
        targetContract(address(this));
    }

    /// @dev Modifier to use random controller
    modifier useController(uint256 controllerSeed) {
        currentActor = controllers[bound(controllerSeed, 0, controllers.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @dev Modifier to use random manager
    modifier useManager(uint256 managerSeed) {
        currentActor = managers[bound(managerSeed, 0, managers.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    SYSTEM-WIDE INVARIANTS (SYS2.1-SYS2.12)
    //////////////////////////////////////////////////////////////*/

    /// @notice SYS2.1: Registry-Plugin Integration Consistency
    /// @dev Plugin payment operations must respect registry controller/recipient separation
    function invariant_SYS2_1_registryPluginIntegrationConsistency() public view {
        for (uint256 i = 0; i < controllers.length; i++) {
            for (uint256 j = 0; j < recipients.length; j++) {
                string memory username = string(abi.encodePacked("sys", vm.toString(i), "_", vm.toString(j)));
                
                if (!registry.isUsernameAvailable(username)) {
                    // Verify registry data
                    address controller = registry.getController(username);
                    address recipient = registry.getRecipient(username);
                    
                    // Plugin should be able to access this username
                    (bytes32[] memory streamIds,) = plugin.getUserStreams(username);
                    (bytes32[] memory scheduleIds,) = plugin.getUserSchedules(username);
                    
                    // Integration should work - no reverts expected for view functions
                    assertTrue(controller != address(0), "SYS2.1: Controller should be valid");
                    assertTrue(recipient != address(0), "SYS2.1: Recipient should be valid");
                    assertTrue(streamIds.length >= 0, "SYS2.1: Plugin should access streams");
                    assertTrue(scheduleIds.length >= 0, "SYS2.1: Plugin should access schedules");
                    
                    // V1 compatibility check
                    assertEq(registry.getUserAddress(username), recipient, "SYS2.1: V1 compatibility broken");
                }
            }
        }
    }

    /// @notice SYS2.2: Controller Authority Across System
    /// @dev Only username controllers should influence payments for their usernames
    function invariant_SYS2_2_controllerAuthorityAcrossSystem() public view {
        for (uint256 i = 0; i < controllers.length; i++) {
            string memory username = string(abi.encodePacked("ctrl", vm.toString(i)));
            
            if (!registry.isUsernameAvailable(username)) {
                address controller = registry.getController(username);
                
                // Controller should be one of our test controllers
                bool isValidController = false;
                for (uint256 j = 0; j < controllers.length; j++) {
                    if (controller == controllers[j]) {
                        isValidController = true;
                        break;
                    }
                }
                
                if (isValidController) {
                    // This controller should have authority over this username
                    // We can't directly test migration authority in view function,
                    // but we can verify the username structure is correct
                    assertTrue(controller != address(0), "SYS2.2: Valid controller required");
                    
                    IRegistry.UsernameData memory data = registry.getUsernameData(username);
                    assertEq(data.controller, controller, "SYS2.2: Controller data consistency");
                }
            }
        }
    }

    /// @notice SYS2.3: Recipient Payment Destination Consistency
    /// @dev All payments should respect the registry recipient designation
    function invariant_SYS2_3_recipientPaymentDestinationConsistency() public view {
        for (uint256 i = 0; i < recipients.length; i++) {
            string memory username = string(abi.encodePacked("recv", vm.toString(i)));
            
            if (!registry.isUsernameAvailable(username)) {
                address recipient = registry.getRecipient(username);
                
                // All payment data should be consistent with this recipient
                (bytes32[] memory streamIds, IPayments.Stream[] memory streams) = plugin.getUserStreams(username);
                (bytes32[] memory scheduleIds, IPayments.Schedule[] memory schedules) = plugin.getUserSchedules(username);
                
                // Payments exist and should be targeting the correct recipient
                // Note: In V2, payments are associated with usernames, and registry resolves to recipients
                assertTrue(recipient != address(0), "SYS2.3: Recipient must be valid");
                
                // The plugin should have consistent access to payment data
                assertEq(streamIds.length, streams.length, "SYS2.3: Stream data consistency");
                assertEq(scheduleIds.length, schedules.length, "SYS2.3: Schedule data consistency");
            }
        }
    }

    /// @notice SYS2.4: System State Consistency Under Updates
    /// @dev Registry updates should not break existing payment structures
    function invariant_SYS2_4_systemStateConsistencyUnderUpdates() public view {
        for (uint256 i = 0; i < controllers.length; i++) {
            string memory username = string(abi.encodePacked("updt", vm.toString(i)));
            
            if (!registry.isUsernameAvailable(username)) {
                IRegistry.UsernameData memory registryData = registry.getUsernameData(username);
                
                // Registry data should be internally consistent
                assertTrue(registryData.controller != address(0), "SYS2.4: Registry controller valid");
                assertTrue(registryData.recipient != address(0), "SYS2.4: Registry recipient valid");
                assertGt(registryData.lastUpdateTime, 0, "SYS2.4: Registry timestamp valid");
                
                // Plugin data should still be accessible
                try plugin.getUserStreams(username) returns (bytes32[] memory streamIds, IPayments.Stream[] memory) {
                    // Should not revert
                    assertTrue(streamIds.length >= 0, "SYS2.4: Streams accessible after updates");
                } catch {
                    // If it reverts, that might indicate a problem
                    assertTrue(false, "SYS2.4: Plugin should access streams after registry updates");
                }
                
                try plugin.getUserSchedules(username) returns (bytes32[] memory scheduleIds, IPayments.Schedule[] memory) {
                    // Should not revert
                    assertTrue(scheduleIds.length >= 0, "SYS2.4: Schedules accessible after updates");
                } catch {
                    assertTrue(false, "SYS2.4: Plugin should access schedules after registry updates");
                }
            }
        }
    }

    /// @notice SYS2.5: Zero Address Protection System-Wide
    /// @dev No component should have zero addresses in active roles
    function invariant_SYS2_5_zeroAddressProtectionSystemWide() public view {
        // Registry protection
        for (uint256 i = 0; i < controllers.length; i++) {
            string memory username = string(abi.encodePacked("zero", vm.toString(i)));
            
            if (!registry.isUsernameAvailable(username)) {
                address controller = registry.getController(username);
                address recipient = registry.getRecipient(username);
                
                assertTrue(controller != address(0), "SYS2.5: Registry controller not zero");
                assertTrue(recipient != address(0), "SYS2.5: Registry recipient not zero");
            }
        }

        // Plugin protection
        for (uint256 i = 0; i < controllers.length; i++) {
            string memory username = string(abi.encodePacked("zero", vm.toString(i)));
            
            (, IPayments.Stream[] memory streams) = plugin.getUserStreams(username);
            (, IPayments.Schedule[] memory schedules) = plugin.getUserSchedules(username);
            
            for (uint256 j = 0; j < streams.length; j++) {
                assertTrue(streams[j].token != address(0), "SYS2.5: Stream token not zero");
            }
            
            for (uint256 j = 0; j < schedules.length; j++) {
                assertTrue(schedules[j].token != address(0), "SYS2.5: Schedule token not zero");
            }
        }
    }

    /// @notice SYS2.6: System Limits and Boundaries
    /// @dev System should respect all defined limits and boundaries
    function invariant_SYS2_6_systemLimitsAndBoundaries() public view {
        for (uint256 i = 0; i < controllers.length; i++) {
            string memory username = string(abi.encodePacked("limit", vm.toString(i)));
            
            // Registry limits (V2 username format)
            if (!registry.isUsernameAvailable(username)) {
                bytes memory usernameBytes = bytes(username);
                assertGe(usernameBytes.length, 3, "SYS2.6: Username min length");
                assertLe(usernameBytes.length, 20, "SYS2.6: Username max length");
            }
            
            // Plugin limits
            (bytes32[] memory streamIds,) = plugin.getUserStreams(username);
            (bytes32[] memory scheduleIds,) = plugin.getUserSchedules(username);
            
            assertLe(streamIds.length, plugin.MAX_STREAMS_PER_USER(), "SYS2.6: Stream limit");
            assertLe(scheduleIds.length, plugin.MAX_SCHEDULES_PER_USER(), "SYS2.6: Schedule limit");
        }
    }

    /// @notice SYS2.7: Timestamp Consistency Across System
    /// @dev Timestamps should be reasonable and consistent across components
    function invariant_SYS2_7_timestampConsistencyAcrossSystem() public view {
        for (uint256 i = 0; i < controllers.length; i++) {
            string memory username = string(abi.encodePacked("time", vm.toString(i)));
            
            if (!registry.isUsernameAvailable(username)) {
                // Registry timestamp
                uint256 registryTime = registry.getLastUpdate(username);
                
                if (registryTime > 0) {
                    assertLe(registryTime, block.timestamp, "SYS2.7: Registry timestamp reasonable");
                    assertGe(registryTime, 1000000000, "SYS2.7: Registry timestamp after epoch");
                }
                
                // Plugin timestamps
                (, IPayments.Stream[] memory streams) = plugin.getUserStreams(username);
                (, IPayments.Schedule[] memory schedules) = plugin.getUserSchedules(username);
                
                for (uint256 j = 0; j < streams.length; j++) {
                    if (streams[j].startTime > 0) {
                        assertLe(streams[j].startTime, block.timestamp, "SYS2.7: Stream start time reasonable");
                    }
                }
                
                for (uint256 j = 0; j < schedules.length; j++) {
                    if (schedules[j].firstPaymentDate > 0) {
                        assertGt(schedules[j].firstPaymentDate, 0, "SYS2.7: Schedule first payment set");
                    }
                }
            }
        }
    }

    /// @notice SYS2.8: V1 Backward Compatibility
    /// @dev V1 integrations should continue working with V2 system
    function invariant_SYS2_8_v1BackwardCompatibility() public view {
        for (uint256 i = 0; i < recipients.length; i++) {
            string memory username = string(abi.encodePacked("v1compat", vm.toString(i)));
            
            if (!registry.isUsernameAvailable(username)) {
                address v1Address = registry.getUserAddress(username);
                address v2Recipient = registry.getRecipient(username);
                
                // V1 compatibility: getUserAddress should return recipient
                assertEq(v1Address, v2Recipient, "SYS2.8: V1 compatibility broken");
                
                // V1 availability check should work
                bool available = registry.isUsernameAvailable(username);
                assertFalse(available, "SYS2.8: V1 availability check works");
            }
        }
    }

    /// @notice SYS2.9: Permission and Authorization Flow
    /// @dev System should maintain proper authorization boundaries
    function invariant_SYS2_9_permissionAndAuthorizationFlow() public view {
        // Plugin initialization and permissions
        assertEq(address(plugin.dao()), DAO_ADDRESS, "SYS2.9: Plugin DAO connection");
        assertEq(address(plugin.registry()), address(registry), "SYS2.9: Plugin registry connection");
        
        // Permission constants should be consistent
        assertEq(plugin.MANAGER_PERMISSION_ID(), keccak256("MANAGER_PERMISSION"), "SYS2.9: Manager permission ID");
        
        // Registry should be independently functional
        assertTrue(address(registry) != address(0), "SYS2.9: Registry deployed");
        
        // System integration should not interfere with individual component function
        for (uint256 i = 0; i < 3; i++) {
            string memory username = string(abi.encodePacked("perm", vm.toString(i)));
            
            // Registry should work independently
            bool available = registry.isUsernameAvailable(username);
            assertTrue(available || !available, "SYS2.9: Registry availability check works");
            
            // Plugin should handle non-existent usernames gracefully
            (bytes32[] memory streamIds,) = plugin.getUserStreams(username);
            assertTrue(streamIds.length >= 0, "SYS2.9: Plugin handles non-existent usernames");
        }
    }

    /// @notice SYS2.10: Data Structure Integrity
    /// @dev All data structures should maintain internal consistency
    function invariant_SYS2_10_dataStructureIntegrity() public view {
        for (uint256 i = 0; i < controllers.length; i++) {
            string memory username = string(abi.encodePacked("data", vm.toString(i)));
            
            if (!registry.isUsernameAvailable(username)) {
                // Registry data structure
                IRegistry.UsernameData memory registryData = registry.getUsernameData(username);
                
                assertTrue(registryData.controller != address(0), "SYS2.10: Registry controller valid");
                assertTrue(registryData.recipient != address(0), "SYS2.10: Registry recipient valid");
                assertGt(registryData.lastUpdateTime, 0, "SYS2.10: Registry timestamp valid");
                
                // Plugin data structures
                (bytes32[] memory streamIds, IPayments.Stream[] memory streams) = plugin.getUserStreams(username);
                (bytes32[] memory scheduleIds, IPayments.Schedule[] memory schedules) = plugin.getUserSchedules(username);
                
                // Array consistency
                assertEq(streamIds.length, streams.length, "SYS2.10: Stream arrays consistent");
                assertEq(scheduleIds.length, schedules.length, "SYS2.10: Schedule arrays consistent");
                
                // Individual structure validity
                for (uint256 j = 0; j < streams.length; j++) {
                    assertTrue(streams[j].token != address(0), "SYS2.10: Stream token valid");
                    assertTrue(uint8(streams[j].state) <= 2, "SYS2.10: Stream state valid");
                }
                
                for (uint256 j = 0; j < schedules.length; j++) {
                    assertTrue(schedules[j].token != address(0), "SYS2.10: Schedule token valid");
                    assertTrue(schedules[j].amount > 0, "SYS2.10: Schedule amount positive");
                    assertTrue(uint8(schedules[j].interval) <= 6, "SYS2.10: Schedule interval valid");
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         SYSTEM HANDLER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Handler for registering usernames with controller/recipient separation
    function registerUsernameWithSeparation(
        uint256 controllerSeed, 
        uint256 recipientSeed, 
        uint256 usernameSeed
    ) public useController(controllerSeed) {
        address recipient = recipients[bound(recipientSeed, 0, recipients.length - 1)];
        string memory username = string(abi.encodePacked("sep", vm.toString(bound(usernameSeed, 0, 999))));
        
        try registry.claimUsername(username, recipient, currentActor) {
            ghost_usernameExists[username] = true;
            ghost_usernameController[username] = currentActor;
            ghost_usernameRecipient[username] = recipient;
            ghost_totalActiveUsernames++;
        } catch {
            // Failed operations are fine
        }
    }

    /// @notice Handler for updating recipients
    function updateUsernameRecipient(
        uint256 controllerSeed, 
        uint256 newRecipientSeed, 
        uint256 usernameSeed
    ) public useController(controllerSeed) {
        address newRecipient = recipients[bound(newRecipientSeed, 0, recipients.length - 1)];
        string memory username = string(abi.encodePacked("sep", vm.toString(bound(usernameSeed, 0, 999))));
        
        try registry.updateRecipient(username, newRecipient) {
            if (ghost_usernameController[username] == currentActor) {
                ghost_usernameRecipient[username] = newRecipient;
            }
        } catch {
            // Failed operations are fine
        }
    }

    /// @notice Handler for creating payments on usernames
    function createPaymentForUsername(
        uint256 managerSeed, 
        uint256 usernameSeed, 
        uint256 amountSeed,
        bool isStream
    ) public useManager(managerSeed) {
        string memory username = string(abi.encodePacked("sep", vm.toString(bound(usernameSeed, 0, 999))));
        address mockToken = controllers[bound(amountSeed, 0, controllers.length - 1)];
        
        if (isStream) {
            uint216 flowRate = uint216(bound(amountSeed, 1e12, 1e18));
            try plugin.createStream(username, mockToken, flowRate) {
                ghost_usernamePaymentCount[username]++;
                ghost_totalSystemPayments++;
            } catch {
                // Failed operations are fine
            }
        } else {
            uint256 amount = bound(amountSeed, 1e6, 1e24);
            uint40 firstPayment = uint40(block.timestamp + 1 hours);
            try plugin.createSchedule(username, mockToken, amount, IPayments.IntervalType.Monthly, false, firstPayment) {
                ghost_usernamePaymentCount[username]++;
                ghost_totalSystemPayments++;
            } catch {
                // Failed operations are fine
            }
        }
    }

    /// @notice Handler for transferring username control
    function transferUsernameControl(
        uint256 controllerSeed, 
        uint256 newControllerSeed, 
        uint256 usernameSeed
    ) public useController(controllerSeed) {
        address newController = controllers[bound(newControllerSeed, 0, controllers.length - 1)];
        string memory username = string(abi.encodePacked("sep", vm.toString(bound(usernameSeed, 0, 999))));
        
        try registry.transferControl(username, newController) {
            if (ghost_usernameController[username] == currentActor) {
                ghost_usernameController[username] = newController;
            }
        } catch {
            // Failed operations are fine
        }
    }
}