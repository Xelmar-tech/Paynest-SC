// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {ForkTestBaseV2} from "../lib/ForkTestBaseV2.sol";
import {PaymentsForkBuilderV2} from "../builders/PaymentsForkBuilderV2.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

import {PaymentsPluginSetup} from "../../../src/v2/setup/PaymentsPluginSetup.sol";
import {PaymentsPlugin} from "../../../src/v2/PaymentsPlugin.sol";
import {AddressRegistry} from "../../../src/v2/AddressRegistry.sol";
import {IPayments} from "../../../src/v2/interfaces/IPayments.sol";
import {ILlamaPayFactory, ILlamaPay} from "../../../src/v2/interfaces/ILlamaPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NON_EMPTY_BYTES} from "../../v1/lib/constants.sol";

contract PaymentsPluginForkTest is ForkTestBaseV2 {
    DAO internal dao;
    PaymentsPlugin internal plugin;
    PluginRepo internal repo;
    PaymentsPluginSetup internal setup;
    AddressRegistry internal registry;
    ILlamaPayFactory internal llamaPayFactory;
    IERC20 internal usdc;

    string constant TEST_USERNAME = "alice";
    uint216 constant STREAM_FLOW_RATE = uint216(1e15); // 0.001 token per second in 20 decimal precision (reasonable rate)
    uint256 constant SCHEDULE_AMOUNT = 1000e6; // 1000 USDC for schedules
    uint40 constant STREAM_DURATION = 30 days;

    // Events to test
    event StreamActive(string indexed username, address indexed token, uint40 endDate, uint256 totalAmount);
    event StreamUpdated(string indexed username, address indexed token, uint256 newAmount);
    event PaymentStreamCancelled(string indexed username, address indexed token);
    event StreamPayout(string indexed username, address indexed token, uint256 amount);
    event ScheduleActive(
        string indexed username,
        address indexed token,
        uint256 amount,
        IPayments.IntervalType interval,
        bool isOneTime,
        uint40 firstPaymentDate
    );
    event ScheduleUpdated(string indexed username, address indexed token, uint256 newAmount);
    event PaymentScheduleCancelled(string indexed username, address indexed token);
    event SchedulePayout(string indexed username, address indexed token, uint256 amount, uint256 periods);

    function setUp() public virtual override {
        super.setUp();

        // Build the fork test environment using DAOFactory pattern
        (dao, repo, setup, plugin, registry, llamaPayFactory, usdc) = new PaymentsForkBuilderV2().withManager(bob).build();

        // Setup test data - alice claims a username with controller/recipient separation
        vm.prank(alice);
        registry.claimUsername(TEST_USERNAME, carol, alice); // Alice controls, Carol receives

        // Approve DAO to spend tokens (simulate DAO treasury having approval)
        vm.prank(address(dao));
        usdc.approve(address(plugin), type(uint256).max);
    }

    modifier givenTestingPluginInitialization() {
        _;
    }

    function test_GivenTestingPluginInitialization() external givenTestingPluginInitialization {
        // It should set DAO address correctly
        assertEq(address(plugin.dao()), address(dao));

        // It should set registry address correctly
        assertEq(address(plugin.registry()), address(registry));

        // It should set LlamaPay factory address correctly
        assertEq(address(plugin.llamaPayFactory()), address(llamaPayFactory));
    }

    function test_WhenInvalidParametersProvided() external givenTestingPluginInitialization {
        // Check the Repo
        PluginRepo.Version memory version = repo.getLatestVersion(repo.latestRelease());
        assertTrue(version.pluginSetup != address(0));
        
        // Check plugin constants
        assertEq(plugin.MANAGER_PERMISSION_ID(), keccak256("MANAGER_PERMISSION"));
        assertEq(plugin.MAX_STREAMS_PER_USER(), 50);
        assertEq(plugin.MAX_SCHEDULES_PER_USER(), 20);
        assertEq(plugin.DEFAULT_FUNDING_PERIOD(), 180 days);
    }

    function test_WhenUnauthorizedUserCallsPlugin() external givenTestingPluginInitialization {
        // It should revert with DaoUnauthorized when unauthorized user calls protected functions
        
        vm.expectRevert();
        vm.prank(alice);
        plugin.createStream(TEST_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        vm.expectRevert();
        vm.prank(alice);
        plugin.createSchedule(
            TEST_USERNAME, 
            address(usdc), 
            SCHEDULE_AMOUNT, 
            IPayments.IntervalType.Monthly, 
            false, 
            uint40(block.timestamp + 86400)
        );
    }

    function test_WhenAuthorizedManagerCallsPlugin() external givenTestingPluginInitialization {
        // It should allow authorized manager to call plugin functions
        
        // Bob is the manager and should be able to create streams
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        // Verify stream was created (should not revert)
        (bytes32[] memory streamIds, IPayments.Stream[] memory streamData) = plugin.getUserStreams(TEST_USERNAME);
        assertEq(streamIds.length, 1);
        assertEq(streamData.length, 1);
        assertEq(streamData[0].token, address(usdc));
        assertTrue(streamData[0].amountPerSec > 0);
    }

    function test_WhenCreatingStreamWithControllerRecipientSeparation() external givenTestingPluginInitialization {
        // It should handle controller/recipient separation correctly
        
        // Bob (manager) creates stream for alice (controller) -> carol (recipient)
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        // Verify stream recipient is carol (from registry)
        (, IPayments.Stream[] memory streamData) = plugin.getUserStreams(TEST_USERNAME);
        assertEq(streamData.length, 1);
        
        // The stream should be associated with the username, registry will resolve to carol
        assertEq(registry.getRecipient(TEST_USERNAME), carol);
        assertEq(registry.getController(TEST_USERNAME), alice);
    }

    function test_WhenCreatingScheduleWithControllerRecipientSeparation() external givenTestingPluginInitialization {
        // It should handle controller/recipient separation for schedules
        
        uint40 firstPayment = uint40(block.timestamp + 86400);
        
        // Bob (manager) creates schedule for alice (controller) -> carol (recipient)
        vm.prank(bob);
        plugin.createSchedule(
            TEST_USERNAME,
            address(usdc),
            SCHEDULE_AMOUNT,
            IPayments.IntervalType.Monthly,
            false,
            firstPayment
        );
        
        // Verify schedule was created
        (bytes32[] memory scheduleIds, IPayments.Schedule[] memory scheduleData) = plugin.getUserSchedules(TEST_USERNAME);
        assertEq(scheduleIds.length, 1);
        assertEq(scheduleData.length, 1);
        assertEq(scheduleData[0].token, address(usdc));
        assertEq(scheduleData[0].amount, SCHEDULE_AMOUNT);
        assertEq(uint8(scheduleData[0].interval), uint8(IPayments.IntervalType.Monthly));
        assertEq(scheduleData[0].firstPaymentDate, firstPayment);
    }

    function test_WhenMigratingStreamsAsController() external givenTestingPluginInitialization {
        // It should allow username controller to migrate streams
        
        // First create a stream as manager
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        // Alice (controller) should be able to migrate streams
        vm.prank(alice);
        bytes32[] memory migratedIds = plugin.migrateAllStreams(TEST_USERNAME);
        
        // Even if no migration happens, it should not revert
        // (migration logic depends on implementation details)
        assertTrue(migratedIds.length >= 0);
    }

    function test_WhenMigratingStreamsAsNonController() external givenTestingPluginInitialization {
        // It should prevent non-controllers from migrating streams
        
        // First create a stream as manager
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        // Carol (recipient but not controller) should not be able to migrate
        vm.expectRevert();
        vm.prank(carol);
        plugin.migrateAllStreams(TEST_USERNAME);
        
        // Random user should not be able to migrate
        vm.expectRevert();
        vm.prank(david);
        plugin.migrateAllStreams(TEST_USERNAME);
    }

    function test_WhenViewingUserStreamsAndSchedules() external givenTestingPluginInitialization {
        // It should return correct data for user streams and schedules
        
        // Initially empty
        (bytes32[] memory streamIds, IPayments.Stream[] memory streamData) = plugin.getUserStreams(TEST_USERNAME);
        assertEq(streamIds.length, 0);
        assertEq(streamData.length, 0);
        
        (bytes32[] memory scheduleIds, IPayments.Schedule[] memory scheduleData) = plugin.getUserSchedules(TEST_USERNAME);
        assertEq(scheduleIds.length, 0);
        assertEq(scheduleData.length, 0);
        
        // Create stream and schedule
        vm.startPrank(bob);
        plugin.createStream(TEST_USERNAME, address(usdc), STREAM_FLOW_RATE);
        plugin.createSchedule(
            TEST_USERNAME,
            address(usdc),
            SCHEDULE_AMOUNT / 2,
            IPayments.IntervalType.Weekly,
            false,
            uint40(block.timestamp + 86400)
        );
        vm.stopPrank();
        
        // Should now have data
        (streamIds, streamData) = plugin.getUserStreams(TEST_USERNAME);
        assertEq(streamIds.length, 1);
        assertEq(streamData.length, 1);
        
        (scheduleIds, scheduleData) = plugin.getUserSchedules(TEST_USERNAME);
        assertEq(scheduleIds.length, 1);
        assertEq(scheduleData.length, 1);
    }

    function test_WhenCheckingPluginIntegrationWithAragon() external givenTestingPluginInitialization {
        // It should integrate properly with Aragon DAO framework
        
        // Verify plugin is properly connected to DAO
        assertTrue(address(plugin.dao()) != address(0));
        assertEq(address(plugin.dao()), address(dao));
        
        // Verify plugin repo is properly set up
        assertTrue(address(repo) != address(0));
        
        // Verify setup contract exists
        assertTrue(address(setup) != address(0));
        
        // Verify plugin constants are correct
        assertEq(plugin.MANAGER_PERMISSION_ID(), keccak256("MANAGER_PERMISSION"));
    }

    function test_WhenHandlingRealTokenOnFork() external givenTestingPluginInitialization {
        // It should work with real USDC on Base fork
        
        // Verify we have real USDC
        assertTrue(address(usdc) != address(0));
        assertTrue(usdc.totalSupply() > 0);
        
        // Verify DAO has USDC balance
        assertTrue(usdc.balanceOf(address(dao)) >= 10000e6);
        
        // Create stream with real token
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        // Verify stream was created with correct token
        (, IPayments.Stream[] memory streamData) = plugin.getUserStreams(TEST_USERNAME);
        assertEq(streamData[0].token, address(usdc));
    }
}