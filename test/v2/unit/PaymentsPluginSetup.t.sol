// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionLib, IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PaymentsPluginSetup} from "../../../src/v2/setup/PaymentsPluginSetup.sol";
import {PaymentsPlugin} from "../../../src/v2/PaymentsPlugin.sol";

contract MockDAO {
    bytes32 public constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    function hasPermission(address, address, bytes32, bytes memory) external pure returns (bool) {
        return true;
    }
}

contract PaymentsPluginSetupV2Test is Test {
    PaymentsPluginSetup public pluginSetup;
    MockDAO public dao;

    address public constant MANAGER = address(0x1);
    address public constant REGISTRY = address(0x2);
    address public constant LLAMAPAY_FACTORY = address(0x3);

    function setUp() public {
        pluginSetup = new PaymentsPluginSetup();
        dao = new MockDAO();
    }

    // Constructor Tests

    function test_constructor_ShouldDeployImplementation() public {
        assertTrue(pluginSetup.implementation() != address(0));
    }

    function test_getImplementation_ShouldReturnCorrectAddress() public view {
        address impl = pluginSetup.implementation();
        assertTrue(impl != address(0));

        // Verify it's a PaymentsPlugin
        PaymentsPlugin plugin = PaymentsPlugin(impl);
        assertEq(plugin.MANAGER_PERMISSION_ID(), keccak256("MANAGER_PERMISSION"));
    }

    // Installation Parameter Encoding/Decoding Tests

    function test_encodeInstallationParams_ShouldEncodeCorrectly() public view {
        bytes memory encoded = pluginSetup.encodeInstallationParams(MANAGER, REGISTRY, LLAMAPAY_FACTORY);

        (address decodedManager, address decodedRegistry, address decodedLlamaPayFactory) =
            pluginSetup.decodeInstallationParams(encoded);

        assertEq(decodedManager, MANAGER);
        assertEq(decodedRegistry, REGISTRY);
        assertEq(decodedLlamaPayFactory, LLAMAPAY_FACTORY);
    }

    function test_decodeInstallationParams_ValidData_ShouldDecodeCorrectly() public view {
        bytes memory data = abi.encode(MANAGER, REGISTRY, LLAMAPAY_FACTORY);

        (address manager, address registry, address llamaPayFactory) = pluginSetup.decodeInstallationParams(data);

        assertEq(manager, MANAGER);
        assertEq(registry, REGISTRY);
        assertEq(llamaPayFactory, LLAMAPAY_FACTORY);
    }

    function test_encodeUninstallationParams_ShouldEncodeCorrectly() public view {
        bytes memory encoded = pluginSetup.encodeUninstallationParams(MANAGER);
        address decoded = pluginSetup.decodeUninstallationParams(encoded);
        assertEq(decoded, MANAGER);
    }

    function test_decodeUninstallationParams_ValidData_ShouldDecodeCorrectly() public view {
        bytes memory data = abi.encode(MANAGER);
        address manager = pluginSetup.decodeUninstallationParams(data);
        assertEq(manager, MANAGER);
    }

    // Installation Preparation Tests

    function test_prepareInstallation_ValidParams_ShouldDeployProxy() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(MANAGER, REGISTRY, LLAMAPAY_FACTORY);

        (address plugin, PaymentsPluginSetup.PreparedSetupData memory preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        assertTrue(plugin != address(0));
        assertTrue(plugin != pluginSetup.implementation());

        // Verify plugin is initialized correctly
        PaymentsPlugin paymentsPlugin = PaymentsPlugin(plugin);
        assertEq(address(paymentsPlugin.dao()), address(dao));
        assertEq(address(paymentsPlugin.registry()), REGISTRY);
        assertEq(address(paymentsPlugin.llamaPayFactory()), LLAMAPAY_FACTORY);
    }

    function test_prepareInstallation_ValidParams_ShouldSetupPermissions() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(MANAGER, REGISTRY, LLAMAPAY_FACTORY);

        (, PaymentsPluginSetup.PreparedSetupData memory preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        assertEq(preparedSetupData.permissions.length, 2);

        // Check MANAGER_PERMISSION grant
        PermissionLib.MultiTargetPermission memory managerPerm = preparedSetupData.permissions[0];
        assertEq(uint8(managerPerm.operation), uint8(PermissionLib.Operation.Grant));
        assertEq(managerPerm.who, MANAGER);
        assertEq(managerPerm.condition, PermissionLib.NO_CONDITION);

        // Check EXECUTE_PERMISSION grant
        PermissionLib.MultiTargetPermission memory executePerm = preparedSetupData.permissions[1];
        assertEq(uint8(executePerm.operation), uint8(PermissionLib.Operation.Grant));
        assertEq(executePerm.where, address(dao));
        assertEq(executePerm.condition, PermissionLib.NO_CONDITION);
    }

    function test_prepareInstallation_ZeroManagerAddress_ShouldRevert() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(address(0), REGISTRY, LLAMAPAY_FACTORY);

        vm.expectRevert(PaymentsPluginSetup.InvalidManagerAddress.selector);
        pluginSetup.prepareInstallation(address(dao), installationParams);
    }

    function test_prepareInstallation_ZeroRegistryAddress_ShouldRevert() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(MANAGER, address(0), LLAMAPAY_FACTORY);

        vm.expectRevert(PaymentsPluginSetup.InvalidRegistryAddress.selector);
        pluginSetup.prepareInstallation(address(dao), installationParams);
    }

    function test_prepareInstallation_ZeroLlamaPayFactory_ShouldRevert() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(MANAGER, REGISTRY, address(0));

        vm.expectRevert(PaymentsPluginSetup.InvalidLlamaPayFactory.selector);
        pluginSetup.prepareInstallation(address(dao), installationParams);
    }

    // Uninstallation Preparation Tests

    function test_prepareUninstallation_ValidParams_ShouldRevokePermissions() public {
        // First prepare installation to get a plugin address
        bytes memory installationParams = pluginSetup.encodeInstallationParams(MANAGER, REGISTRY, LLAMAPAY_FACTORY);
        (address plugin,) = pluginSetup.prepareInstallation(address(dao), installationParams);

        // Prepare uninstallation
        bytes memory uninstallationParams = pluginSetup.encodeUninstallationParams(MANAGER);
        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: plugin, currentHelpers: new address[](0), data: uninstallationParams});

        PermissionLib.MultiTargetPermission[] memory permissions =
            pluginSetup.prepareUninstallation(address(dao), payload);

        assertEq(permissions.length, 2);

        // Check MANAGER_PERMISSION revoke
        PermissionLib.MultiTargetPermission memory managerPerm = permissions[0];
        assertEq(uint8(managerPerm.operation), uint8(PermissionLib.Operation.Revoke));
        assertEq(managerPerm.where, plugin);
        assertEq(managerPerm.who, MANAGER);
        assertEq(managerPerm.condition, PermissionLib.NO_CONDITION);

        // Check EXECUTE_PERMISSION revoke
        PermissionLib.MultiTargetPermission memory executePerm = permissions[1];
        assertEq(uint8(executePerm.operation), uint8(PermissionLib.Operation.Revoke));
        assertEq(executePerm.where, address(dao));
        assertEq(executePerm.who, plugin);
        assertEq(executePerm.condition, PermissionLib.NO_CONDITION);
    }

    // Integration Tests

    function test_fullInstallationUninstallationCycle_ShouldWorkCorrectly() public {
        // 1. Prepare installation
        bytes memory installationParams = pluginSetup.encodeInstallationParams(MANAGER, REGISTRY, LLAMAPAY_FACTORY);
        (address plugin, PaymentsPluginSetup.PreparedSetupData memory preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        // Verify installation preparation
        assertTrue(plugin != address(0));
        assertEq(preparedSetupData.permissions.length, 2);

        // 2. Prepare uninstallation
        bytes memory uninstallationParams = pluginSetup.encodeUninstallationParams(MANAGER);
        IPluginSetup.SetupPayload memory payload =
            IPluginSetup.SetupPayload({plugin: plugin, currentHelpers: new address[](0), data: uninstallationParams});

        PermissionLib.MultiTargetPermission[] memory uninstallPermissions =
            pluginSetup.prepareUninstallation(address(dao), payload);

        // Verify uninstallation preparation
        assertEq(uninstallPermissions.length, 2);

        // Check that install and uninstall permissions are opposites
        for (uint256 i = 0; i < 2; i++) {
            assertEq(preparedSetupData.permissions[i].where, uninstallPermissions[i].where);
            assertEq(preparedSetupData.permissions[i].who, uninstallPermissions[i].who);
            assertEq(preparedSetupData.permissions[i].permissionId, uninstallPermissions[i].permissionId);
            assertEq(preparedSetupData.permissions[i].condition, uninstallPermissions[i].condition);

            // Operations should be opposite
            assertEq(uint8(preparedSetupData.permissions[i].operation), uint8(PermissionLib.Operation.Grant));
            assertEq(uint8(uninstallPermissions[i].operation), uint8(PermissionLib.Operation.Revoke));
        }
    }

    // Edge Case Tests

    function test_prepareInstallation_SameAddressForDifferentParams_ShouldWork() public {
        // Using same address for manager and registry (edge case)
        bytes memory installationParams = pluginSetup.encodeInstallationParams(MANAGER, MANAGER, LLAMAPAY_FACTORY);

        (address plugin, PaymentsPluginSetup.PreparedSetupData memory preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        assertTrue(plugin != address(0));
        assertEq(preparedSetupData.permissions.length, 2);

        // Verify plugin initialization with same addresses
        PaymentsPlugin paymentsPlugin = PaymentsPlugin(plugin);
        assertEq(address(paymentsPlugin.registry()), MANAGER);
    }

    function test_multipleInstallationsWithSameParams_ShouldDeployDifferentProxies() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(MANAGER, REGISTRY, LLAMAPAY_FACTORY);

        (address plugin1,) = pluginSetup.prepareInstallation(address(dao), installationParams);
        (address plugin2,) = pluginSetup.prepareInstallation(address(dao), installationParams);

        assertTrue(plugin1 != plugin2);
        assertTrue(plugin1 != address(0));
        assertTrue(plugin2 != address(0));
    }

    function test_installationParamsWithDifferentDAOs_ShouldInitializeCorrectly() public {
        MockDAO dao2 = new MockDAO();
        bytes memory installationParams = pluginSetup.encodeInstallationParams(MANAGER, REGISTRY, LLAMAPAY_FACTORY);

        (address plugin1,) = pluginSetup.prepareInstallation(address(dao), installationParams);
        (address plugin2,) = pluginSetup.prepareInstallation(address(dao2), installationParams);

        PaymentsPlugin paymentsPlugin1 = PaymentsPlugin(plugin1);
        PaymentsPlugin paymentsPlugin2 = PaymentsPlugin(plugin2);

        assertEq(address(paymentsPlugin1.dao()), address(dao));
        assertEq(address(paymentsPlugin2.dao()), address(dao2));
    }
}
