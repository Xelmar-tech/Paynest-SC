// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import {AddressRegistryV1} from "../src/v1/AddressRegistryV1.sol";
import {PaymentsPluginV1Setup} from "../src/v1/setup/PaymentsPluginV1Setup.sol";
import {PayNestDAOFactory} from "../src/v1/factory/PayNestDAOFactory.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";

/**
 * @title PayNest Deployment Script
 * @notice This script performs a complete PayNest ecosystem deployment:
 * - Deploys AddressRegistry (username mapping system)
 * - Deploys PaymentsPluginSetup and creates plugin repository
 * - Deploys PayNestDAOFactory for streamlined DAO creation
 * - Outputs all deployment information for integration
 */
contract DeployPayNestScript is Script {
    address deployer;
    PluginRepoFactory pluginRepoFactory;
    DAOFactory daoFactory;
    string pluginEnsSubdomain;
    address pluginRepoMaintainerAddress;
    address llamaPayFactory;

    // Deployment artifacts
    AddressRegistryV1 public addressRegistry;
    PaymentsPluginV1Setup public paymentsPluginSetup;
    PluginRepo public paymentsPluginRepo;
    PayNestDAOFactory public payNestDAOFactory;

    modifier broadcast() {
        uint256 privKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
        vm.startBroadcast(privKey);

        deployer = vm.addr(privKey);
        console2.log("PayNest Deployment");
        console2.log("- Deploying from:   ", deployer);
        console2.log("- Chain ID:         ", block.chainid);
        console2.log("- Network:          ", vm.envString("NETWORK_NAME"));
        console2.log("");

        _;

        vm.stopBroadcast();
    }

    function setUp() public {
        // Load Aragon OSx factory addresses
        pluginRepoFactory = PluginRepoFactory(vm.envAddress("PLUGIN_REPO_FACTORY_ADDRESS"));
        daoFactory = DAOFactory(vm.envAddress("DAO_FACTORY_ADDRESS"));
        llamaPayFactory = vm.envAddress("LLAMAPAY_FACTORY_BASE");

        // Load existing AddressRegistry deployment
        address existingRegistry = vm.envOr("ADDRESS_REGISTRY", address(0));
        if (existingRegistry != address(0)) {
            addressRegistry = AddressRegistryV1(existingRegistry);
            console2.log("Using existing AddressRegistry at:", address(addressRegistry));
        }

        vm.label(address(pluginRepoFactory), "PluginRepoFactory");
        vm.label(address(daoFactory), "DAOFactory");
        vm.label(llamaPayFactory, "LlamaPayFactory");

        // Plugin configuration
        pluginEnsSubdomain = vm.envOr("PLUGIN_ENS_SUBDOMAIN", string(""));

        // Generate random subdomain if empty
        if (bytes(pluginEnsSubdomain).length == 0) {
            pluginEnsSubdomain = string.concat("paynest-payments-", vm.toString(block.timestamp));
        }

        // Use deployer as maintainer if not specified
        pluginRepoMaintainerAddress = vm.envOr("PLUGIN_REPO_MAINTAINER_ADDRESS", deployer);
        if (pluginRepoMaintainerAddress == address(0)) {
            pluginRepoMaintainerAddress = deployer;
        }

        vm.label(pluginRepoMaintainerAddress, "PluginMaintainer");
    }

    function run() public broadcast {
        console2.log("=== Deploying PayNest Ecosystem ===");
        console2.log("");

        // Step 1: Deploy AddressRegistry
        deployAddressRegistry();

        // Step 2: Deploy PaymentsPlugin infrastructure
        deployPaymentsPlugin();

        // Step 3: Deploy PayNestDAOFactory
        deployPayNestDAOFactory();

        // Output deployment summary
        printDeployment();

        // Save deployment artifacts
        saveDeploymentArtifacts();
    }

    function deployAddressRegistry() public {
        console2.log("1. AddressRegistry Setup...");

        if (address(addressRegistry) != address(0)) {
            console2.log("   - Using existing AddressRegistry at:", address(addressRegistry));
        } else {
            console2.log("   - Deploying new AddressRegistry...");
            // Deploy as UUPS proxy for upgradeability
            addressRegistry = AddressRegistryV1(ProxyLib.deployUUPSProxy(address(new AddressRegistryV1()), ""));
            console2.log("   - AddressRegistry deployed at:", address(addressRegistry));
        }

        vm.label(address(addressRegistry), "AddressRegistry");
        console2.log("");
    }

    function deployPaymentsPlugin() public {
        console2.log("2. Deploying PaymentsPlugin infrastructure...");

        // Deploy PaymentsPluginSetup
        paymentsPluginSetup = new PaymentsPluginV1Setup();
        vm.label(address(paymentsPluginSetup), "PaymentsPluginSetup");
        console2.log("   - PaymentsPluginSetup deployed at:", address(paymentsPluginSetup));

        // Create plugin repository with first version
        paymentsPluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion(
            pluginEnsSubdomain,
            address(paymentsPluginSetup),
            pluginRepoMaintainerAddress,
            "PayNest Payments Plugin - Streaming and scheduled payments with username addressing",
            "Initial release of PayNest payments plugin with LlamaPay integration"
        );

        vm.label(address(paymentsPluginRepo), "PaymentsPluginRepo");
        console2.log("   - PaymentsPluginRepo deployed at:", address(paymentsPluginRepo));
        console2.log("   - Plugin ENS domain:", string.concat(pluginEnsSubdomain, ".plugin.dao.eth"));
        console2.log("");
    }

    function deployPayNestDAOFactory() public {
        console2.log("3. Deploying PayNestDAOFactory...");

        // Use the official Aragon Admin plugin repository
        PluginRepo adminPluginRepo = PluginRepo(vm.envAddress("ADMIN_PLUGIN_REPO"));

        payNestDAOFactory =
            new PayNestDAOFactory(addressRegistry, daoFactory, adminPluginRepo, paymentsPluginRepo, llamaPayFactory);

        vm.label(address(payNestDAOFactory), "PayNestDAOFactory");
        console2.log("   - PayNestDAOFactory deployed at:", address(payNestDAOFactory));
        console2.log("   - Using Admin Plugin Repo:      ", address(adminPluginRepo));
        console2.log("");
    }

    function printDeployment() public view {
        console2.log("=== PayNest Deployment Summary ===");
        console2.log("");

        console2.log("Core Infrastructure:");
        console2.log("- AddressRegistry:           ", address(addressRegistry));
        console2.log("- PayNestDAOFactory:         ", address(payNestDAOFactory));
        console2.log("");

        console2.log("PaymentsPlugin:");
        console2.log("- Plugin Setup:              ", address(paymentsPluginSetup));
        console2.log("- Plugin Repository:         ", address(paymentsPluginRepo));
        console2.log("- Plugin Maintainer:         ", pluginRepoMaintainerAddress);
        console2.log("- Plugin ENS:                ", string.concat(pluginEnsSubdomain, ".plugin.dao.eth"));
        console2.log("");

        console2.log("Integration Points:");
        console2.log("- LlamaPay Factory:          ", llamaPayFactory);
        console2.log("- Aragon DAO Factory:        ", address(daoFactory));
        console2.log("- Aragon Plugin Repo Factory:", address(pluginRepoFactory));
        console2.log("");

        console2.log("Deployment Details:");
        console2.log("- Deployer Address:          ", deployer);
        console2.log("- Network:                   ", vm.envString("NETWORK_NAME"));
        console2.log("- Chain ID:                  ", block.chainid);
        console2.log("- Block Number:              ", block.number);
        console2.log("- Timestamp:                 ", block.timestamp);
        console2.log("");
    }

    function saveDeploymentArtifacts() public {
        // Create deployment JSON for integration
        string memory deploymentJson = string.concat(
            "{\n",
            '  "network": "',
            vm.envString("NETWORK_NAME"),
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
            '",\n',
            '    "PaymentsPluginSetup": "',
            vm.toString(address(paymentsPluginSetup)),
            '",\n',
            '    "PaymentsPluginRepo": "',
            vm.toString(address(paymentsPluginRepo)),
            '",\n',
            '    "PayNestDAOFactory": "',
            vm.toString(address(payNestDAOFactory)),
            '",\n',
            '    "LlamaPayFactory": "',
            vm.toString(llamaPayFactory),
            '",\n',
            '    "DAOFactory": "',
            vm.toString(address(daoFactory)),
            '",\n',
            '    "PluginRepoFactory": "',
            vm.toString(address(pluginRepoFactory)),
            '"\n',
            "  },\n",
            '  "pluginInfo": {\n',
            '    "ensSubdomain": "',
            pluginEnsSubdomain,
            '",\n',
            '    "ensDomain": "',
            string.concat(pluginEnsSubdomain, ".plugin.dao.eth"),
            '",\n',
            '    "maintainer": "',
            vm.toString(pluginRepoMaintainerAddress),
            '"\n',
            "  }\n",
            "}"
        );

        // Write to artifacts folder
        string memory artifactPath = string.concat(
            "./artifacts/paynest-deployment-", vm.envString("NETWORK_NAME"), "-", vm.toString(block.timestamp), ".json"
        );

        vm.writeFile(artifactPath, deploymentJson);
        console2.log("Deployment artifacts saved to:", artifactPath);
    }
}
