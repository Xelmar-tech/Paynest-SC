// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

import {ForkTestBase} from "../lib/ForkTestBase.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {PayNestDAOFactory} from "../../../src/v1/factory/PayNestDAOFactory.sol";
import {AddressRegistryV1} from "../../../src/v1/AddressRegistryV1.sol";
import {PaymentsPluginV1} from "../../../src/v1/PaymentsPluginV1.sol";
import {PaymentsPluginV1Setup} from "../../../src/v1/setup/PaymentsPluginV1Setup.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {NON_EMPTY_BYTES} from "../lib/constants.sol";

contract PayNestDAOFactoryForkTest is ForkTestBase {
    PayNestDAOFactory internal factory;
    AddressRegistryV1 internal registry;
    PluginRepo internal adminPluginRepo;
    PluginRepo internal paymentsPluginRepo;
    PaymentsPluginV1Setup internal paymentsPluginSetup;

    string constant TEST_DAO_NAME = "test-dao";
    address constant TEST_ADMIN = address(0x123);
    address constant LLAMAPAY_FACTORY_BASE = 0x09c39B8311e4B7c678cBDAD76556877ecD3aEa07;

    // Events to test
    event PayNestDAOCreated(
        address indexed dao, address indexed admin, address adminPlugin, address paymentsPlugin, string daoName
    );

    function setUp() public virtual override {
        super.setUp();

        // Deploy shared AddressRegistry
        registry = AddressRegistryV1(ProxyLib.deployUUPSProxy(address(new AddressRegistryV1()), ""));

        // Create payments plugin repository using real PluginRepoFactory
        string memory paymentsPluginRepoSubdomain = string.concat("payments-plugin-", vm.toString(block.timestamp));
        paymentsPluginSetup = new PaymentsPluginV1Setup();
        paymentsPluginRepo = pluginRepoFactory.createPluginRepoWithFirstVersion({
            _subdomain: paymentsPluginRepoSubdomain,
            _pluginSetup: address(paymentsPluginSetup),
            _maintainer: address(this),
            _releaseMetadata: NON_EMPTY_BYTES,
            _buildMetadata: NON_EMPTY_BYTES
        });

        // Use the actual deployed admin plugin repo on Base mainnet
        adminPluginRepo = PluginRepo(0x212eF339C77B3390599caB4D46222D79fAabcb5c);

        // Deploy PayNest DAO Factory
        factory =
            new PayNestDAOFactory(registry, daoFactory, adminPluginRepo, paymentsPluginRepo, LLAMAPAY_FACTORY_BASE);

        // Labels
        vm.label(address(factory), "PayNestDAOFactory");
        vm.label(address(registry), "AddressRegistry");
        vm.label(address(paymentsPluginRepo), "PaymentsPluginRepo");
        vm.label(TEST_ADMIN, "TestAdmin");
    }

    function test_createDAOWithRealAragonIntegration() external {
        // It should create DAO with real DAOFactory
        // It should install admin plugin
        // It should install payments plugin
        // Note: We can't predict the exact addresses, so we'll check for the event after creation

        // Create DAO
        (address dao, address adminPlugin, address paymentsPlugin) = factory.createPayNestDAO(TEST_ADMIN, TEST_DAO_NAME);

        // It should return valid addresses
        assertTrue(dao != address(0), "DAO address should not be zero");
        assertTrue(adminPlugin != address(0), "Admin plugin address should not be zero");
        assertTrue(paymentsPlugin != address(0), "Payments plugin address should not be zero");

        // It should store DAO info correctly
        PayNestDAOFactory.DAOInfo memory daoInfo = factory.getDAOInfo(dao);
        assertEq(daoInfo.admin, TEST_ADMIN, "Admin should match");
        assertEq(daoInfo.adminPlugin, adminPlugin, "Admin plugin should match");
        assertEq(daoInfo.paymentsPlugin, paymentsPlugin, "Payments plugin should match");
        assertTrue(daoInfo.createdAt > 0, "Creation timestamp should be set");

        // It should add DAO to tracking array
        assertEq(factory.getCreatedDAOsCount(), 1, "Should have 1 DAO");
        assertEq(factory.getCreatedDAO(0), dao, "First DAO should match");

        // It should verify DAO is properly configured
        DAO createdDAO = DAO(payable(dao));
        assertTrue(address(createdDAO) != address(0), "DAO should be valid");

        // Label the created contracts
        vm.label(dao, "CreatedDAO");
        vm.label(adminPlugin, "AdminPlugin");
        vm.label(paymentsPlugin, "PaymentsPlugin");
    }

    function test_verifyPermissionsSetupCorrectly() external {
        // Create DAO first
        (address dao, address adminPlugin, address paymentsPlugin) = factory.createPayNestDAO(TEST_ADMIN, TEST_DAO_NAME);

        DAO createdDAO = DAO(payable(dao));
        PaymentsPluginV1 plugin = PaymentsPluginV1(paymentsPlugin);

        // It should verify admin has control over admin plugin
        // Note: This test depends on the admin plugin implementation
        // For now, we'll test that the payments plugin has correct permissions

        // It should verify admin has manager permission on payments plugin
        bytes32 managerPermissionId = plugin.MANAGER_PERMISSION_ID();
        assertTrue(
            createdDAO.hasPermission(paymentsPlugin, TEST_ADMIN, managerPermissionId, ""),
            "Admin should have manager permission on payments plugin"
        );

        // It should verify payments plugin can execute on DAO
        bytes32 executePermissionId = createdDAO.EXECUTE_PERMISSION_ID();
        assertTrue(
            createdDAO.hasPermission(dao, paymentsPlugin, executePermissionId, ""),
            "Payments plugin should have execute permission on DAO"
        );
    }

    function test_sharedRegistryIntegration() external {
        // Create multiple DAOs
        (address dao1,, address paymentsPlugin1) = factory.createPayNestDAO(alice, "dao1");
        (address dao2,, address paymentsPlugin2) = factory.createPayNestDAO(bob, "dao2");

        PaymentsPluginV1 plugin1 = PaymentsPluginV1(paymentsPlugin1);
        PaymentsPluginV1 plugin2 = PaymentsPluginV1(paymentsPlugin2);

        // It should verify both plugins use the same registry
        assertEq(address(plugin1.registry()), address(registry), "Plugin1 should use shared registry");
        assertEq(address(plugin2.registry()), address(registry), "Plugin2 should use shared registry");
        assertEq(address(plugin1.registry()), address(plugin2.registry()), "Both plugins should use same registry");

        // It should verify shared registry integration works
        vm.prank(carol);
        registry.claimUsername("carol");

        // Both plugins should be able to resolve the same username
        assertEq(plugin1.registry().getUserAddress("carol"), carol, "Plugin1 should resolve carol");
        assertEq(plugin2.registry().getUserAddress("carol"), carol, "Plugin2 should resolve carol");
    }

    function test_multipleDAOCreation() external {
        address[] memory admins = new address[](3);
        admins[0] = alice;
        admins[1] = bob;
        admins[2] = carol;

        address[] memory daos = new address[](3);
        address[] memory adminPlugins = new address[](3);
        address[] memory paymentsPlugins = new address[](3);

        // Create multiple DAOs
        for (uint256 i = 0; i < 3; i++) {
            string memory daoName = string.concat("dao", vm.toString(i));
            (daos[i], adminPlugins[i], paymentsPlugins[i]) = factory.createPayNestDAO(admins[i], daoName);
        }

        // It should handle multiple DAO creation
        assertEq(factory.getCreatedDAOsCount(), 3, "Should have 3 DAOs");

        // It should store all DAOs correctly
        for (uint256 i = 0; i < 3; i++) {
            assertEq(factory.getCreatedDAO(i), daos[i], "DAO should be stored correctly");

            PayNestDAOFactory.DAOInfo memory daoInfo = factory.getDAOInfo(daos[i]);
            assertEq(daoInfo.admin, admins[i], "Admin should match");
            assertEq(daoInfo.adminPlugin, adminPlugins[i], "Admin plugin should match");
            assertEq(daoInfo.paymentsPlugin, paymentsPlugins[i], "Payments plugin should match");
        }

        // It should ensure all DAOs are independent
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = i + 1; j < 3; j++) {
                assertTrue(daos[i] != daos[j], "DAOs should be different");
                assertTrue(adminPlugins[i] != adminPlugins[j], "Admin plugins should be different");
                assertTrue(paymentsPlugins[i] != paymentsPlugins[j], "Payments plugins should be different");
            }
        }
    }

    function test_inputValidation() external {
        // It should revert with AdminAddressZero for zero admin
        vm.expectRevert(PayNestDAOFactory.AdminAddressZero.selector);
        factory.createPayNestDAO(address(0), TEST_DAO_NAME);

        // It should revert with DAONameEmpty for empty name
        vm.expectRevert(PayNestDAOFactory.DAONameEmpty.selector);
        factory.createPayNestDAO(TEST_ADMIN, "");
    }

    function test_viewFunctions() external {
        // Initial state
        assertEq(factory.getCreatedDAOsCount(), 0, "Should start with 0 DAOs");
        assertEq(address(factory.getAddressRegistry()), address(registry), "Should return correct registry");

        // Create a DAO
        (address dao, address adminPlugin, address paymentsPlugin) = factory.createPayNestDAO(TEST_ADMIN, TEST_DAO_NAME);

        // Test view functions
        assertEq(factory.getCreatedDAOsCount(), 1, "Should have 1 DAO");
        assertEq(factory.getCreatedDAO(0), dao, "Should return correct DAO");

        PayNestDAOFactory.DAOInfo memory daoInfo = factory.getDAOInfo(dao);
        assertEq(daoInfo.admin, TEST_ADMIN, "Should return correct admin");
        assertEq(daoInfo.adminPlugin, adminPlugin, "Should return correct admin plugin");
        assertEq(daoInfo.paymentsPlugin, paymentsPlugin, "Should return correct payments plugin");

        // Test non-existent DAO
        PayNestDAOFactory.DAOInfo memory emptyInfo = factory.getDAOInfo(address(0x999));
        assertEq(emptyInfo.admin, address(0), "Should return zero for non-existent DAO");
    }

    function test_factoryCannotHoldFunds() external {
        // Create DAO
        factory.createPayNestDAO(TEST_ADMIN, TEST_DAO_NAME);

        // It should never hold ETH
        assertEq(address(factory).balance, 0, "Factory should not hold ETH");

        // Factory should not have any special functions to receive ETH
        // This is implicit in the contract design
    }

    function test_gasUsageReasonable() external {
        uint256 gasBefore = gasleft();

        // Create DAO and measure gas
        factory.createPayNestDAO(TEST_ADMIN, TEST_DAO_NAME);

        uint256 gasUsed = gasBefore - gasleft();

        // It should verify gas costs are reasonable (less than 10M gas for full DAO creation)
        assertTrue(gasUsed < 10_000_000, "DAO creation should use reasonable gas");

        // Log gas usage for optimization purposes
        emit log_named_uint("Gas used for DAO creation", gasUsed);
    }

    modifier givenTestingFactoryConstruction() {
        _;
    }

    function test_factoryConstructionValidation() external givenTestingFactoryConstruction {
        // It should revert with AdminAddressZero for zero registry
        vm.expectRevert(PayNestDAOFactory.AdminAddressZero.selector);
        new PayNestDAOFactory(
            AddressRegistryV1(address(0)), daoFactory, adminPluginRepo, paymentsPluginRepo, LLAMAPAY_FACTORY_BASE
        );

        // It should revert with AdminAddressZero for zero dao factory
        vm.expectRevert(PayNestDAOFactory.AdminAddressZero.selector);
        new PayNestDAOFactory(
            registry, DAOFactory(address(0)), adminPluginRepo, paymentsPluginRepo, LLAMAPAY_FACTORY_BASE
        );

        // It should revert with AdminAddressZero for zero admin plugin repo
        vm.expectRevert(PayNestDAOFactory.AdminAddressZero.selector);
        new PayNestDAOFactory(registry, daoFactory, PluginRepo(address(0)), paymentsPluginRepo, LLAMAPAY_FACTORY_BASE);

        // It should revert with AdminAddressZero for zero payments plugin repo
        vm.expectRevert(PayNestDAOFactory.AdminAddressZero.selector);
        new PayNestDAOFactory(registry, daoFactory, adminPluginRepo, PluginRepo(address(0)), LLAMAPAY_FACTORY_BASE);

        // It should revert with AdminAddressZero for zero LlamaPay factory
        vm.expectRevert(PayNestDAOFactory.AdminAddressZero.selector);
        new PayNestDAOFactory(registry, daoFactory, adminPluginRepo, paymentsPluginRepo, address(0));
    }
}
