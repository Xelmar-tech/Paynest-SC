// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Org.sol";
import "../src/factory/Paynest.sol";
import "../src/AddressRegistry.sol";
import "../src/util/Errors.sol";
import {ERC20 as OZERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is OZERC20 {
    constructor() OZERC20("Mock", "MCK") {
        _mint(msg.sender, 1e24);
    }
}

contract OrgTest is Test {
    Org public org;
    Registry public registry;
    Paynest public paynest;
    MockERC20 public token;
    address public owner = address(0xA11CE);
    address public user = address(0xB0B);
    string public username = "bob";

    function setUp() public {
        registry = new Registry();
        paynest = new Paynest(address(registry));
        vm.prank(owner);

        address orgAddr = paynest.deployOrg("Bob company");
        org = Org(payable(orgAddr));

        token = new MockERC20();
        vm.deal(orgAddr, 100 ether);
        token.transfer(orgAddr, 1e24);
    }

    function testCreateScheduleRevertsIfNotOwner() public {
        vm.expectRevert();
        org.createSchedule(
            username,
            1 ether,
            address(token),
            IPayments.IntervalType.Monthly,
            false,
            uint40(block.timestamp + 1)
        );
    }

    function testCreateScheduleRevertsIfUsernameInvalid() public {
        vm.prank(owner);
        vm.expectRevert(); // Username doesn't exist
        org.createSchedule(
            "nonexistent",
            1 ether,
            address(token),
            IPayments.IntervalType.Monthly,
            false,
            uint40(block.timestamp + 1)
        );
    }

    function testCreateScheduleSuccess() public {
        vm.startPrank(user);
        registry.claimUsername(username);
        registry.updateUserAddress(username, user);
        vm.stopPrank();

        vm.prank(owner);
        org.createSchedule(
            username,
            1 ether,
            address(token),
            IPayments.IntervalType.Monthly,
            false,
            uint40(block.timestamp + 100)
        );

        Org.Schedule memory schedule = org.getSchedule(username);
        bool isOneTime = schedule.isOneTime;
        bool active = schedule.active;
        uint256 amount = schedule.amount;

        assertEq(amount, 1 ether);
        assertTrue(active);
        assertEq(isOneTime, false);
    }

    function testSchedulePayoutFailsBeforeDue() public {
        vm.startPrank(user);
        registry.claimUsername(username);
        registry.updateUserAddress(username, user);
        vm.stopPrank();

        vm.prank(owner);
        org.createSchedule(
            username,
            1 ether,
            address(token),
            IPayments.IntervalType.Monthly,
            false,
            uint40(block.timestamp + 100)
        );

        vm.expectRevert();
        org.requestSchedulePayout(username);
    }

    function testSchedulePayoutAfterTime() public {
        vm.startPrank(user);
        registry.claimUsername(username);
        registry.updateUserAddress(username, user);
        vm.stopPrank();

        vm.startPrank(owner);
        org.createSchedule(
            username,
            1 ether,
            address(token),
            IPayments.IntervalType.Monthly,
            false,
            uint40(block.timestamp + 100)
        );

        skip(150); // Fast-forward
        org.requestSchedulePayout(username);
        vm.stopPrank();

        Org.Schedule memory schedule = org.getSchedule(username);
        bool isOneTime = schedule.isOneTime;
        bool active = schedule.active;
        uint256 amount = schedule.amount;

        assertTrue(active);
        assertEq(amount, 1 ether);
        assertEq(isOneTime, false);
    }

    function testCreateStreamAndPayout() public {
        vm.startPrank(user);
        registry.claimUsername(username);
        registry.updateUserAddress(username, user);
        vm.stopPrank();

        uint40 end = uint40(block.timestamp + 12 weeks);
        vm.prank(owner);
        org.createStream(username, 20000, address(token), end);

        skip(2 days);

        uint256 payout = org.requestStreamPayout(username);
        assertGt(payout, 0);
    }

    function testCancelScheduleWithNoIncompletePayout() public {
        vm.startPrank(user);
        registry.claimUsername(username);
        registry.updateUserAddress(username, user);
        vm.stopPrank();

        vm.prank(owner);
        org.createSchedule(
            username,
            1 ether,
            address(token),
            IPayments.IntervalType.Monthly,
            false,
            uint40(block.timestamp + 10)
        );
        skip(5 days);

        vm.prank(owner);
        org.cancelSchedule(username);
    }

    function testEditStreamChangesAmount() public {
        vm.startPrank(user);
        registry.claimUsername(username);
        registry.updateUserAddress(username, user);
        vm.stopPrank();

        vm.startPrank(owner);
        uint40 end = uint40(block.timestamp + 7 days);
        org.createStream(username, 10000, address(token), end);

        skip(1 days);
        org.editStream(username, 20000);
        vm.stopPrank();

        Org.Stream memory stream = org.getStream(username);
        uint256 newAmount = stream.amount;
        assertEq(newAmount, 20000);
    }

    function testEditScheduleRevertsNearPayoutTime() public {
        vm.startPrank(user);
        registry.claimUsername(username);
        registry.updateUserAddress(username, user);
        vm.stopPrank();

        vm.startPrank(owner);
        org.createSchedule(
            username,
            1 ether,
            address(token),
            IPayments.IntervalType.Monthly,
            false,
            uint40(block.timestamp + 1 days)
        );
        skip(28 days); // within 3-day window
        vm.expectRevert();
        org.editSchedule(username, 2 ether);
        vm.stopPrank();
    }
}
