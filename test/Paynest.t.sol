// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Paynest} from "../src/factory/Paynest.sol";
import {Org} from "../src/Org.sol";

contract PaynestDAOTest is Test {
    Paynest paynest;
    address owner;

    function setUp() public {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        console.log("Start");
        owner = vm.addr(privKey);

        paynest = new Paynest(owner);
    }

    function testCreateDao() public {
        address deployment = paynest.deployOrg("Xelmar");

        console.log(deployment);
    }
}
