// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {ForkTestBaseV2} from "../lib/ForkTestBaseV2.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PaymentsPlugin} from "../../../src/v2/PaymentsPlugin.sol";
import {PaymentsPluginSetup} from "../../../src/v2/setup/PaymentsPluginSetup.sol";
import {AddressRegistry} from "../../../src/v2/AddressRegistry.sol";
import {ILlamaPayFactory} from "../../../src/v2/interfaces/ILlamaPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {NON_EMPTY_BYTES} from "../../v1/lib/constants.sol";

contract PaymentsForkBuilderV2 is ForkTestBaseV2 {
    address immutable DAO_BASE = address(new DAO());
    address immutable PAYMENTS_PLUGIN_BASE = address(new PaymentsPlugin());

    // Add your own parameters here
    address manager = bob;
    address registryAddress;
    address llamaPayFactoryAddress;
    address tokenAddress;
    address whaleAddress;

    // Environmental variables from .env
    address constant LLAMAPAY_FACTORY_BASE = 0x09c39B8311e4B7c678cBDAD76556877ecD3aEa07;
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDC_WHALE = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;

    constructor() {
        // Default to Base mainnet addresses
        withLlamaPayFactory(LLAMAPAY_FACTORY_BASE);
        withToken(USDC_BASE);
        withWhale(USDC_WHALE);
    }

    function withManager(address _manager) public returns (PaymentsForkBuilderV2) {
        manager = _manager;
        return this;
    }

    function withRegistry(address _registry) public returns (PaymentsForkBuilderV2) {
        registryAddress = _registry;
        return this;
    }

    function withLlamaPayFactory(address _factory) public returns (PaymentsForkBuilderV2) {
        llamaPayFactoryAddress = _factory;
        return this;
    }

    function withToken(address _token) public returns (PaymentsForkBuilderV2) {
        tokenAddress = _token;
        return this;
    }

    function withWhale(address _whale) public returns (PaymentsForkBuilderV2) {
        whaleAddress = _whale;
        return this;
    }

    /// @dev Creates a DAO with the PaymentsPlugin using the same pattern as boilerplate
    /// @dev Uses real DAOFactory and PluginRepoFactory from environment variables
    function build()
        public
        returns (
            DAO dao,
            PluginRepo pluginRepo,
            PaymentsPluginSetup pluginSetup,
            PaymentsPlugin plugin,
            AddressRegistry registry,
            ILlamaPayFactory llamaPayFactory,
            IERC20 token
        )
    {
        // Deploy or use provided registry
        if (registryAddress == address(0)) {
            registry = AddressRegistry(ProxyLib.deployUUPSProxy(address(new AddressRegistry()), ""));
            registryAddress = address(registry);
        } else {
            registry = AddressRegistry(registryAddress);
        }

        // Use real LlamaPay factory and token
        llamaPayFactory = ILlamaPayFactory(llamaPayFactoryAddress);
        token = IERC20(tokenAddress);

        // Prepare a plugin repo with an initial version and subdomain
        string memory pluginRepoSubdomain = string.concat("payments-plugin-v2-", vm.toString(block.timestamp));
        pluginSetup = new PaymentsPluginSetup();
        pluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion({
            _subdomain: string(pluginRepoSubdomain),
            _pluginSetup: address(pluginSetup),
            _maintainer: address(this),
            _releaseMetadata: NON_EMPTY_BYTES,
            _buildMetadata: NON_EMPTY_BYTES
        });

        // DAO settings
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
            trustedForwarder: address(0),
            daoURI: "http://paynest-v2/",
            subdomain: "",
            metadata: ""
        });

        // Define what plugin(s) to install and give the corresponding parameters
        DAOFactory.PluginSettings[] memory installSettings = new DAOFactory.PluginSettings[](1);

        bytes memory pluginInstallData =
            pluginSetup.encodeInstallationParams(manager, registryAddress, llamaPayFactoryAddress);
        installSettings[0] = DAOFactory.PluginSettings({
            pluginSetupRef: PluginSetupRef({versionTag: getLatestTag(pluginRepo), pluginSetupRepo: pluginRepo}),
            data: pluginInstallData
        });

        // Create DAO with the plugin
        DAOFactory.InstalledPlugin[] memory installedPlugins;
        (dao, installedPlugins) = daoFactory.createDao(daoSettings, installSettings);
        plugin = PaymentsPlugin(installedPlugins[0].plugin);

        // Fund the DAO with tokens from whale
        vm.startPrank(whaleAddress);
        uint256 whaleBalance = token.balanceOf(whaleAddress);
        require(whaleBalance >= 10000e6, "Whale has insufficient balance");
        token.transfer(address(dao), 10000e6); // 10,000 USDC
        vm.stopPrank();

        // Labels
        vm.label(address(dao), "DAO");
        vm.label(address(plugin), "PaymentsPlugin");
        vm.label(address(registry), "AddressRegistry");
        vm.label(address(llamaPayFactory), "LlamaPayFactory");
        vm.label(address(token), "USDC");
        vm.label(whaleAddress, "USDC_WHALE");

        // Moving forward to avoid collisions
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}
