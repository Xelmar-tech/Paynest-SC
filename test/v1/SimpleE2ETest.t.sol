// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {PayNestDAOFactory} from "../../src/v1/factory/PayNestDAOFactory.sol";
import {AddressRegistryV1} from "../../src/v1/AddressRegistryV1.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

/**
 * @title Simple E2E Test for PayNest DAO Factory
 * @notice This test demonstrates the PayNest DAO Factory using deployed contracts on Base mainnet
 * @dev This test uses real deployed contracts and should be run with --fork-url pointing to Base mainnet
 */
contract SimpleE2ETest is Test {
    // Deployed contract addresses on Base mainnet
    address constant DEPLOYED_ADDRESS_REGISTRY = 0x0a7DCbbc427a8f7c2078c618301B447cCF1B3Bc0;
    address constant DEPLOYED_DAO_FACTORY = 0xcc602EA573a42eBeC290f33F49D4A87177ebB8d2;
    address constant DEPLOYED_ADMIN_PLUGIN_REPO = 0x212eF339C77B3390599caB4D46222D79fAabcb5c;
    address constant DEPLOYED_PAYMENTS_PLUGIN_REPO = 0xbe203F5f0C3aF11A961c2c426AE7649a1a011028;
    address constant LLAMAPAY_FACTORY_BASE = 0x09c39B8311e4B7c678cBDAD76556877ecD3aEa07;

    // Test addresses
    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");

    PayNestDAOFactory internal factory;
    AddressRegistryV1 internal registry;

    function setUp() public {
        // Skip setup if not on Base mainnet fork
        if (block.chainid != 8453) {
            return;
        }

        // Use deployed AddressRegistry
        registry = AddressRegistryV1(DEPLOYED_ADDRESS_REGISTRY);

        // Deploy a new PayNestDAOFactory using the deployed infrastructure
        factory = new PayNestDAOFactory(
            registry,
            DAOFactory(DEPLOYED_DAO_FACTORY),
            PluginRepo(DEPLOYED_ADMIN_PLUGIN_REPO),
            PluginRepo(DEPLOYED_PAYMENTS_PLUGIN_REPO),
            LLAMAPAY_FACTORY_BASE
        );

        console2.log("PayNestDAOFactory deployed at:", address(factory));
        console2.log("Using AddressRegistry at:", address(registry));
        console2.log("Test setup complete");
    }

    function test_FactoryDeployedCorrectly() public view {
        if (block.chainid != 8453) return;
        // Verify factory was deployed with correct parameters
        assertEq(address(factory.addressRegistry()), DEPLOYED_ADDRESS_REGISTRY);
        assertEq(address(factory.daoFactory()), DEPLOYED_DAO_FACTORY);
        assertEq(address(factory.adminPluginRepo()), DEPLOYED_ADMIN_PLUGIN_REPO);
        assertEq(address(factory.paymentsPluginRepo()), DEPLOYED_PAYMENTS_PLUGIN_REPO);
        assertEq(factory.llamaPayFactory(), LLAMAPAY_FACTORY_BASE);

        // Verify initial state
        assertEq(factory.getCreatedDAOsCount(), 0);
    }

    function test_AddressRegistryWorks() public {
        if (block.chainid != 8453) return;
        // Alice claims a username
        vm.prank(alice);
        registry.claimUsername("alice");

        // Verify username was claimed
        assertEq(registry.getUserAddress("alice"), alice);
        assertEq(registry.getUsernameByAddress(alice), "alice");
        assertTrue(registry.hasUsername(alice));
        assertFalse(registry.isUsernameAvailable("alice"));

        console2.log("Alice claimed username 'alice' successfully");
    }

    function test_CreatePayNestDAO() public {
        if (block.chainid != 8453) return;
        // Create a PayNest DAO
        (address dao, address adminPlugin, address paymentsPlugin) = factory.createPayNestDAO(admin, "test-dao");

        // Verify DAO was created
        assertTrue(dao != address(0));
        assertTrue(adminPlugin != address(0));
        assertTrue(paymentsPlugin != address(0));

        // Verify factory tracking
        assertEq(factory.getCreatedDAOsCount(), 1);
        assertEq(factory.getCreatedDAO(0), dao);

        // Verify DAO info
        PayNestDAOFactory.DAOInfo memory info = factory.getDAOInfo(dao);
        assertEq(info.admin, admin);
        assertEq(info.adminPlugin, adminPlugin);
        assertEq(info.paymentsPlugin, paymentsPlugin);
        assertTrue(info.createdAt > 0);

        console2.log("DAO created successfully:");
        console2.log("  DAO address:", dao);
        console2.log("  Admin plugin:", adminPlugin);
        console2.log("  Payments plugin:", paymentsPlugin);
        console2.log("  Created at:", info.createdAt);
    }

    function test_MultipleDAOCreation() public {
        if (block.chainid != 8453) return;
        // Create multiple DAOs
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        (address dao1,,) = factory.createPayNestDAO(alice, "alice-dao");
        (address dao2,,) = factory.createPayNestDAO(bob, "bob-dao");

        // Verify both DAOs were created
        assertEq(factory.getCreatedDAOsCount(), 2);
        assertEq(factory.getCreatedDAO(0), dao1);
        assertEq(factory.getCreatedDAO(1), dao2);

        // Verify DAO info is separate
        PayNestDAOFactory.DAOInfo memory info1 = factory.getDAOInfo(dao1);
        PayNestDAOFactory.DAOInfo memory info2 = factory.getDAOInfo(dao2);

        assertEq(info1.admin, alice);
        assertEq(info2.admin, bob);

        console2.log("Multiple DAOs created successfully:");
        console2.log("  Alice DAO:", dao1);
        console2.log("  Bob DAO:", dao2);
    }

    function test_InvalidInputs() public {
        if (block.chainid != 8453) return;
        // Test zero admin address
        vm.expectRevert(PayNestDAOFactory.AdminAddressZero.selector);
        factory.createPayNestDAO(address(0), "test-dao");

        // Test empty DAO name
        vm.expectRevert(PayNestDAOFactory.DAONameEmpty.selector);
        factory.createPayNestDAO(admin, "");
    }
}
