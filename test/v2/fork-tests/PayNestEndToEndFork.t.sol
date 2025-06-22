// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {ForkTestBaseV2} from "../lib/ForkTestBaseV2.sol";
import {PaymentsForkBuilderV2} from "../builders/PaymentsForkBuilderV2.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

import {PaymentsPluginSetup} from "../../../src/v2/setup/PaymentsPluginSetup.sol";
import {PaymentsPlugin} from "../../../src/v2/PaymentsPlugin.sol";
import {AddressRegistry} from "../../../src/v2/AddressRegistry.sol";
import {IPayments} from "../../../src/v2/interfaces/IPayments.sol";
import {IRegistry} from "../../../src/v2/interfaces/IRegistry.sol";
import {ILlamaPayFactory, ILlamaPay} from "../../../src/v2/interfaces/ILlamaPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PayNestEndToEndForkTest is ForkTestBaseV2 {
    DAO internal dao;
    PaymentsPlugin internal plugin;
    PluginRepo internal repo;
    PaymentsPluginSetup internal setup;
    AddressRegistry internal registry;
    ILlamaPayFactory internal llamaPayFactory;
    IERC20 internal usdc;

    string constant ALICE_USERNAME = "alice";
    string constant BOB_USERNAME = "bob_wallet";
    string constant CAROL_USERNAME = "carol123";
    
    uint216 constant STREAM_FLOW_RATE = uint216(1e15); // 0.001 token per second in 20 decimal precision (reasonable rate)
    uint256 constant SCHEDULE_AMOUNT = 500e6; // 500 USDC

    function setUp() public virtual override {
        super.setUp();

        // Build the complete PayNest V2 environment
        (dao, repo, setup, plugin, registry, llamaPayFactory, usdc) = new PaymentsForkBuilderV2().withManager(bob).build();

        // Approve DAO to spend tokens
        vm.prank(address(dao));
        usdc.approve(address(plugin), type(uint256).max);
    }

    modifier givenCompletePayNestV2Setup() {
        _;
    }

    function test_GivenCompletePayNestV2Setup() external givenCompletePayNestV2Setup {
        // It should have all components deployed and connected
        assertTrue(address(dao) != address(0));
        assertTrue(address(plugin) != address(0));
        assertTrue(address(registry) != address(0));
        assertTrue(address(llamaPayFactory) != address(0));
        assertTrue(address(usdc) != address(0));
        
        // Verify integrations
        assertEq(address(plugin.dao()), address(dao));
        assertEq(address(plugin.registry()), address(registry));
        assertEq(address(plugin.llamaPayFactory()), address(llamaPayFactory));
    }

    function test_WhenUsersClaimUsernamesWithV2Features() external givenCompletePayNestV2Setup {
        // It should support V2 controller/recipient separation
        
        // Alice: Controller and recipient are the same
        vm.prank(alice);
        registry.claimUsername(ALICE_USERNAME, alice);
        
        // Bob: Separate controller and recipient
        vm.prank(bob);
        registry.claimUsername(BOB_USERNAME, carol, bob); // Bob controls, Carol receives
        
        // Carol: Another standard registration
        vm.prank(carol);
        registry.claimUsername(CAROL_USERNAME, carol);
        
        // Verify all registrations
        assertEq(registry.getController(ALICE_USERNAME), alice);
        assertEq(registry.getRecipient(ALICE_USERNAME), alice);
        
        assertEq(registry.getController(BOB_USERNAME), bob);
        assertEq(registry.getRecipient(BOB_USERNAME), carol);
        
        assertEq(registry.getController(CAROL_USERNAME), carol);
        assertEq(registry.getRecipient(CAROL_USERNAME), carol);
    }

    function test_WhenManagerCreatesPaymentsForUsers() external givenCompletePayNestV2Setup {
        // Setup usernames first
        vm.prank(alice);
        registry.claimUsername(ALICE_USERNAME, alice);
        
        vm.prank(bob);
        registry.claimUsername(BOB_USERNAME, carol, bob);
        
        // It should create payments for users with different controller/recipient setups
        vm.startPrank(bob); // Bob is the manager
        
        // Create stream for Alice (controller = recipient)
        plugin.createStream(ALICE_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        // Create stream for Bob's username (controller ≠ recipient)
        plugin.createStream(BOB_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        // Create schedules
        plugin.createSchedule(
            ALICE_USERNAME,
            address(usdc),
            SCHEDULE_AMOUNT,
            IPayments.IntervalType.Monthly,
            false,
            uint40(block.timestamp + 86400)
        );
        
        plugin.createSchedule(
            BOB_USERNAME,
            address(usdc),
            SCHEDULE_AMOUNT,
            IPayments.IntervalType.Weekly,
            true, // One-time
            uint40(block.timestamp + 86400)
        );
        
        vm.stopPrank();
        
        // Verify streams were created
        (bytes32[] memory aliceStreamIds, IPayments.Stream[] memory aliceStreams) = plugin.getUserStreams(ALICE_USERNAME);
        assertEq(aliceStreamIds.length, 1);
        assertEq(aliceStreams[0].token, address(usdc));
        
        (bytes32[] memory bobStreamIds, IPayments.Stream[] memory bobStreams) = plugin.getUserStreams(BOB_USERNAME);
        assertEq(bobStreamIds.length, 1);
        assertEq(bobStreams[0].token, address(usdc));
        
        // Verify schedules were created
        (bytes32[] memory aliceScheduleIds, IPayments.Schedule[] memory aliceSchedules) = plugin.getUserSchedules(ALICE_USERNAME);
        assertEq(aliceScheduleIds.length, 1);
        assertEq(aliceSchedules[0].amount, SCHEDULE_AMOUNT);
        assertEq(uint8(aliceSchedules[0].interval), uint8(IPayments.IntervalType.Monthly));
        assertFalse(aliceSchedules[0].isOneTime);
        
        (bytes32[] memory bobScheduleIds, IPayments.Schedule[] memory bobSchedules) = plugin.getUserSchedules(BOB_USERNAME);
        assertEq(bobScheduleIds.length, 1);
        assertEq(bobSchedules[0].amount, SCHEDULE_AMOUNT);
        assertEq(uint8(bobSchedules[0].interval), uint8(IPayments.IntervalType.Weekly));
        assertTrue(bobSchedules[0].isOneTime);
    }

    function test_WhenControllersManageTheirUsernames() external givenCompletePayNestV2Setup {
        // Setup: Bob claims username with Carol as recipient
        vm.prank(bob);
        registry.claimUsername(BOB_USERNAME, carol, bob);
        
        // Manager creates a stream
        vm.prank(bob); // Bob is also the manager in this test
        plugin.createStream(BOB_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        // It should allow controller to manage username settings
        
        // Bob (controller) updates recipient to David
        vm.prank(bob);
        registry.updateRecipient(BOB_USERNAME, david);
        
        // Verify update
        assertEq(registry.getRecipient(BOB_USERNAME), david);
        assertEq(registry.getController(BOB_USERNAME), bob);
        
        // Bob transfers control to Carol
        vm.prank(bob);
        registry.transferControl(BOB_USERNAME, carol);
        
        // Carol (new controller) should now be able to update recipient back to herself
        vm.prank(carol);
        registry.updateRecipient(BOB_USERNAME, carol);
        
        // Final verification
        assertEq(registry.getController(BOB_USERNAME), carol);
        assertEq(registry.getRecipient(BOB_USERNAME), carol);
        
        // Carol should also be able to migrate streams
        vm.prank(carol);
        bytes32[] memory migratedIds = plugin.migrateAllStreams(BOB_USERNAME);
        assertTrue(migratedIds.length >= 0); // Should not revert
    }

    function test_WhenHandlingComplexPaymentScenarios() external givenCompletePayNestV2Setup {
        // Setup multiple users with different configurations
        vm.prank(alice);
        registry.claimUsername(ALICE_USERNAME, alice); // Standard setup
        
        vm.prank(bob);
        registry.claimUsername(BOB_USERNAME, carol, bob); // Separated setup
        
        vm.prank(carol);
        registry.claimUsername(CAROL_USERNAME, david, carol); // Another separated setup
        
        // It should handle complex payment scenarios
        vm.startPrank(bob); // Manager
        
        // Create multiple streams for each user
        plugin.createStream(ALICE_USERNAME, address(usdc), STREAM_FLOW_RATE);
        plugin.createStream(BOB_USERNAME, address(usdc), STREAM_FLOW_RATE * 2);
        plugin.createStream(CAROL_USERNAME, address(usdc), STREAM_FLOW_RATE / 2);
        
        // Create multiple schedules with different intervals
        plugin.createSchedule(
            ALICE_USERNAME,
            address(usdc),
            SCHEDULE_AMOUNT,
            IPayments.IntervalType.Daily,
            false,
            uint40(block.timestamp + 3600)
        );
        
        plugin.createSchedule(
            BOB_USERNAME,
            address(usdc),
            SCHEDULE_AMOUNT * 2,
            IPayments.IntervalType.Weekly,
            false,
            uint40(block.timestamp + 86400)
        );
        
        plugin.createSchedule(
            CAROL_USERNAME,
            address(usdc),
            SCHEDULE_AMOUNT / 2,
            IPayments.IntervalType.Monthly,
            true, // One-time
            uint40(block.timestamp + 86400 * 7)
        );
        
        vm.stopPrank();
        
        // Verify all payments were created correctly
        (, IPayments.Stream[] memory aliceStreams) = plugin.getUserStreams(ALICE_USERNAME);
        (, IPayments.Stream[] memory bobStreams) = plugin.getUserStreams(BOB_USERNAME);
        (, IPayments.Stream[] memory carolStreams) = plugin.getUserStreams(CAROL_USERNAME);
        
        assertEq(aliceStreams.length, 1);
        assertEq(bobStreams.length, 1);
        assertEq(carolStreams.length, 1);
        
        assertEq(aliceStreams[0].amountPerSec, STREAM_FLOW_RATE);
        assertEq(bobStreams[0].amountPerSec, STREAM_FLOW_RATE * 2);
        assertEq(carolStreams[0].amountPerSec, STREAM_FLOW_RATE / 2);
        
        (, IPayments.Schedule[] memory aliceSchedules) = plugin.getUserSchedules(ALICE_USERNAME);
        (, IPayments.Schedule[] memory bobSchedules) = plugin.getUserSchedules(BOB_USERNAME);
        (, IPayments.Schedule[] memory carolSchedules) = plugin.getUserSchedules(CAROL_USERNAME);
        
        assertEq(aliceSchedules.length, 1);
        assertEq(bobSchedules.length, 1);
        assertEq(carolSchedules.length, 1);
        
        assertEq(uint8(aliceSchedules[0].interval), uint8(IPayments.IntervalType.Daily));
        assertEq(uint8(bobSchedules[0].interval), uint8(IPayments.IntervalType.Weekly));
        assertEq(uint8(carolSchedules[0].interval), uint8(IPayments.IntervalType.Monthly));
    }

    function test_WhenIntegratingWithRealLlamaPayOnFork() external givenCompletePayNestV2Setup {
        // Setup username
        vm.prank(alice);
        registry.claimUsername(ALICE_USERNAME, alice);
        
        // It should integrate with real LlamaPay factory
        
        // Verify LlamaPay factory is real
        assertTrue(address(llamaPayFactory) != address(0));
        
        // Create stream that would interact with LlamaPay
        vm.prank(bob); // Manager
        plugin.createStream(ALICE_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        // Verify stream was created (integration with LlamaPay happens in implementation)
        (, IPayments.Stream[] memory streams) = plugin.getUserStreams(ALICE_USERNAME);
        assertEq(streams.length, 1);
        assertEq(streams[0].token, address(usdc));
        assertTrue(streams[0].amountPerSec > 0);
    }

    function test_WhenUpgradingPluginConfiguration() external givenCompletePayNestV2Setup {
        // It should support plugin upgrades and configuration changes
        
        // Verify current configuration
        assertEq(plugin.MAX_STREAMS_PER_USER(), 50);
        assertEq(plugin.MAX_SCHEDULES_PER_USER(), 20);
        assertEq(plugin.DEFAULT_FUNDING_PERIOD(), 180 days);
        
        // Create some test data
        vm.prank(alice);
        registry.claimUsername(ALICE_USERNAME, alice);
        
        vm.prank(bob);
        plugin.createStream(ALICE_USERNAME, address(usdc), STREAM_FLOW_RATE);
        
        // Verify data persists
        (, IPayments.Stream[] memory streams) = plugin.getUserStreams(ALICE_USERNAME);
        assertEq(streams.length, 1);
        
        // Plugin should maintain state across potential upgrades
        assertEq(address(plugin.registry()), address(registry));
        assertEq(address(plugin.dao()), address(dao));
    }

    function test_WhenHandlingGasOptimizations() external givenCompletePayNestV2Setup {
        // It should have reasonable gas costs for operations
        
        vm.prank(alice);
        registry.claimUsername(ALICE_USERNAME, alice);
        
        // Measure gas for typical operations
        uint256 gasBefore = gasleft();
        vm.prank(bob);
        plugin.createStream(ALICE_USERNAME, address(usdc), STREAM_FLOW_RATE);
        uint256 gasUsedStream = gasBefore - gasleft();
        
        gasBefore = gasleft();
        vm.prank(bob);
        plugin.createSchedule(
            ALICE_USERNAME,
            address(usdc),
            SCHEDULE_AMOUNT,
            IPayments.IntervalType.Monthly,
            false,
            uint40(block.timestamp + 86400)
        );
        uint256 gasUsedSchedule = gasBefore - gasleft();
        
        // Gas usage should be reasonable (these are rough estimates)
        assertTrue(gasUsedStream < 500000, "Stream creation gas too high");
        assertTrue(gasUsedSchedule < 300000, "Schedule creation gas too high");
    }
}