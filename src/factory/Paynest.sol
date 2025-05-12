// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../Org.sol";
import "../interfaces/IRegistry.sol";

contract Paynest {
    event OrgDeployed(
        address indexed orgAddress,
        string orgName,
        address deployer
    );
    IRegistry private immutable Registry;

    constructor(address registryAddress) {
        Registry = IRegistry(registryAddress);
    }

    receive() external payable {}

    function deployOrg(
        string calldata orgName
    ) external returns (address orgAddress) {
        orgAddress = address(new Org(msg.sender, orgName));
        emit OrgDeployed(orgAddress, orgName, msg.sender);
    }

    function getRegistry() public view returns (address) {
        return address(Registry);
    }
}
