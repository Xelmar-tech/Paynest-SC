// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {IDAO, DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IPluginSetup, PluginSetup, PermissionLib} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import {PaymentsPluginV1} from "../PaymentsPluginV1.sol";

/// @title PaymentsPluginV1Setup
/// @notice Setup contract for the PaymentsPluginV1 that handles installation and uninstallation
/// @dev Follows the standard Aragon plugin setup pattern with UUPS proxy deployment
contract PaymentsPluginV1Setup is PluginSetup {
    /// @notice Address of the PaymentsPlugin implementation contract
    address private immutable paymentsPluginImplementation;

    /// @notice Constructor that deploys the plugin implementation
    constructor() PluginSetup(address(new PaymentsPluginV1())) {
        paymentsPluginImplementation = implementation();
    }

    /// @notice Installation parameters structure
    struct InstallationParams {
        address managerAddress; // Who can manage payments
        address registryAddress; // Address registry contract
        address llamaPayFactory; // LlamaPay factory contract
    }

    /// @notice Prepare the installation of the plugin
    /// @param _dao The DAO address
    /// @param _installationParams Encoded installation parameters
    /// @return plugin The deployed plugin proxy address
    /// @return preparedSetupData The setup data including permissions
    function prepareInstallation(address _dao, bytes memory _installationParams)
        external
        returns (address plugin, PreparedSetupData memory preparedSetupData)
    {
        // Decode installation parameters
        (address managerAddress, address registryAddress, address llamaPayFactory) =
            decodeInstallationParams(_installationParams);

        // Validate parameters
        if (managerAddress == address(0)) revert InvalidManagerAddress();
        if (registryAddress == address(0)) revert InvalidRegistryAddress();
        if (llamaPayFactory == address(0)) revert InvalidLlamaPayFactory();

        // Deploy UUPS proxy of PaymentsPlugin
        plugin = ProxyLib.deployUUPSProxy(
            paymentsPluginImplementation,
            abi.encodeCall(PaymentsPluginV1.initialize, (IDAO(_dao), registryAddress, llamaPayFactory))
        );

        // Prepare permissions array
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](2);

        // Grant MANAGER_PERMISSION on plugin to manager address
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: managerAddress,
            condition: PermissionLib.NO_CONDITION,
            permissionId: PaymentsPluginV1(plugin).MANAGER_PERMISSION_ID()
        });

        // Grant EXECUTE_PERMISSION on DAO to plugin
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });

        preparedSetupData.permissions = permissions;
        preparedSetupData.helpers = new address[](0);
    }

    /// @notice Prepare the uninstallation of the plugin
    /// @param _dao The DAO address
    /// @param _payload The setup payload from installation
    /// @return permissions The permissions to revoke
    function prepareUninstallation(address _dao, SetupPayload calldata _payload)
        external
        view
        returns (PermissionLib.MultiTargetPermission[] memory permissions)
    {
        // Decode uninstallation parameters to get manager address
        address managerAddress = decodeUninstallationParams(_payload.data);

        // Prepare permissions array to revoke
        permissions = new PermissionLib.MultiTargetPermission[](2);

        // Revoke MANAGER_PERMISSION on plugin from manager address
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: managerAddress,
            condition: PermissionLib.NO_CONDITION,
            permissionId: PaymentsPluginV1(_payload.plugin).MANAGER_PERMISSION_ID()
        });

        // Revoke EXECUTE_PERMISSION on DAO from plugin
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: DAO(payable(_dao)).EXECUTE_PERMISSION_ID()
        });
    }

    /// @notice Encode installation parameters
    /// @param _managerAddress Who can manage payments
    /// @param _registryAddress Address registry contract
    /// @param _llamaPayFactory LlamaPay factory contract
    /// @return Encoded parameters
    function encodeInstallationParams(address _managerAddress, address _registryAddress, address _llamaPayFactory)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(_managerAddress, _registryAddress, _llamaPayFactory);
    }

    /// @notice Decode installation parameters
    /// @param _data Encoded installation parameters
    /// @return managerAddress Who can manage payments
    /// @return registryAddress Address registry contract
    /// @return llamaPayFactory LlamaPay factory contract
    function decodeInstallationParams(bytes memory _data)
        public
        pure
        returns (address managerAddress, address registryAddress, address llamaPayFactory)
    {
        (managerAddress, registryAddress, llamaPayFactory) = abi.decode(_data, (address, address, address));
    }

    /// @notice Encode uninstallation parameters
    /// @param _managerAddress Manager address to revoke permissions from
    /// @return Encoded parameters
    function encodeUninstallationParams(address _managerAddress) external pure returns (bytes memory) {
        return abi.encode(_managerAddress);
    }

    /// @notice Decode uninstallation parameters
    /// @param _data Encoded uninstallation parameters
    /// @return managerAddress Manager address to revoke permissions from
    function decodeUninstallationParams(bytes memory _data) public pure returns (address managerAddress) {
        (managerAddress) = abi.decode(_data, (address));
    }

    /// @notice Get the current implementation address
    /// @return The implementation address
    function getImplementation() external view returns (address) {
        return paymentsPluginImplementation;
    }

    /// @notice Custom errors for parameter validation
    error InvalidManagerAddress();
    error InvalidRegistryAddress();
    error InvalidLlamaPayFactory();
}
