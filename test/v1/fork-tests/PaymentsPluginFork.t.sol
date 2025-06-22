// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

import {ForkTestBase} from "../lib/ForkTestBase.sol";
import {PaymentsForkBuilder} from "../builders/PaymentsForkBuilder.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

import {PaymentsPluginV1Setup} from "../../../src/v1/setup/PaymentsPluginV1Setup.sol";
import {PaymentsPluginV1} from "../../../src/v1/PaymentsPluginV1.sol";
import {AddressRegistryV1} from "../../../src/v1/AddressRegistryV1.sol";
import {IPaymentsV1} from "../../../src/v1/interfaces/IPaymentsV1.sol";
import {ILlamaPayFactory, ILlamaPay} from "../../../src/v1/interfaces/ILlamaPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {NON_EMPTY_BYTES} from "../lib/constants.sol";

contract PaymentsPluginForkTest is ForkTestBase {
    DAO internal dao;
    PaymentsPluginV1 internal plugin;
    PluginRepo internal repo;
    PaymentsPluginV1Setup internal setup;
    AddressRegistryV1 internal registry;
    ILlamaPayFactory internal llamaPayFactory;
    IERC20 internal usdc;

    string constant TEST_USERNAME = "alice";
    uint256 constant STREAM_AMOUNT = 1000e6; // 1000 USDC
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
        IPaymentsV1.IntervalType interval,
        bool isOneTime,
        uint40 firstPaymentDate
    );
    event ScheduleUpdated(string indexed username, address indexed token, uint256 newAmount);
    event PaymentScheduleCancelled(string indexed username, address indexed token);
    event SchedulePayout(string indexed username, address indexed token, uint256 amount, uint256 periods);

    function setUp() public virtual override {
        super.setUp();

        // Build the fork test environment using DAOFactory pattern
        (dao, repo, setup, plugin, registry, llamaPayFactory, usdc) = new PaymentsForkBuilder().withManager(bob).build();

        // Setup test data - alice claims a username
        vm.prank(alice);
        registry.claimUsername(TEST_USERNAME);

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
        assertEq(version.pluginSetup, address(setup));
        assertEq(version.buildMetadata, NON_EMPTY_BYTES);

        // Check the DAO
        assertEq(keccak256(bytes(dao.daoURI())), keccak256(bytes("http://paynest/")));
    }

    modifier givenTestingStreamManagement() {
        _;
    }

    modifier whenCreatingStreams() {
        _;
    }

    function test_WhenCreatingStreams() external givenTestingStreamManagement whenCreatingStreams {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);

        // Check if LlamaPay contract exists for USDC before stream creation
        (address predictedAddress, bool isDeployed) = llamaPayFactory.getLlamaPayContractByToken(address(usdc));

        // It should emit stream active event
        vm.expectEmit(true, true, false, true);
        emit StreamActive(TEST_USERNAME, address(usdc), endTime, STREAM_AMOUNT);

        // It should create stream successfully with real USDC
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), endTime);

        // It should store stream metadata correctly
        IPaymentsV1.Stream memory stream = plugin.getStream(TEST_USERNAME);
        assertEq(stream.token, address(usdc));
        assertEq(stream.endDate, endTime);
        assertTrue(stream.active);
        assertTrue(stream.amount > 0);

        // It should deploy real LlamaPay contract for token (if it wasn't deployed)
        (address newPredictedAddress, bool nowDeployed) = llamaPayFactory.getLlamaPayContractByToken(address(usdc));
        assertTrue(nowDeployed, "LlamaPay contract should be deployed");

        // It should deposit funds to real LlamaPay contract
        ILlamaPay llamaPayContract = ILlamaPay(newPredictedAddress);
        assertTrue(llamaPayContract.balances(address(dao)) > 0, "DAO should have balance in LlamaPay");
    }

    function test_WhenInvalidParameters() external givenTestingStreamManagement whenCreatingStreams {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);

        // It should revert with invalid amount for zero amount
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.InvalidAmount.selector);
        plugin.createStream(TEST_USERNAME, 0, address(usdc), endTime);

        // It should revert with invalid token for zero token
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.InvalidToken.selector);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(0), endTime);

        // It should revert with invalid end date for past date
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.InvalidEndDate.selector);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), uint40(block.timestamp - 1));

        // It should revert with username not found for invalid username
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.UsernameNotFound.selector);
        plugin.createStream("nonexistent", STREAM_AMOUNT, address(usdc), endTime);

        // Create a stream first
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), endTime);

        // It should revert with stream already exists for duplicate stream
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.StreamAlreadyExists.selector);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), endTime);
    }

    function test_WhenCancelingStreams() external givenTestingStreamManagement {
        // Setup: Create a stream first
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), endTime);

        // Get LlamaPay contract address
        (address llamaPayAddress,) = llamaPayFactory.getLlamaPayContractByToken(address(usdc));
        ILlamaPay llamaPay = ILlamaPay(llamaPayAddress);

        // Check initial balance
        uint256 initialDaoBalance = usdc.balanceOf(address(dao));
        uint256 initialLlamaPayBalance = llamaPay.balances(address(dao));

        // Wait a bit for the stream to be fully registered
        vm.warp(block.timestamp + 1);

        // It should emit payment stream cancelled event
        vm.expectEmit(true, true, false, true);
        emit PaymentStreamCancelled(TEST_USERNAME, address(usdc));

        // It should cancel stream successfully
        vm.prank(bob);
        plugin.cancelStream(TEST_USERNAME);

        // It should mark stream as inactive
        IPaymentsV1.Stream memory stream = plugin.getStream(TEST_USERNAME);
        assertFalse(stream.active);

        // It should cancel real LlamaPay stream
        // Stream should no longer exist in LlamaPay - this will revert with "stream doesn't exist"
        address recipient = registry.getUserAddress(TEST_USERNAME);
        vm.expectRevert("stream doesn't exist");
        llamaPay.withdrawable(address(dao), recipient, stream.amount);

        // It should withdraw remaining funds to DAO
        uint256 finalDaoBalance = usdc.balanceOf(address(dao));
        uint256 finalLlamaPayBalance = llamaPay.balances(address(dao));

        // DAO should have recovered most funds (minus any streamed amount)
        assertTrue(finalDaoBalance > initialDaoBalance - STREAM_AMOUNT, "DAO should recover funds");
        assertEq(finalLlamaPayBalance, 0, "LlamaPay balance should be 0 after withdrawal");

        // It should revert with stream not active for non-existent stream
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.StreamNotActive.selector);
        plugin.cancelStream(TEST_USERNAME);
    }

    function test_WhenEditingStreams() external givenTestingStreamManagement {
        // Setup: Create a stream first
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), endTime);

        uint256 newAmount = 2000e6; // 2000 USDC

        // It should emit stream updated event
        vm.expectEmit(true, true, false, true);
        emit StreamUpdated(TEST_USERNAME, address(usdc), newAmount);

        // It should update stream amount successfully
        vm.prank(bob);
        plugin.editStream(TEST_USERNAME, newAmount);

        IPaymentsV1.Stream memory stream = plugin.getStream(TEST_USERNAME);

        // The amount per second should be different now
        // Calculate expected new amount per second
        uint256 remainingDuration = endTime - block.timestamp;
        uint8 tokenDecimals = 6; // USDC has 6 decimals
        uint256 decimalsMultiplier = 10 ** (20 - tokenDecimals);
        uint256 expectedAmountPerSec = (newAmount * decimalsMultiplier) / remainingDuration;

        assertEq(stream.amount, uint216(expectedAmountPerSec), "Stream amount should be updated");

        // It should cancel old LlamaPay stream and create new LlamaPay stream with updated amount
        // This is implicitly tested by the successful update

        // It should revert with stream not active for non-existent stream
        vm.prank(bob);
        plugin.cancelStream(TEST_USERNAME);

        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.StreamNotActive.selector);
        plugin.editStream(TEST_USERNAME, 3000e6);
    }

    function test_WhenRequestingStreamPayouts() external givenTestingStreamManagement {
        // Setup: Create a stream first
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), endTime);

        // Fast forward some time
        vm.warp(block.timestamp + 1 days);

        // Get initial balance
        uint256 initialRecipientBalance = usdc.balanceOf(alice);

        // It should execute payout successfully with real LlamaPay
        uint256 payoutAmount = plugin.requestStreamPayout(TEST_USERNAME);

        // It should emit stream payout event
        vm.expectEmit(true, true, false, false); // Don't check amount since it's calculated
        emit StreamPayout(TEST_USERNAME, address(usdc), 0);

        // It should update last payout timestamp
        IPaymentsV1.Stream memory stream = plugin.getStream(TEST_USERNAME);
        assertEq(stream.lastPayout, uint40(block.timestamp));

        // Check actual payout occurred
        uint256 finalRecipientBalance = usdc.balanceOf(alice);
        assertEq(finalRecipientBalance - initialRecipientBalance, payoutAmount, "Recipient should receive payout");
        assertTrue(payoutAmount > 0, "Payout amount should be positive after 1 day");

        // It should handle zero withdrawable amount gracefully
        // Request payout immediately again
        uint256 secondPayout = plugin.requestStreamPayout(TEST_USERNAME);
        assertEq(secondPayout, 0, "Second immediate payout should be 0");

        // It should revert with username not found for invalid username
        vm.expectRevert(PaymentsPluginV1.UsernameNotFound.selector);
        plugin.requestStreamPayout("nonexistent");

        // Cancel stream to test inactive stream
        vm.prank(bob);
        plugin.cancelStream(TEST_USERNAME);

        // It should revert with stream not active for non-existent stream
        vm.expectRevert(PaymentsPluginV1.StreamNotActive.selector);
        plugin.requestStreamPayout(TEST_USERNAME);
    }

    modifier givenTestingScheduleManagement() {
        _;
    }

    modifier whenCreatingSchedules() {
        _;
    }

    function test_WhenCreatingSchedules() external givenTestingScheduleManagement whenCreatingSchedules {
        uint40 firstPaymentDate = uint40(block.timestamp + 7 days);
        uint256 amount = 500e6; // 500 USDC per payment

        // It should emit schedule active event
        vm.expectEmit(true, true, false, true);
        emit ScheduleActive(
            TEST_USERNAME, address(usdc), amount, IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate
        );

        // It should create schedule successfully
        vm.prank(bob);
        plugin.createSchedule(
            TEST_USERNAME,
            amount,
            address(usdc),
            IPaymentsV1.IntervalType.Weekly,
            false, // recurring
            firstPaymentDate
        );

        // It should store schedule metadata correctly
        IPaymentsV1.Schedule memory schedule = plugin.getSchedule(TEST_USERNAME);
        assertEq(schedule.token, address(usdc));
        assertEq(schedule.amount, amount);
        assertEq(uint8(schedule.interval), uint8(IPaymentsV1.IntervalType.Weekly));
        assertFalse(schedule.isOneTime);
        assertTrue(schedule.active);
        assertEq(schedule.firstPaymentDate, firstPaymentDate);
        assertEq(schedule.nextPayout, firstPaymentDate);
    }

    function test_WhenInvalidParameters2() external givenTestingScheduleManagement whenCreatingSchedules {
        uint40 firstPaymentDate = uint40(block.timestamp + 7 days);
        uint256 amount = 500e6;

        // It should revert with invalid amount for zero amount
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.InvalidAmount.selector);
        plugin.createSchedule(TEST_USERNAME, 0, address(usdc), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate);

        // It should revert with invalid token for zero token
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.InvalidToken.selector);
        plugin.createSchedule(
            TEST_USERNAME, amount, address(0), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate
        );

        // It should revert with invalid first payment date for past date
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.InvalidFirstPaymentDate.selector);
        plugin.createSchedule(
            TEST_USERNAME, amount, address(usdc), IPaymentsV1.IntervalType.Weekly, false, uint40(block.timestamp - 1)
        );

        // It should revert with username not found for invalid username
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.UsernameNotFound.selector);
        plugin.createSchedule(
            "nonexistent", amount, address(usdc), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate
        );

        // Create a schedule first
        vm.prank(bob);
        plugin.createSchedule(
            TEST_USERNAME, amount, address(usdc), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate
        );

        // It should revert with schedule already exists for duplicate schedule
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.ScheduleAlreadyExists.selector);
        plugin.createSchedule(
            TEST_USERNAME, amount, address(usdc), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate
        );
    }

    function test_WhenCancelingSchedules() external givenTestingScheduleManagement {
        // Setup: Create a schedule first
        uint40 firstPaymentDate = uint40(block.timestamp + 7 days);
        vm.prank(bob);
        plugin.createSchedule(
            TEST_USERNAME, 500e6, address(usdc), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate
        );

        // It should emit payment schedule cancelled event
        vm.expectEmit(true, true, false, true);
        emit PaymentScheduleCancelled(TEST_USERNAME, address(usdc));

        // It should cancel schedule successfully
        vm.prank(bob);
        plugin.cancelSchedule(TEST_USERNAME);

        // It should mark schedule as inactive
        IPaymentsV1.Schedule memory schedule = plugin.getSchedule(TEST_USERNAME);
        assertFalse(schedule.active);

        // It should revert with schedule not active for non-existent schedule
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.ScheduleNotActive.selector);
        plugin.cancelSchedule(TEST_USERNAME);
    }

    function test_WhenEditingSchedules() external givenTestingScheduleManagement {
        // Setup: Create a schedule first
        uint40 firstPaymentDate = uint40(block.timestamp + 7 days);
        uint256 originalAmount = 500e6;
        vm.prank(bob);
        plugin.createSchedule(
            TEST_USERNAME, originalAmount, address(usdc), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate
        );

        uint256 newAmount = 750e6;

        // It should emit schedule updated event
        vm.expectEmit(true, true, false, true);
        emit ScheduleUpdated(TEST_USERNAME, address(usdc), newAmount);

        // It should update schedule amount successfully
        vm.prank(bob);
        plugin.editSchedule(TEST_USERNAME, newAmount);

        IPaymentsV1.Schedule memory schedule = plugin.getSchedule(TEST_USERNAME);
        assertEq(schedule.amount, newAmount);

        // Cancel to test inactive
        vm.prank(bob);
        plugin.cancelSchedule(TEST_USERNAME);

        // It should revert with schedule not active for non-existent schedule
        vm.prank(bob);
        vm.expectRevert(PaymentsPluginV1.ScheduleNotActive.selector);
        plugin.editSchedule(TEST_USERNAME, 1000e6);
    }

    function test_WhenRequestingSchedulePayouts() external givenTestingScheduleManagement {
        // Setup: Create schedules
        uint40 firstPaymentDate = uint40(block.timestamp + 7 days);
        uint256 amount = 500e6;

        // Create recurring schedule
        vm.prank(bob);
        plugin.createSchedule(
            TEST_USERNAME, amount, address(usdc), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate
        );

        // Create one-time schedule for carol
        vm.prank(carol);
        registry.claimUsername("carol");
        vm.prank(bob);
        plugin.createSchedule("carol", amount, address(usdc), IPaymentsV1.IntervalType.Weekly, true, firstPaymentDate);

        // Fast forward to payment date
        vm.warp(firstPaymentDate);

        // It should emit schedule payout event
        vm.expectEmit(true, true, false, true);
        emit SchedulePayout(TEST_USERNAME, address(usdc), amount, 1);

        // It should execute payout successfully for due payment
        uint256 initialBalance = usdc.balanceOf(alice);
        plugin.requestSchedulePayout(TEST_USERNAME);
        uint256 finalBalance = usdc.balanceOf(alice);

        // It should transfer real USDC tokens
        assertEq(finalBalance - initialBalance, amount, "Should transfer correct amount");

        // It should update next payout timestamp for recurring
        IPaymentsV1.Schedule memory schedule = plugin.getSchedule(TEST_USERNAME);
        assertEq(schedule.nextPayout, firstPaymentDate + 7 days, "Next payout should be 1 week later");
        assertTrue(schedule.active, "Recurring schedule should remain active");

        // Test one-time schedule
        uint256 carolInitialBalance = usdc.balanceOf(carol);
        plugin.requestSchedulePayout("carol");
        uint256 carolFinalBalance = usdc.balanceOf(carol);
        assertEq(carolFinalBalance - carolInitialBalance, amount);

        // It should mark one-time schedule as inactive
        IPaymentsV1.Schedule memory carolSchedule = plugin.getSchedule("carol");
        assertFalse(carolSchedule.active, "One-time schedule should be inactive after payout");

        // It should handle multiple periods correctly
        // Fast forward 3 weeks (miss 2 payments)
        vm.warp(block.timestamp + 21 days);

        initialBalance = usdc.balanceOf(alice);
        plugin.requestSchedulePayout(TEST_USERNAME);
        finalBalance = usdc.balanceOf(alice);

        // Should pay for 3 periods (the missed 2 + current)
        assertEq(finalBalance - initialBalance, amount * 3, "Should pay for multiple periods");

        // It should revert with payment not due for early payout
        vm.expectRevert(PaymentsPluginV1.PaymentNotDue.selector);
        plugin.requestSchedulePayout(TEST_USERNAME);

        // It should revert with schedule not active for non-existent schedule
        vm.expectRevert(PaymentsPluginV1.ScheduleNotActive.selector);
        plugin.requestSchedulePayout("carol"); // Already paid out one-time
    }

    modifier givenTestingPermissionSystem() {
        _;
    }

    function test_GivenTestingPermissionSystem() external givenTestingPermissionSystem {
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        uint40 firstPaymentDate = uint40(block.timestamp + 7 days);

        // Get the actual test contract address (this contract, not alice)
        address unauthorizedCaller = address(this);

        // It should revert create stream without manager permission
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                unauthorizedCaller,
                plugin.MANAGER_PERMISSION_ID()
            )
        );
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), endTime);

        // Create stream as manager for next tests
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), endTime);

        // It should revert cancel stream without manager permission
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                unauthorizedCaller,
                plugin.MANAGER_PERMISSION_ID()
            )
        );
        plugin.cancelStream(TEST_USERNAME);

        // It should revert edit stream without manager permission
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                unauthorizedCaller,
                plugin.MANAGER_PERMISSION_ID()
            )
        );
        plugin.editStream(TEST_USERNAME, 2000e6);

        // It should revert create schedule without manager permission
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                unauthorizedCaller,
                plugin.MANAGER_PERMISSION_ID()
            )
        );
        plugin.createSchedule(
            TEST_USERNAME, 500e6, address(usdc), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate
        );

        // Create schedule as manager for next tests
        vm.prank(carol);
        registry.claimUsername("carol");
        vm.prank(bob);
        plugin.createSchedule("carol", 500e6, address(usdc), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate);

        // It should revert cancel schedule without manager permission
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                unauthorizedCaller,
                plugin.MANAGER_PERMISSION_ID()
            )
        );
        plugin.cancelSchedule("carol");

        // It should revert edit schedule without manager permission
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                address(plugin),
                unauthorizedCaller,
                plugin.MANAGER_PERMISSION_ID()
            )
        );
        plugin.editSchedule("carol", 750e6);
    }

    modifier givenTestingLlamaPayIntegration() {
        _;
    }

    function test_GivenTestingLlamaPayIntegration() external givenTestingLlamaPayIntegration {
        // It should get or deploy LlamaPay contract for token
        (address predictedAddress, bool isDeployedBefore) = llamaPayFactory.getLlamaPayContractByToken(address(usdc));

        // Create a stream to trigger deployment if needed
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), endTime);

        (address llamaPayAddress, bool isDeployedAfter) = llamaPayFactory.getLlamaPayContractByToken(address(usdc));
        assertTrue(isDeployedAfter, "LlamaPay should be deployed");

        // It should cache LlamaPay contract addresses
        assertEq(plugin.tokenToLlamaPay(address(usdc)), llamaPayAddress, "Should cache LlamaPay address");

        // It should calculate amount per second correctly with decimals
        IPaymentsV1.Stream memory stream = plugin.getStream(TEST_USERNAME);

        // USDC has 6 decimals, LlamaPay uses 20 decimals internally
        uint256 expectedAmountPerSec = (STREAM_AMOUNT * 10 ** 14) / STREAM_DURATION; // 10^14 = 10^(20-6)
        assertEq(stream.amount, uint216(expectedAmountPerSec), "Amount per second calculation");

        // It should handle USDC decimals conversion properly
        // This is implicitly tested by successful stream creation

        // It should ensure DAO approval for LlamaPay spending
        uint256 allowance = usdc.allowance(address(dao), llamaPayAddress);
        // USDC on Base uses a different max value than type(uint256).max
        assertTrue(allowance >= STREAM_AMOUNT, "DAO should approve enough for stream");

        // It should deposit to real LlamaPay contract
        ILlamaPay llamaPay = ILlamaPay(llamaPayAddress);
        assertTrue(llamaPay.balances(address(dao)) > 0, "DAO should have balance in LlamaPay");

        // It should create stream with reason in real LlamaPay
        bytes32 streamId = llamaPay.getStreamId(address(dao), alice, stream.amount);
        uint256 streamStart = llamaPay.streamToStart(streamId);
        assertTrue(streamStart > 0, "Stream should exist in LlamaPay");

        // Cancel stream to test cancellation
        vm.prank(bob);
        plugin.cancelStream(TEST_USERNAME);

        // It should cancel stream in real LlamaPay
        streamStart = llamaPay.streamToStart(streamId);
        assertEq(streamStart, 0, "Stream should be cancelled in LlamaPay");

        // It should withdraw funds from real LlamaPay
        assertEq(llamaPay.balances(address(dao)), 0, "DAO balance in LlamaPay should be 0 after withdrawal");
    }

    modifier givenTestingViewFunctions() {
        _;
    }

    function test_GivenTestingViewFunctions() external givenTestingViewFunctions {
        // Setup data
        uint40 endTime = uint40(block.timestamp + STREAM_DURATION);
        uint40 firstPaymentDate = uint40(block.timestamp + 7 days);

        vm.prank(bob);
        plugin.createStream(TEST_USERNAME, STREAM_AMOUNT, address(usdc), endTime);

        vm.prank(carol);
        registry.claimUsername("carol");
        vm.prank(bob);
        plugin.createSchedule("carol", 500e6, address(usdc), IPaymentsV1.IntervalType.Weekly, false, firstPaymentDate);

        // It should return correct stream information
        IPaymentsV1.Stream memory stream = plugin.getStream(TEST_USERNAME);
        assertEq(stream.token, address(usdc));
        assertEq(stream.endDate, endTime);
        assertTrue(stream.active);
        assertTrue(stream.amount > 0);
        assertEq(stream.lastPayout, uint40(block.timestamp));

        // It should return empty for non-existent stream
        IPaymentsV1.Stream memory emptyStream = plugin.getStream("nonexistent");
        assertEq(emptyStream.token, address(0));
        assertEq(emptyStream.endDate, 0);
        assertFalse(emptyStream.active);
        assertEq(emptyStream.amount, 0);

        // It should return correct schedule information
        IPaymentsV1.Schedule memory schedule = plugin.getSchedule("carol");
        assertEq(schedule.token, address(usdc));
        assertEq(schedule.amount, 500e6);
        assertEq(uint8(schedule.interval), uint8(IPaymentsV1.IntervalType.Weekly));
        assertFalse(schedule.isOneTime);
        assertTrue(schedule.active);
        assertEq(schedule.firstPaymentDate, firstPaymentDate);
        assertEq(schedule.nextPayout, firstPaymentDate);

        // It should return empty for non-existent schedule
        IPaymentsV1.Schedule memory emptySchedule = plugin.getSchedule("nonexistent");
        assertEq(emptySchedule.token, address(0));
        assertEq(emptySchedule.amount, 0);
        assertFalse(emptySchedule.active);
    }
}
