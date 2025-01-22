// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/core/Paynest.sol";
import "../src/core/AddressRegistry.sol";
import "../src/core/Organization.sol";
import "../src/utils/Errors.sol";
import "../src/interfaces/IOrg.sol";

contract OrganizationTest is Test {
    //     Paynest private paynest;
    //     Registry private registry;
    //     Organization private organization;
    //     address private owner;
    //     address private user;
    //     address private token;
    //     function setUp() public {
    //         owner = vm.addr(1);
    //         user = vm.addr(2);
    //         token = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    //         // Deploy Registry and Paynest
    //         registry = new Registry();
    //         paynest = new Paynest();
    //         // Deploy Organization via Paynest
    //         vm.prank(address(paynest)); // Simulate call from Paynest
    //         organization = new Organization(owner, "Test Org");
    //         // Register user in the registry
    //         registry.updateUserAddress("testuser", user);
    //         // Add token support in Paynest
    //         vm.prank(address(paynest));
    //         paynest.addTokenSupport(token);
    //     }
    //     function testUpdateOrgName() public {
    //         vm.prank(owner);
    //         organization.updateOrgName("Updated Org Name");
    //     }
    //     function testCreateSchedule() public {
    //         vm.prank(owner);
    //         organization.createSchedule("testuser", 1000, token, uint40(block.timestamp + 30 days));
    //         // Expect the PaymentScheduleActive event
    //         vm.expectEmit(true, true, true, true);
    //         emit IOrg.PaymentScheduleActive("testuser", token, uint40(block.timestamp + 30 days), 1000);
    //     }
    //     function testCreateStream() public {
    //         vm.prank(owner);
    //         organization.createStream("testuser", 1000, token, uint40(block.timestamp + 90 days));
    //         // Expect the PaymentStreamActive event
    //         vm.expectEmit(true, true, true, true);
    //         emit IOrg.PaymentStreamActive("testuser", token, uint40(block.timestamp), 1000);
    //     }
    //     function testCancelStream() public {
    //         vm.startPrank(owner);
    //         organization.createStream("testuser", 1000, token, uint40(block.timestamp + 90 days));
    //         organization.cancelStream("testuser");
    //         // Expect the PaymentStreamCancelled event
    //         vm.expectEmit(true, true, true, true);
    //         emit IOrg.PaymentStreamCancelled("testuser");
    //         vm.stopPrank();
    //     }
    //     function testRequestSchedulePayout() public {
    //         vm.startPrank(owner);
    //         organization.createSchedule("testuser", 1000, token, uint40(block.timestamp + 30 days));
    //         vm.warp(block.timestamp + 31 days); // Advance time by 31 days
    //         vm.stopPrank();
    //         vm.prank(user);
    //         organization.requestSchedulePayout("testuser");
    //         // Expect the Payout event
    //         vm.expectEmit(true, true, true, true);
    //         emit IOrg.Payout("testuser", token, 1000);
    //     }
    //     function testFailTokenNotSupported() public {
    //         vm.prank(owner);
    //         vm.expectRevert(abi.encodeWithSelector(Errors.TokenNotSupported.selector));
    //         organization.createSchedule("testuser", 1000, address(0xdead), uint40(block.timestamp + 30 days));
    //     }
    //     function testFailActivePayment() public {
    //         vm.startPrank(owner);
    //         organization.createSchedule("testuser", 1000, token, uint40(block.timestamp + 30 days));
    //         vm.expectRevert(abi.encodeWithSelector(Errors.ActivePayment.selector, "testuser"));
    //         organization.createSchedule("testuser", 500, token, uint40(block.timestamp + 60 days));
    //         vm.stopPrank();
    //     }
    //     function testEmergencyWithdraw() public {
    //         vm.prank(owner);
    //         paynest.removeTokenSupport(token);
    //         vm.startPrank(owner);
    //         organization.emergencyWithdraw(token);
    //         // Expect the safe transfer of funds
    //     }
}
