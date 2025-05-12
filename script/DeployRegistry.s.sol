// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console} from "forge-std/Script.sol";
import {Registry} from "../src/AddressRegistry.sol";

contract DeployRegistry is Script {
    function run() public {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);
        console.log("Deploying from:", vm.addr(privKey));

        // Deploy the address registry
        Registry registry = new Registry();
        console.log("AddressRegistry deployed at:", address(registry));

        vm.stopBroadcast();

        // Print summary
        console.log("\nDeployment Summary");
        console.log("------------------");
        console.log("Chain ID:", block.chainid);
        console.log("AddressRegistry:", address(registry));
    }
}
