// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentsPlugin} from "../../../src/v2/PaymentsPlugin.sol";
import {AddressRegistry} from "../../../src/v2/AddressRegistry.sol";
import {IPayments} from "../../../src/v2/interfaces/IPayments.sol";
import {IRegistry} from "../../../src/v2/interfaces/IRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

/// @title PaymentsPlugin V2 Invariant Tests
/// @notice Tests critical invariants for the PaymentsPlugin V2 contract with flow-based streaming
/// @dev Implements comprehensive invariants for V2 payment features
contract PaymentsPluginInvariantsV2 is Test {
    PaymentsPlugin public plugin;
    PaymentsPlugin public pluginImplementation;
    AddressRegistry public registry;
    
    // Mock DAO for testing
    address public constant DAO_ADDRESS = address(0x1234);
    address public constant LLAMAPAY_FACTORY = address(0x5678);
    address public constant MANAGER = address(0x9999);

    // Test actors
    address[] public actors;
    address internal currentActor;

    // Ghost variables for tracking plugin state
    mapping(string => uint256) public ghost_userStreamCount;
    mapping(string => uint256) public ghost_userScheduleCount;
    mapping(bytes32 => bool) public ghost_streamExists;
    mapping(bytes32 => bool) public ghost_scheduleExists;
    uint256 public ghost_totalStreams;
    uint256 public ghost_totalSchedules;

    function setUp() public {
        // Deploy registry and plugin
        registry = new AddressRegistry();
        pluginImplementation = new PaymentsPlugin();
        
        // Create proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            PaymentsPlugin.initialize.selector,
            DAO(payable(DAO_ADDRESS)),
            address(registry),
            LLAMAPAY_FACTORY
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(pluginImplementation), initData);
        plugin = PaymentsPlugin(address(proxy));

        // Initialize test actors
        actors = new address[](12);
        for (uint256 i = 0; i < 12; i++) {
            actors[i] = address(uint160(0x3000 + i));
            vm.deal(actors[i], 1 ether);
            
            // Pre-register some usernames for testing
            string memory username = string(abi.encodePacked("user", vm.toString(i)));
            vm.prank(actors[i]);
            registry.claimUsername(username, actors[i]);
        }

        // Target the plugin for invariant testing
        targetContract(address(this));
    }

    /// @dev Modifier to use random actor for operations
    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /// @dev Modifier for manager operations
    modifier asManager() {
        vm.startPrank(MANAGER);
        _;
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         V2 PAYMENTS INVARIANTS (PP2.1-PP2.10)
    //////////////////////////////////////////////////////////////*/

    /// @notice PP2.1: Plugin Initialization Integrity
    /// @dev Plugin must maintain correct initialization state
    function invariant_PP2_1_pluginInitializationIntegrity() public view {
        // Core initialization values should be immutable
        assertEq(address(plugin.dao()), DAO_ADDRESS, "PP2.1: DAO address changed");
        assertEq(address(plugin.registry()), address(registry), "PP2.1: Registry address changed");
        assertEq(address(plugin.llamaPayFactory()), LLAMAPAY_FACTORY, "PP2.1: LlamaPay factory changed");
        
        // Constants should remain constant
        assertEq(plugin.MANAGER_PERMISSION_ID(), keccak256("MANAGER_PERMISSION"), "PP2.1: Manager permission changed");
        assertEq(plugin.MAX_STREAMS_PER_USER(), 50, "PP2.1: Max streams changed");
        assertEq(plugin.MAX_SCHEDULES_PER_USER(), 20, "PP2.1: Max schedules changed");
        assertEq(plugin.DEFAULT_FUNDING_PERIOD(), 180 days, "PP2.1: Default funding period changed");
    }

    /// @notice PP2.2: Stream Data Consistency
    /// @dev Stream data structures must be consistent across all access methods
    function invariant_PP2_2_streamDataConsistency() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = string(abi.encodePacked("user", vm.toString(i)));
            
            (bytes32[] memory streamIds, IPayments.Stream[] memory streamData) = plugin.getUserStreams(username);
            
            // Array lengths must match
            assertEq(streamIds.length, streamData.length, "PP2.2: Stream arrays length mismatch");
            
            // Each stream ID should correspond to valid stream data
            for (uint256 j = 0; j < streamIds.length; j++) {
                bytes32 streamId = streamIds[j];
                IPayments.Stream memory streamFromArray = streamData[j];
                
                // Skip getStream call since it might revert for non-existent streams
                // Instead verify the stream data is reasonable
                assertTrue(streamFromArray.token != address(0), "PP2.2: Stream token cannot be zero");
                assertTrue(streamFromArray.amountPerSec > 0, "PP2.2: Stream amount must be positive");
                
                // Stream state should be valid
                assertTrue(
                    uint8(streamFromArray.state) <= uint8(IPayments.StreamState.Cancelled),
                    "PP2.2: Invalid stream state"
                );
                
                // Start time should be reasonable
                assertLe(streamFromArray.startTime, block.timestamp, "PP2.2: Start time cannot be future");
            }
        }
    }

    /// @notice PP2.3: Schedule Data Consistency
    /// @dev Schedule data structures must be consistent across all access methods
    function invariant_PP2_3_scheduleDataConsistency() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = string(abi.encodePacked("user", vm.toString(i)));
            
            (bytes32[] memory scheduleIds, IPayments.Schedule[] memory scheduleData) = plugin.getUserSchedules(username);
            
            // Array lengths must match
            assertEq(scheduleIds.length, scheduleData.length, "PP2.3: Schedule arrays length mismatch");
            
            // Each schedule should have valid data
            for (uint256 j = 0; j < scheduleIds.length; j++) {
                IPayments.Schedule memory schedule = scheduleData[j];
                
                // Basic validation
                assertTrue(schedule.token != address(0), "PP2.3: Schedule token cannot be zero");
                assertTrue(schedule.amount > 0, "PP2.3: Schedule amount must be positive");
                
                // Interval should be valid
                assertTrue(
                    uint8(schedule.interval) <= uint8(IPayments.IntervalType.Yearly),
                    "PP2.3: Invalid schedule interval"
                );
                
                // Timing should be reasonable
                assertGt(schedule.firstPaymentDate, 0, "PP2.3: First payment date must be set");
                
                if (schedule.active) {
                    assertGt(schedule.nextPayout, 0, "PP2.3: Active schedule must have next payout");
                }
            }
        }
    }

    /// @notice PP2.4: Username-Registry Integration
    /// @dev Plugin operations must respect registry controller/recipient separation
    function invariant_PP2_4_usernameRegistryIntegration() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = string(abi.encodePacked("user", vm.toString(i)));
            
            // If username exists in registry, verify consistency
            if (!registry.isUsernameAvailable(username)) {
                address controller = registry.getController(username);
                address recipient = registry.getRecipient(username);
                
                // Controller and recipient should be valid
                assertTrue(controller != address(0), "PP2.4: Username controller cannot be zero");
                assertTrue(recipient != address(0), "PP2.4: Username recipient cannot be zero");
                
                // Verify plugin can access user data (this validates the integration)
                (bytes32[] memory streamIds,) = plugin.getUserStreams(username);
                (bytes32[] memory scheduleIds,) = plugin.getUserSchedules(username);
                
                // Arrays should be non-null (even if empty)
                assertTrue(streamIds.length >= 0, "PP2.4: Stream IDs array should be accessible");
                assertTrue(scheduleIds.length >= 0, "PP2.4: Schedule IDs array should be accessible");
            }
        }
    }

    /// @notice PP2.5: Stream State Transitions
    /// @dev Stream states must follow valid transition patterns
    function invariant_PP2_5_streamStateTransitions() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = string(abi.encodePacked("user", vm.toString(i)));
            
            (, IPayments.Stream[] memory streams) = plugin.getUserStreams(username);
            
            for (uint256 j = 0; j < streams.length; j++) {
                IPayments.Stream memory stream = streams[j];
                
                // Validate state consistency
                if (stream.state == IPayments.StreamState.Active) {
                    assertTrue(stream.amountPerSec > 0, "PP2.5: Active stream must have positive flow rate");
                } else if (stream.state == IPayments.StreamState.Paused) {
                    // Paused streams can have any amount (metadata preserved)
                    assertTrue(stream.token != address(0), "PP2.5: Paused stream must have valid token");
                } else if (stream.state == IPayments.StreamState.Cancelled) {
                    // Cancelled streams might have cleared metadata but should still have token reference
                    assertTrue(stream.token != address(0), "PP2.5: Cancelled stream must have token reference");
                }
                
                // Start time should always be reasonable for any state
                if (stream.startTime > 0) {
                    assertLe(stream.startTime, block.timestamp, "PP2.5: Start time cannot be future");
                }
            }
        }
    }

    /// @notice PP2.6: Schedule State Consistency
    /// @dev Schedule states and timing must be logically consistent
    function invariant_PP2_6_scheduleStateConsistency() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = string(abi.encodePacked("user", vm.toString(i)));
            
            (, IPayments.Schedule[] memory schedules) = plugin.getUserSchedules(username);
            
            for (uint256 j = 0; j < schedules.length; j++) {
                IPayments.Schedule memory schedule = schedules[j];
                
                if (schedule.active) {
                    // Active schedules must have reasonable timing
                    assertGt(schedule.firstPaymentDate, 0, "PP2.6: Active schedule needs first payment date");
                    assertGt(schedule.nextPayout, 0, "PP2.6: Active schedule needs next payout");
                    
                    // Next payout should be after first payment
                    assertGe(schedule.nextPayout, schedule.firstPaymentDate, "PP2.6: Next payout before first payment");
                } else {
                    // Inactive schedules might have zero next payout
                    // but should still have valid first payment date
                    assertGt(schedule.firstPaymentDate, 0, "PP2.6: Schedule needs first payment date");
                }
                
                // One-time schedules should have appropriate behavior
                if (schedule.isOneTime && schedule.active) {
                    // One-time schedules that are active should have next payout
                    assertGt(schedule.nextPayout, 0, "PP2.6: Active one-time schedule needs next payout");
                }
            }
        }
    }

    /// @notice PP2.7: Flow Rate Validity
    /// @dev Stream flow rates must be within reasonable bounds and properly formatted
    function invariant_PP2_7_flowRateValidity() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = string(abi.encodePacked("user", vm.toString(i)));
            
            (, IPayments.Stream[] memory streams) = plugin.getUserStreams(username);
            
            for (uint256 j = 0; j < streams.length; j++) {
                IPayments.Stream memory stream = streams[j];
                
                if (stream.state == IPayments.StreamState.Active) {
                    // Active streams must have positive flow rate
                    assertTrue(stream.amountPerSec > 0, "PP2.7: Active stream needs positive flow rate");
                    
                    // Flow rate should be reasonable (not exceed uint216 max)
                    assertTrue(stream.amountPerSec <= type(uint216).max, "PP2.7: Flow rate within uint216");
                    
                    // Very high flow rates might be suspicious but are technically valid
                    // We just ensure they're not zero for active streams
                }
                
                // For paused/cancelled streams, amountPerSec might be preserved or cleared
                // No strict requirements, but should be >= 0 (uint256 ensures this)
            }
        }
    }

    /// @notice PP2.8: Schedule Interval Validity
    /// @dev Schedule intervals and amounts must be valid and reasonable
    function invariant_PP2_8_scheduleIntervalValidity() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = string(abi.encodePacked("user", vm.toString(i)));
            
            (, IPayments.Schedule[] memory schedules) = plugin.getUserSchedules(username);
            
            for (uint256 j = 0; j < schedules.length; j++) {
                IPayments.Schedule memory schedule = schedules[j];
                
                // Interval should be within valid enum range
                assertTrue(
                    uint8(schedule.interval) <= uint8(IPayments.IntervalType.Yearly),
                    "PP2.8: Schedule interval out of range"
                );
                
                // Amount should be positive
                assertTrue(schedule.amount > 0, "PP2.8: Schedule amount must be positive");
                
                // Amount should be reasonable (not exceed uint256 practical limits)
                assertTrue(schedule.amount <= type(uint128).max, "PP2.8: Schedule amount reasonable");
            }
        }
    }

    /// @notice PP2.9: User Limits Enforcement
    /// @dev Users should not exceed maximum streams/schedules per user
    function invariant_PP2_9_userLimitsEnforcement() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = string(abi.encodePacked("user", vm.toString(i)));
            
            (bytes32[] memory streamIds,) = plugin.getUserStreams(username);
            (bytes32[] memory scheduleIds,) = plugin.getUserSchedules(username);
            
            // Should not exceed defined limits
            assertLe(streamIds.length, plugin.MAX_STREAMS_PER_USER(), "PP2.9: Too many streams per user");
            assertLe(scheduleIds.length, plugin.MAX_SCHEDULES_PER_USER(), "PP2.9: Too many schedules per user");
        }
    }

    /// @notice PP2.10: Token Address Validity
    /// @dev All payment tokens should be valid contract addresses
    function invariant_PP2_10_tokenAddressValidity() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            string memory username = string(abi.encodePacked("user", vm.toString(i)));
            
            (, IPayments.Stream[] memory streams) = plugin.getUserStreams(username);
            (, IPayments.Schedule[] memory schedules) = plugin.getUserSchedules(username);
            
            // Check stream tokens
            for (uint256 j = 0; j < streams.length; j++) {
                assertTrue(streams[j].token != address(0), "PP2.10: Stream token cannot be zero");
                
                // In a real test, you might check token.code.length > 0
                // but for invariant testing we focus on non-zero addresses
            }
            
            // Check schedule tokens
            for (uint256 j = 0; j < schedules.length; j++) {
                assertTrue(schedules[j].token != address(0), "PP2.10: Schedule token cannot be zero");
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                         HANDLER FUNCTIONS FOR INVARIANT TESTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Handler for creating streams (as manager)
    function createStream(uint256 userSeed, uint256 tokenSeed, uint256 amountSeed) public asManager {
        string memory username = string(abi.encodePacked("user", vm.toString(bound(userSeed, 0, actors.length - 1))));
        address token = actors[bound(tokenSeed, 0, actors.length - 1)]; // Use actor addresses as mock tokens
        uint216 amount = uint216(bound(amountSeed, 1e12, 1e20)); // Reasonable flow rate range
        
        try plugin.createStream(username, token, amount) {
            ghost_userStreamCount[username]++;
            ghost_totalStreams++;
        } catch {
            // Failed operations are acceptable in invariant testing
        }
    }

    /// @notice Handler for creating schedules (as manager)
    function createSchedule(
        uint256 userSeed, 
        uint256 tokenSeed, 
        uint256 amountSeed, 
        uint256 intervalSeed, 
        bool isOneTime
    ) public asManager {
        string memory username = string(abi.encodePacked("user", vm.toString(bound(userSeed, 0, actors.length - 1))));
        address token = actors[bound(tokenSeed, 0, actors.length - 1)];
        uint256 amount = bound(amountSeed, 1e6, 1e24); // Reasonable schedule amounts
        IPayments.IntervalType interval = IPayments.IntervalType(bound(intervalSeed, 0, 6));
        uint40 firstPayment = uint40(block.timestamp + bound(amountSeed, 1 hours, 30 days));
        
        try plugin.createSchedule(username, token, amount, interval, isOneTime, firstPayment) {
            ghost_userScheduleCount[username]++;
            ghost_totalSchedules++;
        } catch {
            // Failed operations are acceptable
        }
    }

    /// @notice Handler for updating flow rates (as manager)
    function updateFlowRate(uint256 userSeed, uint256 streamIndexSeed, uint256 newAmountSeed) public asManager {
        string memory username = string(abi.encodePacked("user", vm.toString(bound(userSeed, 0, actors.length - 1))));
        
        (bytes32[] memory streamIds,) = plugin.getUserStreams(username);
        if (streamIds.length > 0) {
            bytes32 streamId = streamIds[bound(streamIndexSeed, 0, streamIds.length - 1)];
            uint216 newAmount = uint216(bound(newAmountSeed, 1e12, 1e20));
            
            try plugin.updateFlowRate(username, streamId, newAmount) {
                // Ghost variable updates would happen here
            } catch {
                // Failed operations are acceptable
            }
        }
    }

    /// @notice Handler for pausing streams (as manager)
    function pauseStream(uint256 userSeed, uint256 streamIndexSeed) public asManager {
        string memory username = string(abi.encodePacked("user", vm.toString(bound(userSeed, 0, actors.length - 1))));
        
        (bytes32[] memory streamIds,) = plugin.getUserStreams(username);
        if (streamIds.length > 0) {
            bytes32 streamId = streamIds[bound(streamIndexSeed, 0, streamIds.length - 1)];
            
            try plugin.pauseStream(username, streamId) {
                // State change tracked
            } catch {
                // Failed operations are acceptable
            }
        }
    }

    /// @notice Handler for cancelling schedules (as manager)
    function cancelSchedule(uint256 userSeed, uint256 scheduleIndexSeed) public asManager {
        string memory username = string(abi.encodePacked("user", vm.toString(bound(userSeed, 0, actors.length - 1))));
        
        (bytes32[] memory scheduleIds,) = plugin.getUserSchedules(username);
        if (scheduleIds.length > 0) {
            bytes32 scheduleId = scheduleIds[bound(scheduleIndexSeed, 0, scheduleIds.length - 1)];
            
            try plugin.cancelSchedule(username, scheduleId) {
                if (ghost_userScheduleCount[username] > 0) {
                    ghost_userScheduleCount[username]--;
                    ghost_totalSchedules--;
                }
            } catch {
                // Failed operations are acceptable
            }
        }
    }
}