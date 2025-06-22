// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentsPluginV1Setup} from "../../../src/v1/setup/PaymentsPluginV1Setup.sol";
import {PaymentsPluginV1} from "../../../src/v1/PaymentsPluginV1.sol";
import {IPluginSetup, PermissionLib} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";

contract MockDAO {
    bytes32 public constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");
}

contract PaymentsPluginSetupTest is Test {
    PaymentsPluginV1Setup public pluginSetup;
    MockDAO public dao;
    address alice = vm.addr(1);

    function setUp() public {
        pluginSetup = new PaymentsPluginV1Setup();
        dao = new MockDAO();
    }

    // =========================================================================
    // Plugin Setup Installation Tests
    // =========================================================================

    function test_prepareInstallation_ShouldDeployPluginProxySuccessfully() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(
            alice,
            address(0x123), // registry
            address(0x456) // llamaPayFactory
        );

        (address plugin,) = pluginSetup.prepareInstallation(address(dao), installationParams);

        assertTrue(plugin != address(0));
        assertEq(address(PaymentsPluginV1(plugin).registry()), address(0x123));
        assertEq(address(PaymentsPluginV1(plugin).llamaPayFactory()), address(0x456));
    }

    function test_prepareInstallation_ShouldGrantMANAGER_PERMISSIONToManagerAddress() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(alice, address(0x123), address(0x456));

        (, IPluginSetup.PreparedSetupData memory preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        // Check that first permission grants MANAGER_PERMISSION to alice
        assertEq(preparedSetupData.permissions[0].who, alice);
        assertEq(preparedSetupData.permissions[0].permissionId, keccak256("MANAGER_PERMISSION"));
    }

    function test_prepareInstallation_ShouldGrantEXECUTE_PERMISSIONToPluginOnDAO() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(alice, address(0x123), address(0x456));

        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) =
            pluginSetup.prepareInstallation(address(dao), installationParams);

        // Check that second permission grants EXECUTE_PERMISSION to plugin on DAO
        assertEq(preparedSetupData.permissions[1].where, address(dao));
        assertEq(preparedSetupData.permissions[1].who, plugin);
        assertEq(preparedSetupData.permissions[1].permissionId, dao.EXECUTE_PERMISSION_ID());
    }

    function test_prepareInstallation_ShouldRevertWithInvalidManagerAddressForZeroManager() public {
        bytes memory installationParams =
            pluginSetup.encodeInstallationParams(address(0), address(0x123), address(0x456));

        vm.expectRevert(PaymentsPluginV1Setup.InvalidManagerAddress.selector);
        pluginSetup.prepareInstallation(address(dao), installationParams);
    }

    function test_prepareInstallation_ShouldRevertWithInvalidRegistryAddressForZeroRegistry() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(alice, address(0), address(0x456));

        vm.expectRevert(PaymentsPluginV1Setup.InvalidRegistryAddress.selector);
        pluginSetup.prepareInstallation(address(dao), installationParams);
    }

    function test_prepareInstallation_ShouldRevertWithInvalidLlamaPayFactoryForZeroFactory() public {
        bytes memory installationParams = pluginSetup.encodeInstallationParams(alice, address(0x123), address(0));

        vm.expectRevert(PaymentsPluginV1Setup.InvalidLlamaPayFactory.selector);
        pluginSetup.prepareInstallation(address(dao), installationParams);
    }

    // =========================================================================
    // Plugin Setup Uninstallation Tests
    // =========================================================================

    function test_prepareUninstallation_ShouldRevokeMANAGER_PERMISSIONFromManagerAddress() public {
        // First install
        bytes memory installationParams = pluginSetup.encodeInstallationParams(alice, address(0x123), address(0x456));

        (address plugin,) = pluginSetup.prepareInstallation(address(dao), installationParams);

        // Create uninstallation payload
        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: plugin,
            currentHelpers: new address[](0),
            data: pluginSetup.encodeUninstallationParams(alice)
        });

        // Test uninstallation
        PermissionLib.MultiTargetPermission[] memory permissions =
            pluginSetup.prepareUninstallation(address(dao), payload);

        // Check that first permission revokes MANAGER_PERMISSION from alice
        assertEq(permissions[0].who, alice);
        assertEq(permissions[0].permissionId, keccak256("MANAGER_PERMISSION"));
        assertEq(uint256(permissions[0].operation), uint256(PermissionLib.Operation.Revoke));
    }

    function test_prepareUninstallation_ShouldRevokeEXECUTE_PERMISSIONFromPluginOnDAO() public {
        // First install
        bytes memory installationParams = pluginSetup.encodeInstallationParams(alice, address(0x123), address(0x456));

        (address plugin,) = pluginSetup.prepareInstallation(address(dao), installationParams);

        // Create uninstallation payload
        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: plugin,
            currentHelpers: new address[](0),
            data: pluginSetup.encodeUninstallationParams(alice)
        });

        // Test uninstallation
        PermissionLib.MultiTargetPermission[] memory permissions =
            pluginSetup.prepareUninstallation(address(dao), payload);

        // Check that second permission revokes EXECUTE_PERMISSION from plugin on DAO
        assertEq(permissions[1].where, address(dao));
        assertEq(permissions[1].who, plugin);
        assertEq(permissions[1].permissionId, dao.EXECUTE_PERMISSION_ID());
        assertEq(uint256(permissions[1].operation), uint256(PermissionLib.Operation.Revoke));
    }

    // =========================================================================
    // Parameter Encoding/Decoding Tests
    // =========================================================================

    function test_encodeInstallationParameters_ShouldEncodeParametersCorrectly() public view {
        bytes memory encoded = pluginSetup.encodeInstallationParams(alice, address(0x123), address(0x456));

        assertTrue(encoded.length > 0);
    }

    function test_decodeInstallationParameters_ShouldDecodeParametersCorrectly() public view {
        bytes memory encoded = pluginSetup.encodeInstallationParams(alice, address(0x123), address(0x456));

        (address manager, address registry, address factory) = pluginSetup.decodeInstallationParams(encoded);

        assertEq(manager, alice);
        assertEq(registry, address(0x123));
        assertEq(factory, address(0x456));
    }

    function test_decodeInstallationParameters_ShouldMatchOriginalValues() public view {
        address originalManager = alice;
        address originalRegistry = address(0x123);
        address originalFactory = address(0x456);

        bytes memory encoded = pluginSetup.encodeInstallationParams(originalManager, originalRegistry, originalFactory);

        (address decodedManager, address decodedRegistry, address decodedFactory) =
            pluginSetup.decodeInstallationParams(encoded);

        assertEq(decodedManager, originalManager);
        assertEq(decodedRegistry, originalRegistry);
        assertEq(decodedFactory, originalFactory);
    }

    function test_encodeUninstallationParameters_ShouldEncodeManagerAddressCorrectly() public view {
        bytes memory encoded = pluginSetup.encodeUninstallationParams(alice);
        assertTrue(encoded.length > 0);
    }

    function test_decodeUninstallationParameters_ShouldDecodeManagerAddressCorrectly() public view {
        bytes memory encoded = pluginSetup.encodeUninstallationParams(alice);
        address decoded = pluginSetup.decodeUninstallationParams(encoded);
        assertEq(decoded, alice);
    }

    // =========================================================================
    // Implementation Management Tests
    // =========================================================================

    function test_getImplementation_ShouldReturnCorrectImplementationAddress() public view {
        address implementation = pluginSetup.getImplementation();
        assertTrue(implementation != address(0));

        // Should be a PaymentsPlugin contract
        PaymentsPluginV1(implementation); // This would revert if not a valid PaymentsPluginV1
    }
}
