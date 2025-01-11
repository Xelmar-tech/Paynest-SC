// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../interfaces/IPaynest.sol";
import "./Organization.sol";
import "../utils/Errors.sol";
import "../utils/Owner.sol";
import "../ext_lib/SafeTransferLib.sol";


contract Paynest is IPaynest, Owner, Errors {

    uint private fixedFee;
    mapping(address => bool) private tokenSupport;

    constructor() Owner(msg.sender){}

    receive() external payable {}

    function addTokenSupport(address tokenAddr) external override {
        onlyOwner();

        if (tokenSupport[tokenAddr]) revert TokenAlreadySupported();
        tokenSupport[tokenAddr] = true;
    }

    function removeTokenSupport(address tokenAddr) external override {
        onlyOwner();
        
        if (!tokenSupport[tokenAddr]) revert TokenNotSupported();
        tokenSupport[tokenAddr] = false;
    }

    function deployOrganization(string calldata orgName) external override {
        address orgAddress = address(new Organization(msg.sender, orgName));
        emit OrgDeployed(orgAddress, orgName);
    }

    function redeemSubscriptionFees() external override {
        onlyOwner();
        uint balance = address(this).balance;
        
        if(balance == 0) revert InvalidAmount();
        SafeTransferLib.safeTransferETH(msg.sender, balance);
    }

    function isSupportedToken(address token) external view override returns (bool) {
        return tokenSupport[token];
    }

    function canEmergencyWithdraw(address caller, address tokenAddr) external view override returns (bool) {
        return caller == owner && !tokenSupport[tokenAddr];
    }

    function getFixedFee() external view override returns (uint) {
        return fixedFee;
    }

    function updateFixedFee(uint fee) external override {
        onlyOwner();

        fixedFee = fee;
    }
}