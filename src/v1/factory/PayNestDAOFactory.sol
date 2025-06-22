// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {AddressRegistryV1} from "../AddressRegistryV1.sol";

/// @title PayNest DAO Factory
/// @notice Creates fully configured Aragon DAOs with both Admin plugin and PayNest plugin installed in a single transaction
/// @dev Provides a streamlined way to deploy payment-enabled DAOs for the PayNest ecosystem
contract PayNestDAOFactory {
    /// @notice Shared AddressRegistry for all PayNest DAOs
    AddressRegistryV1 public immutable addressRegistry;

    /// @notice Aragon DAO factory for creating DAOs
    DAOFactory public immutable daoFactory;

    /// @notice Plugin repository for Admin plugin
    PluginRepo public immutable adminPluginRepo;

    /// @notice Plugin repository for PayNest plugin
    PluginRepo public immutable paymentsPluginRepo;

    /// @notice LlamaPay factory address for streaming payments
    address public immutable llamaPayFactory;

    /// @notice DAO deployment information
    mapping(address dao => DAOInfo) public daoInfo;

    /// @notice Track all created DAOs
    address[] public createdDAOs;

    /// @notice DAO deployment information structure
    /// @param admin The admin address who controls the DAO
    /// @param adminPlugin The address of the installed Admin plugin
    /// @param paymentsPlugin The address of the installed PayNest plugin
    /// @param createdAt Timestamp when the DAO was created
    struct DAOInfo {
        address admin;
        address adminPlugin;
        address paymentsPlugin;
        uint256 createdAt;
    }

    /// @notice Emitted when a new PayNest DAO is created
    /// @param dao The address of the created DAO
    /// @param admin The admin address who controls the DAO
    /// @param adminPlugin The address of the installed Admin plugin
    /// @param paymentsPlugin The address of the installed PayNest plugin
    /// @param daoName The name of the created DAO
    event PayNestDAOCreated(
        address indexed dao, address indexed admin, address adminPlugin, address paymentsPlugin, string daoName
    );

    /// @notice Admin address cannot be zero
    error AdminAddressZero();

    /// @notice DAO name cannot be empty
    error DAONameEmpty();

    /// @notice DAO creation failed
    error DAOCreationFailed();

    /// @notice Plugin installation failed
    error PluginInstallationFailed();

    /// @notice Constructs the PayNest DAO Factory
    /// @param _addressRegistry Deployed AddressRegistry contract
    /// @param _daoFactory Aragon's DAOFactory contract
    /// @param _adminPluginRepo Aragon's Admin plugin repository
    /// @param _paymentsPluginRepo PayNest plugin repository
    /// @param _llamaPayFactory LlamaPay factory address for streaming payments
    constructor(
        AddressRegistryV1 _addressRegistry,
        DAOFactory _daoFactory,
        PluginRepo _adminPluginRepo,
        PluginRepo _paymentsPluginRepo,
        address _llamaPayFactory
    ) {
        if (address(_addressRegistry) == address(0)) revert AdminAddressZero();
        if (address(_daoFactory) == address(0)) revert AdminAddressZero();
        if (address(_adminPluginRepo) == address(0)) revert AdminAddressZero();
        if (address(_paymentsPluginRepo) == address(0)) revert AdminAddressZero();
        if (_llamaPayFactory == address(0)) revert AdminAddressZero();

        addressRegistry = _addressRegistry;
        daoFactory = _daoFactory;
        adminPluginRepo = _adminPluginRepo;
        paymentsPluginRepo = _paymentsPluginRepo;
        llamaPayFactory = _llamaPayFactory;
    }

    /// @notice Creates a fully configured PayNest DAO with both Admin and PayNest plugins
    /// @param admin The address that will have admin control over the DAO
    /// @param daoName The name of the DAO to create
    /// @return dao The address of the created DAO
    /// @return adminPlugin The address of the installed Admin plugin
    /// @return paymentsPlugin The address of the installed PayNest plugin
    function createPayNestDAO(address admin, string memory daoName)
        external
        returns (address dao, address adminPlugin, address paymentsPlugin)
    {
        // Input validation
        if (admin == address(0)) revert AdminAddressZero();
        if (bytes(daoName).length == 0) revert DAONameEmpty();

        // Prepare DAO settings
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
            trustedForwarder: address(0), // No meta-transactions
            daoURI: string.concat("https://paynest.xyz/dao/", daoName),
            subdomain: "", // No ENS subdomain
            metadata: abi.encode(daoName, block.timestamp)
        });

        // Prepare plugin installations
        DAOFactory.PluginSettings[] memory pluginSettings = new DAOFactory.PluginSettings[](2);

        // Admin Plugin Setup - admin gets single-owner control with DAO as execution target
        bytes memory adminPluginData = abi.encode(
            admin,
            IPlugin.TargetConfig({
                target: address(0), // Will be set to DAO address by setup contract
                operation: IPlugin.Operation.Call
            })
        );

        pluginSettings[0] = DAOFactory.PluginSettings({
            pluginSetupRef: PluginSetupRef({
                versionTag: adminPluginRepo.getLatestVersion(adminPluginRepo.latestRelease()).tag,
                pluginSetupRepo: adminPluginRepo
            }),
            data: adminPluginData
        });

        // PayNest Plugin Setup - uses shared registry and LlamaPay factory
        bytes memory paymentsPluginData = abi.encode(admin, address(addressRegistry), llamaPayFactory);

        pluginSettings[1] = DAOFactory.PluginSettings({
            pluginSetupRef: PluginSetupRef({
                versionTag: paymentsPluginRepo.getLatestVersion(paymentsPluginRepo.latestRelease()).tag,
                pluginSetupRepo: paymentsPluginRepo
            }),
            data: paymentsPluginData
        });

        // Create DAO with both plugins
        DAOFactory.InstalledPlugin[] memory installedPlugins;
        try daoFactory.createDao(daoSettings, pluginSettings) returns (
            DAO createdDao, DAOFactory.InstalledPlugin[] memory plugins
        ) {
            dao = address(createdDao);
            installedPlugins = plugins;
        } catch {
            revert DAOCreationFailed();
        }

        // Validate plugin installation
        if (installedPlugins.length != 2) revert PluginInstallationFailed();

        // Extract plugin addresses
        adminPlugin = installedPlugins[0].plugin;
        paymentsPlugin = installedPlugins[1].plugin;

        // Store DAO information
        daoInfo[dao] = DAOInfo({
            admin: admin,
            adminPlugin: adminPlugin,
            paymentsPlugin: paymentsPlugin,
            createdAt: block.timestamp
        });

        // Add to tracking array
        createdDAOs.push(dao);

        // Emit creation event
        emit PayNestDAOCreated(dao, admin, adminPlugin, paymentsPlugin, daoName);

        return (dao, adminPlugin, paymentsPlugin);
    }

    /// @notice Returns the shared AddressRegistry address
    /// @return The address of the shared AddressRegistry
    function getAddressRegistry() external view returns (address) {
        return address(addressRegistry);
    }

    /// @notice Returns DAO information for a given DAO address
    /// @param dao The DAO address to query
    /// @return DAOInfo struct containing admin, plugins, and creation time
    function getDAOInfo(address dao) external view returns (DAOInfo memory) {
        return daoInfo[dao];
    }

    /// @notice Returns the total number of created DAOs
    /// @return The count of DAOs created by this factory
    function getCreatedDAOsCount() external view returns (uint256) {
        return createdDAOs.length;
    }

    /// @notice Returns the DAO address at a specific index
    /// @param index The index in the created DAOs array
    /// @return The DAO address at the given index
    function getCreatedDAO(uint256 index) external view returns (address) {
        return createdDAOs[index];
    }
}
