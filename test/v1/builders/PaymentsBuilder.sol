// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {TestBase} from "../lib/TestBase.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PaymentsPluginV1} from "../../../src/v1/PaymentsPluginV1.sol";
import {AddressRegistryV1} from "../../../src/v1/AddressRegistryV1.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

contract MockLlamaPayFactory {
    mapping(address => address) public tokenToContract;
    mapping(address => bool) public isDeployed;

    function createLlamaPayContract(address _token) external returns (address llamaPayContract) {
        llamaPayContract = address(new MockLlamaPay(_token));
        tokenToContract[_token] = llamaPayContract;
        isDeployed[llamaPayContract] = true;
        return llamaPayContract;
    }

    function getLlamaPayContractByToken(address _token)
        external
        view
        returns (address predictedAddress, bool deployed)
    {
        predictedAddress = tokenToContract[_token];
        deployed = isDeployed[predictedAddress];
    }
}

contract MockLlamaPay {
    address public token;
    uint256 public constant DECIMALS_DIVISOR = 1e14; // Assume 6 decimal token for simplicity

    mapping(address => uint256) public balances;
    mapping(bytes32 => uint256) public streamToStart;

    event StreamCreated(address indexed from, address indexed to, uint216 amountPerSec);
    event StreamCancelled(address indexed from, address indexed to, uint216 amountPerSec);
    event Withdraw(address indexed from, address indexed to, uint216 amountPerSec, uint256 amount);

    constructor(address _token) {
        token = _token;
    }

    function deposit(uint256 amount) external {
        // Mock transfer from sender
        balances[msg.sender] += amount;
    }

    function createStreamWithReason(address to, uint216 amountPerSec, string calldata /* reason */ ) external {
        bytes32 streamId = keccak256(abi.encodePacked(msg.sender, to, amountPerSec));
        streamToStart[streamId] = block.timestamp;
        emit StreamCreated(msg.sender, to, amountPerSec);
    }

    function createStream(address to, uint216 amountPerSec) external {
        bytes32 streamId = keccak256(abi.encodePacked(msg.sender, to, amountPerSec));
        streamToStart[streamId] = block.timestamp;
        emit StreamCreated(msg.sender, to, amountPerSec);
    }

    function cancelStream(address to, uint216 amountPerSec) external {
        bytes32 streamId = keccak256(abi.encodePacked(msg.sender, to, amountPerSec));
        delete streamToStart[streamId];
        emit StreamCancelled(msg.sender, to, amountPerSec);
    }

    function withdraw(address from, address to, uint216 amountPerSec) external {
        // Calculate withdrawable amount based on time elapsed
        bytes32 streamId = keccak256(abi.encodePacked(from, to, amountPerSec));
        uint256 startTime = streamToStart[streamId];
        require(startTime > 0, "Stream not found");

        uint256 elapsed = block.timestamp - startTime;
        uint256 withdrawableAmount = (elapsed * amountPerSec) / DECIMALS_DIVISOR;

        // Update start time to prevent double withdrawal
        streamToStart[streamId] = block.timestamp;

        emit Withdraw(from, to, amountPerSec, withdrawableAmount);
    }

    function withdrawable(address from, address to, uint216 amountPerSec)
        external
        view
        returns (uint256 withdrawableAmount, uint256 lastUpdate, uint256 owed)
    {
        bytes32 streamId = keccak256(abi.encodePacked(from, to, amountPerSec));
        uint256 startTime = streamToStart[streamId];

        if (startTime == 0) return (0, 0, 0);

        uint256 elapsed = block.timestamp - startTime;
        withdrawableAmount = (elapsed * amountPerSec) / DECIMALS_DIVISOR;
        lastUpdate = startTime;
        owed = 0; // Simplify for testing
    }

    function withdrawPayerAll() external {
        balances[msg.sender] = 0;
    }

    function getStreamId(address from, address to, uint216 amountPerSec) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(from, to, amountPerSec));
    }
}

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint8 public decimals;
    string public name;
    string public symbol;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract PaymentsBuilder is TestBase {
    address immutable DAO_BASE = address(new DAO());
    address immutable PAYMENTS_PLUGIN_BASE = address(new PaymentsPluginV1());
    address immutable REGISTRY_BASE = address(new AddressRegistryV1());

    // Parameters to override
    address daoOwner; // Used for testing purposes only
    address[] managers = [bob];
    address registryAddress;
    address llamaPayFactoryAddress;

    constructor() {
        // Set the caller as the initial daoOwner
        // It can grant and revoke permissions freely for testing purposes
        withDaoOwner(msg.sender);
    }

    // Override methods
    function withDaoOwner(address _newOwner) public returns (PaymentsBuilder) {
        daoOwner = _newOwner;
        return this;
    }

    function withManagers(address[] memory _newManagers) public returns (PaymentsBuilder) {
        delete managers;
        for (uint256 i = 0; i < _newManagers.length; i++) {
            managers.push(_newManagers[i]);
        }
        return this;
    }

    function withRegistry(address _registry) public returns (PaymentsBuilder) {
        registryAddress = _registry;
        return this;
    }

    function withLlamaPayFactory(address _factory) public returns (PaymentsBuilder) {
        llamaPayFactoryAddress = _factory;
        return this;
    }

    /// @dev Creates a DAO with the PaymentsPlugin and proper permissions
    /// @dev The setup is done on block/timestamp 0 and tests should be made on block/timestamp 1 or later.
    function build()
        public
        returns (
            DAO dao,
            PaymentsPluginV1 plugin,
            AddressRegistryV1 registry,
            MockLlamaPayFactory llamaPayFactory,
            MockERC20 token
        )
    {
        // Deploy the DAO with `daoOwner` as ROOT
        dao = DAO(
            payable(
                ProxyLib.deployUUPSProxy(
                    address(DAO_BASE), abi.encodeCall(DAO.initialize, ("", daoOwner, address(0x0), ""))
                )
            )
        );

        // Deploy dependencies if not provided
        if (registryAddress == address(0)) {
            registry = AddressRegistryV1(ProxyLib.deployUUPSProxy(address(REGISTRY_BASE), ""));
            registryAddress = address(registry);
        } else {
            registry = AddressRegistryV1(registryAddress);
        }

        if (llamaPayFactoryAddress == address(0)) {
            llamaPayFactory = new MockLlamaPayFactory();
            llamaPayFactoryAddress = address(llamaPayFactory);
        } else {
            llamaPayFactory = MockLlamaPayFactory(llamaPayFactoryAddress);
        }

        // Create test token
        token = new MockERC20("Test USDC", "TUSDC", 6);

        // Deploy PaymentsPlugin
        plugin = PaymentsPluginV1(
            ProxyLib.deployUUPSProxy(
                address(PAYMENTS_PLUGIN_BASE),
                abi.encodeCall(PaymentsPluginV1.initialize, (dao, registryAddress, llamaPayFactoryAddress))
            )
        );

        vm.startPrank(daoOwner);

        // Grant plugin permissions to managers
        if (managers.length > 0) {
            for (uint256 i = 0; i < managers.length; i++) {
                dao.grant(address(plugin), managers[i], plugin.MANAGER_PERMISSION_ID());
            }
        } else {
            // Set alice as the plugin manager if no managers are defined
            dao.grant(address(plugin), alice, plugin.MANAGER_PERMISSION_ID());
        }

        // Grant EXECUTE_PERMISSION to plugin on DAO (critical for DAO actions)
        dao.grant(address(dao), address(plugin), dao.EXECUTE_PERMISSION_ID());

        vm.stopPrank();

        // Give DAO some tokens for testing
        token.mint(address(dao), 10000e6);

        // Labels
        vm.label(address(dao), "DAO");
        vm.label(address(plugin), "PaymentsPlugin");
        vm.label(address(registry), "AddressRegistry");
        vm.label(address(llamaPayFactory), "MockLlamaPayFactory");
        vm.label(address(token), "MockERC20");

        // Moving forward to avoid collisions
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }
}
