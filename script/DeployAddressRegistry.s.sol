// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {AddressRegistryV1} from "../src/v1/AddressRegistryV1.sol";

/**
 * This script deploys the AddressRegistry contract using CREATE2 for deterministic addresses
 * across networks. The registry provides global username-to-address mapping for PayNest.
 */
contract DeployAddressRegistryScript is Script {
    address deployer;
    AddressRegistryV1 addressRegistry;

    // Salt for CREATE2 deployment (deterministic address)
    bytes32 constant SALT = keccak256("PayNest.AddressRegistry.v1.0.0");

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);

        deployer = vm.addr(privKey);
        console2.log("AddressRegistry Deployment");
        console2.log("- Deploying from:   ", deployer);
        console2.log("- Chain ID:         ", block.chainid);
        console2.log("- Network:          ", vm.envString("NETWORK_NAME"));
        console2.log("");

        _;

        vm.stopBroadcast();
    }

    function run() public broadcast {
        deployAddressRegistry();
        printDeployment();
        saveDeploymentArtifacts();
    }

    function deployAddressRegistry() public {
        console2.log("Deploying AddressRegistry...");

        // Deploy using CREATE2 for deterministic address
        addressRegistry = new AddressRegistryV1{salt: SALT}();

        console2.log("[SUCCESS] AddressRegistry deployed to:", address(addressRegistry));
        console2.log("");
    }

    function printDeployment() public view {
        console2.log("=== DEPLOYMENT SUMMARY ===");
        console2.log("");
        console2.log("AddressRegistry:");
        console2.log("- Contract Address:  ", address(addressRegistry));
        console2.log("- Deployer:          ", deployer);
        console2.log("- Block Number:      ", block.number);
        console2.log("- Network:           ", vm.envString("NETWORK_NAME"));
        console2.log("- Chain ID:          ", block.chainid);
        console2.log("");
        console2.log("[SUCCESS] Deployment Complete!");
        console2.log("");
    }

    function saveDeploymentArtifacts() public {
        // Create deployment artifact
        string memory networkName = vm.envString("NETWORK_NAME");
        string memory timestamp = vm.toString(block.timestamp);
        string memory filename =
            string.concat("./artifacts/address-registry-deployment-", networkName, "-", timestamp, ".json");

        string memory json = string.concat(
            "{\n",
            '  "network": "',
            networkName,
            '",\n',
            '  "chainId": ',
            vm.toString(block.chainid),
            ",\n",
            '  "deployer": "',
            vm.toString(deployer),
            '",\n',
            '  "timestamp": ',
            vm.toString(block.timestamp),
            ",\n",
            '  "blockNumber": ',
            vm.toString(block.number),
            ",\n",
            '  "contracts": {\n',
            '    "AddressRegistry": "',
            vm.toString(address(addressRegistry)),
            '"\n',
            "  }\n",
            "}"
        );

        vm.writeFile(filename, json);
        console2.log("[SAVED] Deployment artifact saved to:", filename);
    }
}
