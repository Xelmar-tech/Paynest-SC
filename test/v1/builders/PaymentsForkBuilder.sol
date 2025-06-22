// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import {ForkTestBase} from "../lib/ForkTestBase.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PaymentsPluginV1} from "../../../src/v1/PaymentsPluginV1.sol";
import {PaymentsPluginV1Setup} from "../../../src/v1/setup/PaymentsPluginV1Setup.sol";
import {AddressRegistryV1} from "../../../src/v1/AddressRegistryV1.sol";
import {ILlamaPayFactory} from "../../../src/v1/interfaces/ILlamaPay.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {NON_EMPTY_BYTES} from "../lib/constants.sol";

contract PaymentsForkBuilder is ForkTestBase {
    address immutable DAO_BASE = address(new DAO());
    address immutable PAYMENTS_PLUGIN_BASE = address(new PaymentsPluginV1());

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

    function withManager(address _manager) public returns (PaymentsForkBuilder) {
        manager = _manager;
        return this;
    }

    function withRegistry(address _registry) public returns (PaymentsForkBuilder) {
        registryAddress = _registry;
        return this;
    }

    function withLlamaPayFactory(address _factory) public returns (PaymentsForkBuilder) {
        llamaPayFactoryAddress = _factory;
        return this;
    }

    function withToken(address _token) public returns (PaymentsForkBuilder) {
        tokenAddress = _token;
        return this;
    }

    function withWhale(address _whale) public returns (PaymentsForkBuilder) {
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
            PaymentsPluginV1Setup pluginSetup,
            PaymentsPluginV1 plugin,
            AddressRegistryV1 registry,
            ILlamaPayFactory llamaPayFactory,
            IERC20 token
        )
    {
        // Deploy or use provided registry
        if (registryAddress == address(0)) {
            registry = AddressRegistryV1(ProxyLib.deployUUPSProxy(address(new AddressRegistryV1()), ""));
            registryAddress = address(registry);
        } else {
            registry = AddressRegistryV1(registryAddress);
        }

        // Use real LlamaPay factory and token
        llamaPayFactory = ILlamaPayFactory(llamaPayFactoryAddress);
        token = IERC20(tokenAddress);

        // Prepare a plugin repo with an initial version and subdomain
        string memory pluginRepoSubdomain = string.concat("payments-plugin-", vm.toString(block.timestamp));
        pluginSetup = new PaymentsPluginV1Setup();
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
            daoURI: "http://paynest/",
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
        plugin = PaymentsPluginV1(installedPlugins[0].plugin);

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
