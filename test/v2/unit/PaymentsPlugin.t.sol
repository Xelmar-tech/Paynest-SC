// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DAO, Action} from "@aragon/osx/core/dao/DAO.sol";
import {PaymentsPlugin} from "../../../src/v2/PaymentsPlugin.sol";
import {AddressRegistry} from "../../../src/v2/AddressRegistry.sol";
import {IPayments} from "../../../src/v2/interfaces/IPayments.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PaymentsPluginV2Test is Test {
    PaymentsPlugin public pluginImplementation;
    PaymentsPlugin public plugin;
    AddressRegistry public registry;

    address public constant DAO_ADDRESS = address(0x1);
    address public constant REGISTRY_ADDRESS = address(0x2);
    address public constant LLAMAPAY_FACTORY = address(0x3);
    address public constant ALICE = address(0xa);
    address public constant BOB = address(0xb);

    function setUp() public {
        registry = new AddressRegistry();
        pluginImplementation = new PaymentsPlugin();

        // Create proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            PaymentsPlugin.initialize.selector, DAO(payable(DAO_ADDRESS)), address(registry), LLAMAPAY_FACTORY
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(pluginImplementation), initData);
        plugin = PaymentsPlugin(address(proxy));
    }

    // Constructor Tests

    function test_constructor_ShouldDisableInitializers() public {
        // Try to initialize the implementation contract (should fail)
        vm.expectRevert();
        pluginImplementation.initialize(DAO(payable(DAO_ADDRESS)), REGISTRY_ADDRESS, LLAMAPAY_FACTORY);
    }

    // Constants Tests

    function test_constants_ShouldHaveCorrectValues() public view {
        assertEq(plugin.MANAGER_PERMISSION_ID(), keccak256("MANAGER_PERMISSION"));
        assertEq(plugin.MAX_STREAMS_PER_USER(), 50);
        assertEq(plugin.MAX_SCHEDULES_PER_USER(), 20);
        assertEq(plugin.DEFAULT_FUNDING_PERIOD(), 180 days);
    }

    // Initialization Tests

    function test_initialize_ValidParameters_ShouldInitializeCorrectly() public view {
        assertEq(address(plugin.dao()), DAO_ADDRESS);
        assertEq(address(plugin.registry()), address(registry));
        assertEq(address(plugin.llamaPayFactory()), LLAMAPAY_FACTORY);
    }

    function test_initialize_ZeroRegistry_ShouldRevert() public {
        PaymentsPlugin newImplementation = new PaymentsPlugin();

        bytes memory initData = abi.encodeWithSelector(
            PaymentsPlugin.initialize.selector, DAO(payable(DAO_ADDRESS)), address(0), LLAMAPAY_FACTORY
        );

        vm.expectRevert();
        new ERC1967Proxy(address(newImplementation), initData);
    }

    function test_initialize_ZeroLlamaPayFactory_ShouldRevert() public {
        PaymentsPlugin newImplementation = new PaymentsPlugin();

        bytes memory initData = abi.encodeWithSelector(
            PaymentsPlugin.initialize.selector, DAO(payable(DAO_ADDRESS)), address(registry), address(0)
        );

        vm.expectRevert();
        new ERC1967Proxy(address(newImplementation), initData);
    }

    function test_initialize_AlreadyInitialized_ShouldRevert() public {
        vm.expectRevert();
        plugin.initialize(DAO(payable(DAO_ADDRESS)), address(registry), LLAMAPAY_FACTORY);
    }

    // View Function Tests (Without Authorization Required)

    function test_getUserStreams_EmptyUser_ShouldReturnEmptyArrays() public view {
        (bytes32[] memory streamIds, IPayments.Stream[] memory streamData) = plugin.getUserStreams("alice");
        assertEq(streamIds.length, 0);
        assertEq(streamData.length, 0);
    }

    function test_getUserSchedules_EmptyUser_ShouldReturnEmptyArrays() public view {
        (bytes32[] memory scheduleIds, IPayments.Schedule[] memory scheduleData) = plugin.getUserSchedules("alice");
        assertEq(scheduleIds.length, 0);
        assertEq(scheduleData.length, 0);
    }

    function test_getStream_NonExistentStream_ShouldRevert() public {
        bytes32 streamId = keccak256("nonexistent");

        vm.expectRevert(PaymentsPlugin.StreamIdNotFound.selector);
        plugin.getStream("alice", streamId);
    }

    function test_getSchedule_NonExistentSchedule_ShouldRevert() public {
        bytes32 scheduleId = keccak256("nonexistent");

        vm.expectRevert(PaymentsPlugin.ScheduleIdNotFound.selector);
        plugin.getSchedule("alice", scheduleId);
    }

    // Authorization Tests (Should Fail Without Proper Permission)

    function test_createStream_UnauthorizedCaller_ShouldRevert() public {
        // Should revert due to lack of MANAGER_PERMISSION_ID
        vm.expectRevert();
        plugin.createStream("alice", address(0x123), 1e18);
    }

    function test_updateFlowRate_UnauthorizedCaller_ShouldRevert() public {
        bytes32 streamId = keccak256("test");

        vm.expectRevert();
        plugin.updateFlowRate("alice", streamId, 2e18);
    }

    function test_pauseStream_UnauthorizedCaller_ShouldRevert() public {
        bytes32 streamId = keccak256("test");

        vm.expectRevert();
        plugin.pauseStream("alice", streamId);
    }

    function test_resumeStream_UnauthorizedCaller_ShouldRevert() public {
        bytes32 streamId = keccak256("test");

        vm.expectRevert();
        plugin.resumeStream("alice", streamId);
    }

    function test_cancelStream_UnauthorizedCaller_ShouldRevert() public {
        bytes32 streamId = keccak256("test");

        vm.expectRevert();
        plugin.cancelStream("alice", streamId);
    }

    function test_createSchedule_UnauthorizedCaller_ShouldRevert() public {
        vm.expectRevert();
        plugin.createSchedule(
            "alice", address(0x123), 1e18, IPayments.IntervalType.Daily, false, uint40(block.timestamp + 86400)
        );
    }

    function test_updateScheduleAmount_UnauthorizedCaller_ShouldRevert() public {
        bytes32 scheduleId = keccak256("test");

        vm.expectRevert();
        plugin.updateScheduleAmount("alice", scheduleId, 2e18);
    }

    function test_updateScheduleInterval_UnauthorizedCaller_ShouldRevert() public {
        bytes32 scheduleId = keccak256("test");

        vm.expectRevert();
        plugin.updateScheduleInterval("alice", scheduleId, IPayments.IntervalType.Weekly);
    }

    function test_cancelSchedule_UnauthorizedCaller_ShouldRevert() public {
        bytes32 scheduleId = keccak256("test");

        vm.expectRevert();
        plugin.cancelSchedule("alice", scheduleId);
    }

    function test_executeSchedule_UnauthorizedCaller_ShouldRevert() public {
        bytes32 scheduleId = keccak256("test");

        vm.expectRevert();
        plugin.executeSchedule("alice", scheduleId);
    }

    // Migration Function Tests (Should Work for Username Controllers)

    function test_migrateStream_NonExistentStream_ShouldRevert() public {
        // Register alice in registry
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE, ALICE);

        bytes32 streamId = keccak256("nonexistent");

        vm.expectRevert(PaymentsPlugin.StreamIdNotFound.selector);
        vm.prank(ALICE);
        plugin.migrateStream("alice", streamId);
    }

    function test_migrateAllStreams_EmptyUser_ShouldReturnEmptyArray() public {
        // Register alice in registry
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE, ALICE);

        vm.prank(ALICE);
        bytes32[] memory migratedIds = plugin.migrateAllStreams("alice");
        assertEq(migratedIds.length, 0);
    }

    function test_migrateSelectedStreams_EmptyArray_ShouldReturnEmptyArray() public {
        // Register alice in registry
        vm.prank(ALICE);
        registry.claimUsername("alice", ALICE, ALICE);

        bytes32[] memory streamIds = new bytes32[](0);

        vm.prank(ALICE);
        bytes32[] memory migratedIds = plugin.migrateSelectedStreams("alice", streamIds);
        assertEq(migratedIds.length, 0);
    }

    // Permission ID Test

    function test_MANAGER_PERMISSION_ID_ShouldBeConsistent() public view {
        bytes32 expectedId = keccak256("MANAGER_PERMISSION");
        assertEq(plugin.MANAGER_PERMISSION_ID(), expectedId);
    }

    // Storage Gap Test (Edge Case)

    function test_storageLayout_ShouldNotHaveStorageConflicts() public view {
        // This test ensures that the storage layout is properly set up
        // by checking that initialization worked properly

        // Verify state is properly set in our proxy
        assertEq(address(plugin.registry()), address(registry));
        assertEq(address(plugin.llamaPayFactory()), LLAMAPAY_FACTORY);
    }
}
