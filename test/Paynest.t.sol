// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/core/Paynest.sol";
import "../src/interfaces/IPaynest.sol";
import "../src/utils/Errors.sol";

contract PaynestTest is Test {
    Paynest public paynest;
    address public owner;
    address public nonOwner;
    address public token1;
    address public token2;

    
    receive() external payable {}

    function setUp() public {
        owner = address(this); 
        nonOwner = address(0x1); // A non-owner address
        token1 = address(0x2); // Token address 1
        token2 = address(0x3); // Token address 2
        paynest = new Paynest();
    }

    function test_AddTokenSupportByOwner() public {
        // Add a supported token as the owner
        vm.prank(owner);
        paynest.addTokenSupport(token1);

        // Verify token1 is supported
        bool isSupported = paynest.isSupportedToken(token1);
        assertTrue(isSupported, "Token1 should be supported");
    }

    function test_FailAddTokenSupportByNonOwner() public {
        // Attempt to add token support as a non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        paynest.addTokenSupport(token1);
    }

    function test_FailAddExistingToken() public {
        // Add token1 as the owner
        vm.prank(owner);
        paynest.addTokenSupport(token1);

        // Attempt to add the same token again
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenAlreadySupported.selector));
        paynest.addTokenSupport(token1);
    }

    function test_RemoveTokenSupportByOwner() public {
        // Add and then remove token1 as the owner
        vm.prank(owner);
        paynest.addTokenSupport(token1);

        vm.prank(owner);
        paynest.removeTokenSupport(token1);

        // Verify token1 is no longer supported
        bool isSupported = paynest.isSupportedToken(token1);
        assertFalse(isSupported, "Token1 should not be supported");
    }

    function test_FailRemoveUnsupportedToken() public {
        // Attempt to remove a token that hasn't been added
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenNotSupported.selector));
        paynest.removeTokenSupport(token1);
    }

    function test_DeployOrganization() public {
        string memory orgName = "Test Organization";

        // Deploy a new organization
        vm.prank(owner);
        paynest.deployOrganization(orgName);
    }

    function test_RedeemSubscriptionFees() public {
        // Send ETH to the Paynest contract
        uint256 amount = 1 ether;
        vm.deal(address(paynest), amount);

        // Verify balance before redeeming
        assertEq(address(paynest).balance, amount, "Paynest balance mismatch");

        // Redeem fees as the owner
        vm.prank(owner);
        paynest.redeemSubscriptionFees();

        // Verify the owner's balance increased
        assertGe(owner.balance, amount, "Owner balance less than claimed fees");
    }

    function test_FailRedeemZeroBalance() public {
        // Attempt to redeem fees with zero balance
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector));
        paynest.redeemSubscriptionFees();
    }

    function test_CanEmergencyWithdraw() public {
        vm.prank(owner);
        paynest.addTokenSupport(token2);
        // Verify emergency withdrawal conditions
        bool canWithdrawUnsupported = paynest.canEmergencyWithdraw(owner, token1);
        bool cannotWithdrawSupported = paynest.canEmergencyWithdraw(owner, token2);

        assertTrue(canWithdrawUnsupported, "Owner should be able to withdraw unsupported tokens");
        assertFalse(cannotWithdrawSupported, "Owner should not be able to withdraw supported tokens");
    }

    function test_GetFixedFee() public view {
        // Get the fixed fee (expected to be zero initially)
        uint fixedFee = paynest.getFixedFee();
        assertEq(fixedFee, 0, "Initial fixed fee should be 0");
    }
}
