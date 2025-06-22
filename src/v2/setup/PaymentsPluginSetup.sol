// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {IDAO, DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IPluginSetup, PluginSetup, PermissionLib} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import {PaymentsPlugin} from "../PaymentsPlugin.sol";

/// @title PaymentsPluginSetup
/// @notice Setup contract for the PaymentsPlugin V2.0 that handles installation and uninstallation
/// @dev Follows the standard Aragon plugin setup pattern with UUPS proxy deployment for V2.0 architecture
contract PaymentsPluginSetup is PluginSetup {
    /// @notice Address of the PaymentsPlugin V2.0 implementation contract
    address private immutable paymentsPluginImplementation;

    /// @notice Custom errors for gas-efficient error handling
    error InvalidManagerAddress();
    error InvalidRegistryAddress();
    error InvalidLlamaPayFactory();

    /// @notice Constructor that deploys the PaymentsPlugin V2.0 implementation
    constructor() PluginSetup(address(new PaymentsPlugin())) {
        paymentsPluginImplementation = implementation();
    }

    /// @notice Installation parameters structure for V2.0
    struct InstallationParams {
        address managerAddress; // Who can manage payments (has MANAGER_PERMISSION_ID)
        address registryAddress; // Address registry V2.0 contract
        address llamaPayFactory; // LlamaPay factory contract
    }

    /// @notice Prepare the installation of the PaymentsPlugin V2.0
    /// @param _dao The DAO address that will host the plugin
    /// @param _installationParams Encoded installation parameters
    /// @return plugin The deployed plugin proxy address
    /// @return preparedSetupData The setup data including permissions to be granted
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

        // Deploy UUPS proxy of PaymentsPlugin V2.0
        plugin = ProxyLib.deployUUPSProxy(
            paymentsPluginImplementation,
            abi.encodeCall(PaymentsPlugin.initialize, (IDAO(_dao), registryAddress, llamaPayFactory))
        );

        // Prepare permissions array
        PermissionLib.MultiTargetPermission[] memory permissions = new PermissionLib.MultiTargetPermission[](2);

        // Grant MANAGER_PERMISSION on plugin to manager address
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: managerAddress,
            condition: PermissionLib.NO_CONDITION,
            permissionId: PaymentsPlugin(plugin).MANAGER_PERMISSION_ID()
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
    }

    /// @notice Prepare the uninstallation of the PaymentsPlugin V2.0
    /// @param _dao The DAO address
    /// @param _payload The uninstallation payload
    /// @return permissions Array of permissions to be revoked
    function prepareUninstallation(address _dao, SetupPayload calldata _payload)
        external
        view
        returns (PermissionLib.MultiTargetPermission[] memory permissions)
    {
        // Decode uninstallation parameters
        address managerAddress = decodeUninstallationParams(_payload.data);

        // Prepare permissions array for revocation
        permissions = new PermissionLib.MultiTargetPermission[](2);

        // Revoke MANAGER_PERMISSION on plugin from manager address
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: managerAddress,
            condition: PermissionLib.NO_CONDITION,
            permissionId: PaymentsPlugin(_payload.plugin).MANAGER_PERMISSION_ID()
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

    /// @notice Encode installation parameters for PaymentsPlugin V2.0
    /// @param _managerAddress Address that will have MANAGER_PERMISSION_ID
    /// @param _registryAddress Address of the registry contract (V2.0)
    /// @param _llamaPayFactory Address of the LlamaPay factory contract
    /// @return Encoded installation parameters
    function encodeInstallationParams(address _managerAddress, address _registryAddress, address _llamaPayFactory)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(_managerAddress, _registryAddress, _llamaPayFactory);
    }

    /// @notice Decode installation parameters for PaymentsPlugin V2.0
    /// @param _data Encoded installation parameters
    /// @return managerAddress Address that will have MANAGER_PERMISSION_ID
    /// @return registryAddress Address of the registry contract (V2.0)
    /// @return llamaPayFactory Address of the LlamaPay factory contract
    function decodeInstallationParams(bytes memory _data)
        public
        pure
        returns (address managerAddress, address registryAddress, address llamaPayFactory)
    {
        (managerAddress, registryAddress, llamaPayFactory) = abi.decode(_data, (address, address, address));
    }

    /// @notice Encode uninstallation parameters for PaymentsPlugin V2.0
    /// @param _managerAddress Address that has MANAGER_PERMISSION_ID
    /// @return Encoded uninstallation parameters
    function encodeUninstallationParams(address _managerAddress) external pure returns (bytes memory) {
        return abi.encode(_managerAddress);
    }

    /// @notice Decode uninstallation parameters for PaymentsPlugin V2.0
    /// @param _data Encoded uninstallation parameters
    /// @return managerAddress Address that has MANAGER_PERMISSION_ID
    function decodeUninstallationParams(bytes memory _data) public pure returns (address managerAddress) {
        (managerAddress) = abi.decode(_data, (address));
    }
}
