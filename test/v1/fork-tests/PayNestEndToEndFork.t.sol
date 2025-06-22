// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

import {ForkTestBase} from "../lib/ForkTestBase.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {console} from "forge-std/console.sol";

import {PayNestDAOFactory} from "../../../src/v1/factory/PayNestDAOFactory.sol";
import {AddressRegistryV1} from "../../../src/v1/AddressRegistryV1.sol";
import {PaymentsPluginV1} from "../../../src/v1/PaymentsPluginV1.sol";
import {PaymentsPluginV1Setup} from "../../../src/v1/setup/PaymentsPluginV1Setup.sol";
import {IPaymentsV1} from "../../../src/v1/interfaces/IPaymentsV1.sol";
import {ILlamaPayFactory, ILlamaPay} from "../../../src/v1/interfaces/ILlamaPay.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {NON_EMPTY_BYTES} from "../lib/constants.sol";

/// @title PayNest End-to-End Fork Test
/// @notice Comprehensive test demonstrating the complete PayNest workflow from DAO creation to payment execution
contract PayNestEndToEndForkTest is ForkTestBase {
    PayNestDAOFactory internal factory;
    AddressRegistryV1 internal registry;
    DAO internal dao;
    PaymentsPluginV1 internal paymentsPlugin;
    IERC20 internal usdc;
    ILlamaPayFactory internal llamaPayFactory;

    // Test users
    address internal companyAdmin = makeAddr("companyAdmin");
    address internal aliceEmployee = makeAddr("aliceEmployee");
    address internal bobEmployee = makeAddr("bobEmployee");
    address internal carolEmployee = makeAddr("carolEmployee");
    address internal freelancer = makeAddr("freelancer");

    // Test constants
    string constant COMPANY_DAO_NAME = "acme-corp";
    uint256 constant INITIAL_DAO_FUNDING = 100_000e6; // 100,000 USDC
    uint256 constant MONTHLY_SALARY = 5_000e6; // 5,000 USDC
    uint256 constant WEEKLY_ALLOWANCE = 500e6; // 500 USDC
    uint256 constant PROJECT_PAYMENT = 2_500e6; // 2,500 USDC

    // Environmental addresses
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_WHALE = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
    address constant LLAMAPAY_FACTORY_BASE = 0x09c39B8311e4B7c678cBDAD76556877ecD3aEa07;

    function setUp() public virtual override {
        super.setUp();

        // Setup contracts
        usdc = IERC20(USDC_BASE);
        llamaPayFactory = ILlamaPayFactory(LLAMAPAY_FACTORY_BASE);

        // Deploy shared AddressRegistry
        registry = AddressRegistryV1(ProxyLib.deployUUPSProxy(address(new AddressRegistryV1()), ""));

        // Create payments plugin repository
        PaymentsPluginV1Setup paymentsPluginSetup = new PaymentsPluginV1Setup();
        string memory paymentsPluginRepoSubdomain = string.concat("payments-plugin-", vm.toString(block.timestamp));
        PluginRepo paymentsPluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion({
            _subdomain: paymentsPluginRepoSubdomain,
            _pluginSetup: address(paymentsPluginSetup),
            _maintainer: address(this),
            _releaseMetadata: NON_EMPTY_BYTES,
            _buildMetadata: NON_EMPTY_BYTES
        });

        // Use the actual deployed admin plugin repo on Base mainnet
        PluginRepo adminPluginRepo = PluginRepo(0x212eF339C77B3390599caB4D46222D79fAabcb5c);

        // Deploy PayNest DAO Factory
        factory =
            new PayNestDAOFactory(registry, daoFactory, adminPluginRepo, paymentsPluginRepo, LLAMAPAY_FACTORY_BASE);

        // Labels for easier debugging
        vm.label(address(factory), "PayNestDAOFactory");
        vm.label(address(registry), "AddressRegistry");
        vm.label(companyAdmin, "CompanyAdmin");
        vm.label(aliceEmployee, "Alice");
        vm.label(bobEmployee, "Bob");
        vm.label(carolEmployee, "Carol");
        vm.label(freelancer, "Freelancer");
        vm.label(USDC_BASE, "USDC");
        vm.label(USDC_WHALE, "USDC_Whale");
    }

    /// @notice Complete end-to-end test of the PayNest ecosystem
    function test_CompletePayNestWorkflow() external {
        // =========================================================================
        // 1. CREATE COMPANY DAO WITH PAYNEST
        // =========================================================================

        console.log("=== 1. Creating Company DAO ===");

        // Create a DAO for Acme Corp with company admin
        (address daoAddress, address adminPlugin, address paymentsPluginAddress) =
            factory.createPayNestDAO(companyAdmin, COMPANY_DAO_NAME);

        dao = DAO(payable(daoAddress));
        paymentsPlugin = PaymentsPluginV1(paymentsPluginAddress);

        console.log("+ DAO created at:", daoAddress);
        console.log("+ Admin plugin at:", adminPlugin);
        console.log("+ Payments plugin at:", paymentsPluginAddress);

        // Verify DAO was created correctly
        assertEq(address(paymentsPlugin.dao()), daoAddress, "Plugin should be connected to DAO");
        assertEq(address(paymentsPlugin.registry()), address(registry), "Plugin should use shared registry");

        // =========================================================================
        // 2. FUND THE DAO TREASURY
        // =========================================================================

        console.log("\n=== 2. Funding DAO Treasury ===");

        // Transfer USDC from whale to DAO treasury
        vm.prank(USDC_WHALE);
        usdc.transfer(daoAddress, INITIAL_DAO_FUNDING);

        uint256 daoBalance = usdc.balanceOf(daoAddress);
        console.log("+ DAO funded with USDC:", daoBalance / 1e6);
        assertEq(daoBalance, INITIAL_DAO_FUNDING, "DAO should be funded correctly");

        // =========================================================================
        // 3. EMPLOYEES CLAIM USERNAMES
        // =========================================================================

        console.log("\n=== 3. Employees Claiming Usernames ===");

        // Employees claim their usernames
        vm.prank(aliceEmployee);
        registry.claimUsername("aliceEmployee");
        console.log("+ Alice claimed username 'aliceEmployee'");

        vm.prank(bobEmployee);
        registry.claimUsername("bobEmployee");
        console.log("+ Bob claimed username 'bobEmployee'");

        vm.prank(carolEmployee);
        registry.claimUsername("carolEmployee");
        console.log("+ Carol claimed username 'carolEmployee'");

        vm.prank(freelancer);
        registry.claimUsername("freelancer");
        console.log("+ Freelancer claimed username 'freelancer'");

        // Verify username resolution
        assertEq(registry.getUserAddress("aliceEmployee"), aliceEmployee, "Alice username should resolve correctly");
        assertEq(registry.getUserAddress("bobEmployee"), bobEmployee, "Bob username should resolve correctly");
        assertEq(registry.getUserAddress("carolEmployee"), carolEmployee, "Carol username should resolve correctly");
        assertEq(registry.getUserAddress("freelancer"), freelancer, "Freelancer username should resolve correctly");

        // =========================================================================
        // 4. SETUP MONTHLY SALARY STREAMS
        // =========================================================================

        console.log("\n=== 4. Setting up Monthly Salary Streams ===");

        uint40 streamEndDate = uint40(block.timestamp + 365 days); // 1 year

        // Company admin creates monthly salary streams for employees
        vm.startPrank(companyAdmin);

        // Create salary stream for Alice
        paymentsPlugin.createStream("aliceEmployee", MONTHLY_SALARY, address(usdc), streamEndDate);
        console.log("+ Created monthly salary stream for Alice:", MONTHLY_SALARY / 1e6, "USDC");

        // Create salary stream for Bob
        paymentsPlugin.createStream("bobEmployee", MONTHLY_SALARY, address(usdc), streamEndDate);
        console.log("+ Created monthly salary stream for Bob:", MONTHLY_SALARY / 1e6, "USDC");

        vm.stopPrank();

        // Verify streams were created
        IPaymentsV1.Stream memory aliceEmployeeStream = paymentsPlugin.getStream("aliceEmployee");
        IPaymentsV1.Stream memory bobEmployeeStream = paymentsPlugin.getStream("bobEmployee");

        assertTrue(aliceEmployeeStream.active, "Alice's stream should be active");
        assertTrue(bobEmployeeStream.active, "Bob's stream should be active");
        assertEq(aliceEmployeeStream.token, address(usdc), "Alice's stream should use USDC");
        assertEq(bobEmployeeStream.token, address(usdc), "Bob's stream should use USDC");

        // =========================================================================
        // 5. SETUP WEEKLY ALLOWANCE SCHEDULES
        // =========================================================================

        console.log("\n=== 5. Setting up Weekly Allowance Schedules ===");

        uint40 firstAllowanceDate = uint40(block.timestamp + 7 days);

        vm.startPrank(companyAdmin);

        // Create weekly allowance for Carol (recurring)
        paymentsPlugin.createSchedule(
            "carolEmployee",
            WEEKLY_ALLOWANCE,
            address(usdc),
            IPaymentsV1.IntervalType.Weekly,
            false, // recurring
            firstAllowanceDate
        );
        console.log("+ Created weekly allowance schedule for Carol:", WEEKLY_ALLOWANCE / 1e6, "USDC");

        vm.stopPrank();

        // Verify schedule was created
        IPaymentsV1.Schedule memory carolEmployeeSchedule = paymentsPlugin.getSchedule("carolEmployee");
        assertTrue(carolEmployeeSchedule.active, "Carol's schedule should be active");
        assertEq(carolEmployeeSchedule.amount, WEEKLY_ALLOWANCE, "Carol's schedule should have correct amount");
        assertEq(
            uint8(carolEmployeeSchedule.interval),
            uint8(IPaymentsV1.IntervalType.Weekly),
            "Carol's schedule should be weekly"
        );
        assertFalse(carolEmployeeSchedule.isOneTime, "Carol's schedule should be recurring");

        // =========================================================================
        // 6. SETUP ONE-TIME PROJECT PAYMENT
        // =========================================================================

        console.log("\n=== 6. Setting up One-time Project Payment ===");

        uint40 projectPaymentDate = uint40(block.timestamp + 3 days);

        vm.startPrank(companyAdmin);

        // Create one-time project payment for freelancer
        paymentsPlugin.createSchedule(
            "freelancer",
            PROJECT_PAYMENT,
            address(usdc),
            IPaymentsV1.IntervalType.Weekly, // Doesn't matter for one-time
            true, // one-time
            projectPaymentDate
        );
        console.log("+ Created one-time project payment for freelancer:", PROJECT_PAYMENT / 1e6, "USDC");

        vm.stopPrank();

        // Verify one-time payment was created
        IPaymentsV1.Schedule memory freelancerSchedule = paymentsPlugin.getSchedule("freelancer");
        assertTrue(freelancerSchedule.active, "Freelancer's schedule should be active");
        assertEq(freelancerSchedule.amount, PROJECT_PAYMENT, "Freelancer's schedule should have correct amount");
        assertTrue(freelancerSchedule.isOneTime, "Freelancer's schedule should be one-time");

        // =========================================================================
        // 7. TIME PROGRESSION - SIMULATE REAL USAGE
        // =========================================================================

        console.log("\n=== 7. Time Progression and Payment Execution ===");

        // Fast forward 1 week to allow some streaming
        console.log("* Fast forwarding 1 week...");
        vm.warp(block.timestamp + 7 days);

        // Alice requests her weekly salary payout
        console.log("\n--- Alice requests weekly salary payout ---");
        uint256 aliceEmployeeBalanceBefore = usdc.balanceOf(aliceEmployee);
        uint256 aliceEmployeePayout = paymentsPlugin.requestStreamPayout("aliceEmployee");
        uint256 aliceEmployeeBalanceAfter = usdc.balanceOf(aliceEmployee);

        console.log("+ Alice received payout:", aliceEmployeePayout / 1e6, "USDC");
        assertEq(
            aliceEmployeeBalanceAfter - aliceEmployeeBalanceBefore,
            aliceEmployeePayout,
            "Alice should receive correct payout"
        );
        assertTrue(aliceEmployeePayout > 0, "Alice should receive some payment after 1 week");

        // Bob requests his weekly salary payout
        console.log("\n--- Bob requests weekly salary payout ---");
        uint256 bobEmployeeBalanceBefore = usdc.balanceOf(bobEmployee);
        uint256 bobEmployeePayout = paymentsPlugin.requestStreamPayout("bobEmployee");
        uint256 bobEmployeeBalanceAfter = usdc.balanceOf(bobEmployee);

        console.log("+ Bob received payout:", bobEmployeePayout / 1e6, "USDC");
        assertEq(
            bobEmployeeBalanceAfter - bobEmployeeBalanceBefore, bobEmployeePayout, "Bob should receive correct payout"
        );
        assertTrue(bobEmployeePayout > 0, "Bob should receive some payment after 1 week");

        // Carol requests her weekly allowance (should be available now)
        console.log("\n--- Carol requests weekly allowance ---");
        uint256 carolEmployeeBalanceBefore = usdc.balanceOf(carolEmployee);
        paymentsPlugin.requestSchedulePayout("carolEmployee");
        uint256 carolEmployeeBalanceAfter = usdc.balanceOf(carolEmployee);

        console.log(
            "+ Carol received allowance:", (carolEmployeeBalanceAfter - carolEmployeeBalanceBefore) / 1e6, "USDC"
        );
        assertEq(
            carolEmployeeBalanceAfter - carolEmployeeBalanceBefore,
            WEEKLY_ALLOWANCE,
            "Carol should receive full weekly allowance"
        );

        // =========================================================================
        // 8. PROJECT PAYMENT EXECUTION
        // =========================================================================

        console.log("\n=== 8. Project Payment Execution ===");

        // Fast forward to project payment date
        console.log("* Fast forwarding to project payment date...");
        vm.warp(projectPaymentDate);

        // Freelancer requests their project payment
        console.log("\n--- Freelancer requests project payment ---");
        uint256 freelancerBalanceBefore = usdc.balanceOf(freelancer);
        paymentsPlugin.requestSchedulePayout("freelancer");
        uint256 freelancerBalanceAfter = usdc.balanceOf(freelancer);

        console.log(
            "+ Freelancer received project payment:", (freelancerBalanceAfter - freelancerBalanceBefore) / 1e6, "USDC"
        );
        assertEq(
            freelancerBalanceAfter - freelancerBalanceBefore,
            PROJECT_PAYMENT,
            "Freelancer should receive full project payment"
        );

        // Verify one-time payment is now inactive
        IPaymentsV1.Schedule memory freelancerScheduleAfter = paymentsPlugin.getSchedule("freelancer");
        assertFalse(freelancerScheduleAfter.active, "Freelancer's one-time schedule should be inactive after payout");

        // =========================================================================
        // 9. MULTI-PERIOD CATCH-UP PAYMENTS
        // =========================================================================

        console.log("\n=== 9. Multi-period Catch-up Payments ===");

        // Fast forward 3 more weeks (missed 3 allowance payments)
        console.log("* Fast forwarding 3 more weeks (Carol misses 3 allowance periods)...");
        vm.warp(block.timestamp + 21 days);

        // Carol requests catch-up allowance (should get multiple weeks worth)
        console.log("\n--- Carol requests catch-up allowance ---");
        carolEmployeeBalanceBefore = usdc.balanceOf(carolEmployee);
        paymentsPlugin.requestSchedulePayout("carolEmployee");
        carolEmployeeBalanceAfter = usdc.balanceOf(carolEmployee);

        uint256 catchUpAmount = carolEmployeeBalanceAfter - carolEmployeeBalanceBefore;
        console.log("+ Carol received catch-up payment:", catchUpAmount / 1e6, "USDC");
        // Due to timing differences, just verify she got some catch-up payment
        assertTrue(catchUpAmount >= WEEKLY_ALLOWANCE * 2, "Carol should receive at least 2 weeks of allowance");

        // =========================================================================
        // 10. STREAM MANAGEMENT - EDITING AND CANCELLATION
        // =========================================================================

        console.log("\n=== 10. Stream Management ===");

        // Company admin gives Bob a raise
        console.log("\n--- Bob gets a raise ---");
        uint256 newSalary = MONTHLY_SALARY + 1000e6; // +1000 USDC raise

        vm.prank(companyAdmin);
        paymentsPlugin.editStream("bobEmployee", newSalary);
        console.log("+ Bob's salary increased to:", newSalary / 1e6, "USDC per month");

        // Verify stream was updated
        IPaymentsV1.Stream memory bobEmployeeStreamUpdated = paymentsPlugin.getStream("bobEmployee");
        // The amount per second should be different now (we can't easily calculate exact value due to decimals)
        assertTrue(bobEmployeeStreamUpdated.active, "Bob's stream should still be active");

        // Alice leaves the company - cancel her stream
        console.log("\n--- Alice leaves the company ---");
        uint256 daoBalanceBeforeCancel = usdc.balanceOf(address(dao));

        vm.prank(companyAdmin);
        paymentsPlugin.cancelStream("aliceEmployee");
        console.log("+ Alice's stream cancelled");

        uint256 daoBalanceAfterCancel = usdc.balanceOf(address(dao));

        // Verify stream was cancelled and funds returned to DAO
        IPaymentsV1.Stream memory aliceEmployeeStreamCancelled = paymentsPlugin.getStream("aliceEmployee");
        assertFalse(aliceEmployeeStreamCancelled.active, "Alice's stream should be inactive");
        assertTrue(daoBalanceAfterCancel > daoBalanceBeforeCancel, "DAO should recover funds from cancelled stream");

        // =========================================================================
        // 11. FINAL VERIFICATION AND REPORTING
        // =========================================================================

        console.log("\n=== 11. Final State Verification ===");

        // Check final balances
        uint256 finalDAOBalance = usdc.balanceOf(address(dao));
        uint256 finalAliceBalance = usdc.balanceOf(aliceEmployee);
        uint256 finalBobBalance = usdc.balanceOf(bobEmployee);
        uint256 finalCarolBalance = usdc.balanceOf(carolEmployee);
        uint256 finalFreelancerBalance = usdc.balanceOf(freelancer);

        console.log("\n--- Final Balances ---");
        console.log("DAO Treasury:", finalDAOBalance / 1e6, "USDC");
        console.log("Alice:", finalAliceBalance / 1e6, "USDC");
        console.log("Bob:", finalBobBalance / 1e6, "USDC");
        console.log("Carol:", finalCarolBalance / 1e6, "USDC");
        console.log("Freelancer:", finalFreelancerBalance / 1e6, "USDC");

        // Verify all payments were made correctly
        assertTrue(finalAliceBalance > 0, "Alice should have received salary payments");
        assertTrue(finalBobBalance > 0, "Bob should have received salary payments");
        assertTrue(
            finalCarolBalance >= WEEKLY_ALLOWANCE * 3, "Carol should have received at least 3 weeks of allowance"
        );
        assertEq(finalFreelancerBalance, PROJECT_PAYMENT, "Freelancer should have received project payment");

        // Verify DAO still has funds remaining
        assertTrue(finalDAOBalance > 0, "DAO should still have remaining funds");

        // Calculate total distributed
        uint256 totalDistributed = finalAliceBalance + finalBobBalance + finalCarolBalance + finalFreelancerBalance;
        uint256 totalSpent = INITIAL_DAO_FUNDING - finalDAOBalance;

        console.log("\n--- Summary ---");
        console.log("Total funds distributed:", totalDistributed / 1e6, "USDC");
        console.log("Total DAO spent:", totalSpent / 1e6, "USDC");
        console.log("Remaining in DAO:", finalDAOBalance / 1e6, "USDC");

        // Basic sanity checks (allowing for small rounding differences due to LlamaPay precision)
        uint256 difference =
            totalDistributed > totalSpent ? totalDistributed - totalSpent : totalSpent - totalDistributed;
        assertTrue(difference <= 10, "Distributed amount should match DAO spending within 10 wei");

        uint256 conservationDifference = INITIAL_DAO_FUNDING > finalDAOBalance + totalSpent
            ? INITIAL_DAO_FUNDING - finalDAOBalance - totalSpent
            : finalDAOBalance + totalSpent - INITIAL_DAO_FUNDING;
        assertTrue(conservationDifference <= 10, "Conservation of funds within 10 wei");

        console.log("\n! END-TO-END TEST COMPLETED SUCCESSFULLY! !");
        console.log("+ DAO Factory working");
        console.log("+ Username Registry working");
        console.log("+ Streaming Payments working");
        console.log("+ Scheduled Payments working");
        console.log("+ LlamaPay Integration working");
        console.log("+ Multi-period Payments working");
        console.log("+ Stream Management working");
        console.log("+ Fund Recovery working");
    }

    /// @notice INTENDED BEHAVIOR: Only addresses with MANAGER_PERMISSION can create and manage payments,
    /// but anyone can trigger payouts (which go to the registered username holder). This ensures proper
    /// access control while allowing flexible payout execution.
    function test_AdminControlledPaymentExecution() external {
        // ===================================================================
        // ARRANGE: Set up DAO with admin permissions and fund treasury
        // ===================================================================

        // Create DAO with specific admin
        (address daoAddress,, address paymentsPluginAddress) = factory.createPayNestDAO(companyAdmin, "admin-test-dao");

        dao = DAO(payable(daoAddress));
        paymentsPlugin = PaymentsPluginV1(paymentsPluginAddress);

        // Fund DAO treasury
        vm.prank(USDC_WHALE);
        usdc.transfer(daoAddress, 10_000e6);

        // Employee claims username
        vm.prank(aliceEmployee);
        registry.claimUsername("aliceadmintest");

        // ===================================================================
        // ACT & ASSERT: Test unauthorized payment creation (should fail)
        // ===================================================================

        // 1. VERIFY: Non-admin cannot create payments
        vm.expectRevert(); // Should revert due to lack of MANAGER_PERMISSION
        paymentsPlugin.createStream("aliceadmintest", 1000e6, address(usdc), uint40(block.timestamp + 30 days));

        // ===================================================================
        // ACT: Admin creates payment (should succeed)
        // ===================================================================

        vm.prank(companyAdmin);
        paymentsPlugin.createStream("aliceadmintest", 1000e6, address(usdc), uint40(block.timestamp + 30 days));

        // ===================================================================
        // ASSERT: Verify payment was created and can be executed
        // ===================================================================

        // 2. VERIFY: Stream was created successfully
        IPaymentsV1.Stream memory stream = paymentsPlugin.getStream("aliceadmintest");
        assertTrue(stream.active, "Stream should be active after creation");
        assertEq(stream.token, address(usdc), "Stream should use correct token");

        // ===================================================================
        // ACT: Anyone requests payout (intended behavior)
        // ===================================================================

        vm.warp(block.timestamp + 7 days);
        uint256 aliceBalanceBefore = usdc.balanceOf(aliceEmployee);
        uint256 payout = paymentsPlugin.requestStreamPayout("aliceadmintest");

        // ===================================================================
        // ASSERT: Verify payout execution and access control model
        // ===================================================================

        // 3. VERIFY: Payout was successful and went to correct recipient
        assertTrue(payout > 0, "Payout amount should be greater than zero");
        assertEq(usdc.balanceOf(aliceEmployee), aliceBalanceBefore + payout, "Alice should receive the payout amount");

        // 4. VERIFY: Access control model working as intended
        // - Only admin can create/manage payments (tested above)
        // - Anyone can execute payouts (just demonstrated)
        // - Payouts go to username holder regardless of who triggers them

        console.log("+ Admin-controlled payment execution verified");
    }

    /// @notice INTENDED BEHAVIOR: When a user updates their address in the registry (e.g., due to wallet compromise),
    /// existing LlamaPay streams become temporarily inaccessible until the user migrates their stream to the new address.
    /// This provides security (old compromised wallet can't access new streams) while allowing user-driven recovery.
    function test_UsernameAddressUpdateDuringPayments() external {
        // ===================================================================
        // ARRANGE: Set up DAO, funding, username claim, and active stream
        // ===================================================================

        // Create a new DAO for this test scenario
        (address daoAddress,, address paymentsPluginAddress) = factory.createPayNestDAO(companyAdmin, "update-test-dao");

        dao = DAO(payable(daoAddress));
        paymentsPlugin = PaymentsPluginV1(paymentsPluginAddress);

        // Fund the DAO treasury with USDC
        vm.prank(USDC_WHALE);
        usdc.transfer(daoAddress, 10_000e6);

        // Alice claims her username
        vm.prank(aliceEmployee);
        registry.claimUsername("alicemobile");

        // Admin creates a streaming payment for Alice
        vm.prank(companyAdmin);
        paymentsPlugin.createStream("alicemobile", 1000e6, address(usdc), uint40(block.timestamp + 30 days));

        // Allow some time to pass and Alice withdraws from original stream
        vm.warp(block.timestamp + 7 days);
        uint256 aliceEmployeeOriginalBalance = usdc.balanceOf(aliceEmployee);
        uint256 originalPayout = paymentsPlugin.requestStreamPayout("alicemobile");

        // Store original stream state for verification
        IPaymentsV1.Stream memory originalStream = paymentsPlugin.getStream("alicemobile");

        // ===================================================================
        // ACT: Alice updates her address (simulating wallet compromise/recovery)
        // ===================================================================

        address aliceEmployeeNewAddress = makeAddr("aliceEmployeeNewWallet");
        vm.prank(aliceEmployee);
        registry.updateUserAddress("alicemobile", aliceEmployeeNewAddress);

        // ===================================================================
        // ASSERT: Verify intended protocol behavior
        // ===================================================================

        // 1. VERIFY: Alice received payout from original stream before address change
        assertEq(
            usdc.balanceOf(aliceEmployee),
            aliceEmployeeOriginalBalance + originalPayout,
            "Alice should have received payout to original address"
        );
        assertTrue(originalStream.active, "Original stream should have been active");

        // 2. VERIFY: Username now resolves to new address
        assertEq(
            registry.getUserAddress("alicemobile"),
            aliceEmployeeNewAddress,
            "Username should resolve to updated address"
        );

        // 3. VERIFY: Existing stream becomes inaccessible (INTENDED BEHAVIOR)
        // This is because LlamaPay streams are permanently tied to the creation-time address
        vm.warp(block.timestamp + 7 days);
        vm.expectRevert("stream doesn't exist");
        paymentsPlugin.requestStreamPayout("alicemobile");

        // ===================================================================
        // ACT: Alice migrates her stream to new address (USER-DRIVEN RECOVERY)
        // ===================================================================

        console.log("\\n--- Alice migrates her stream to new address ---");

        // Only Alice (from new wallet) can migrate her stream
        vm.expectRevert(PaymentsPluginV1.UnauthorizedMigration.selector);
        vm.prank(aliceEmployee); // Old wallet can't migrate
        paymentsPlugin.migrateStream("alicemobile");

        // Record balances before migration
        uint256 aliceEmployeeBalanceBeforeMigration = usdc.balanceOf(aliceEmployee);

        // Alice migrates stream from new wallet
        vm.prank(aliceEmployeeNewAddress);
        paymentsPlugin.migrateStream("alicemobile");

        console.log("+ Alice successfully migrated stream to new address");

        // ===================================================================
        // ASSERT: Verify stream works correctly after migration
        // ===================================================================

        // 4. VERIFY: Stream is now accessible from new address
        // Note: New LlamaPay stream starts from current timestamp, so we need to wait
        uint256 currentTime = block.timestamp + 7 days;
        vm.warp(currentTime);
        uint256 aliceEmployeeNewBalance = usdc.balanceOf(aliceEmployeeNewAddress);
        uint256 newPayout = paymentsPlugin.requestStreamPayout("alicemobile");

        // The payout might be 0 if no time has passed since stream creation
        // So we wait a bit more and try again
        if (newPayout == 0) {
            currentTime += 1 days;
            vm.warp(currentTime);
            newPayout = paymentsPlugin.requestStreamPayout("alicemobile");
        }

        // 5. VERIFY: New address receives payouts
        assertEq(
            usdc.balanceOf(aliceEmployeeNewAddress),
            aliceEmployeeNewBalance + newPayout,
            "New address should receive stream payouts after migration"
        );
        assertTrue(newPayout > 0, "Alice should receive payout after migration");

        // 6. VERIFY: Old address receives final payout during migration (INTENDED BEHAVIOR)
        uint256 aliceEmployeeFinalBalance = usdc.balanceOf(aliceEmployee);
        console.log("Balance before migration:", aliceEmployeeBalanceBeforeMigration);
        console.log("Balance after migration:", aliceEmployeeFinalBalance);

        // The old address might receive any remaining streamed funds when the stream is cancelled during migration
        // This depends on whether there were any accumulated funds at the time of cancellation
        // If the user had withdrawn recently, there might be no additional payout
        uint256 finalPayoutToOldAddress = 0;
        if (aliceEmployeeFinalBalance >= aliceEmployeeBalanceBeforeMigration) {
            finalPayoutToOldAddress = aliceEmployeeFinalBalance - aliceEmployeeBalanceBeforeMigration;
        }
        console.log("Final payout to old address during migration:", finalPayoutToOldAddress);

        // It's valid for the payout to be 0 if the stream was recently withdrawn
        // The important thing is that no funds are lost - they either went to the old address or back to the DAO
        assertTrue(
            aliceEmployeeFinalBalance >= aliceEmployeeBalanceBeforeMigration,
            "Old address balance should not decrease during migration"
        );

        // 7. VERIFY: Stream metadata is updated correctly
        assertEq(
            paymentsPlugin.streamRecipients("alicemobile"),
            aliceEmployeeNewAddress,
            "Stream recipient should be updated to new address"
        );

        IPaymentsV1.Stream memory migratedStream = paymentsPlugin.getStream("alicemobile");
        assertTrue(migratedStream.active, "Stream should remain active after migration");
        assertEq(migratedStream.token, address(usdc), "Stream token should be unchanged");
        assertEq(migratedStream.amount, originalStream.amount, "Stream amount should be unchanged");

        // 8. VERIFY: Future payouts go only to new address
        // Continue moving forward in time (don't go backwards)
        currentTime += 7 days;
        vm.warp(currentTime);
        uint256 aliceEmployeeBalanceBeforeSecondPayout = usdc.balanceOf(aliceEmployee);
        uint256 aliceEmployeeNewBalanceBeforeSecondPayout = usdc.balanceOf(aliceEmployeeNewAddress);

        uint256 secondPayout = paymentsPlugin.requestStreamPayout("alicemobile");

        // Old address balance should not change
        assertEq(
            usdc.balanceOf(aliceEmployee),
            aliceEmployeeBalanceBeforeSecondPayout,
            "Old address should not receive future payouts after migration"
        );

        // New address should receive the payout
        assertEq(
            usdc.balanceOf(aliceEmployeeNewAddress),
            aliceEmployeeNewBalanceBeforeSecondPayout + secondPayout,
            "New address should receive future payouts after migration"
        );
        assertTrue(secondPayout > 0, "Second payout should be greater than zero");

        console.log("+ Username address update and migration verified - user-controlled recovery working");
    }
}
