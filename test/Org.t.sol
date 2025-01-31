// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/core/Organization.sol";
import "../src/interfaces/IRegistry.sol";
import "../src/interfaces/IPaynest.sol";
import "../src/interfaces/IOrg.sol";
import "../src/utils/Constants.sol";
import "../src/ext_lib/ERC20.sol";

/// @title MockRegistry
/// @notice A simple registry to store user addresses for testing.
contract MockRegistry is IRegistry {
    mapping(string => address) public directory;

    function updateUserAddress(
        string calldata username,
        address userAddress
    ) external override {
        directory[username] = userAddress;
        emit UserAddressUpdated(username, userAddress);
    }

    function getUserAddress(
        string calldata username
    ) external view override returns (address) {
        address userAddress = directory[username];
        require(userAddress != address(0), "User not found");
        return userAddress;
    }
}

/// @title MockPaynest
/// @notice A simple Paynest mock for testing Organization interactions.
contract MockPaynest is IPaynest {
    mapping(address => bool) public tokenSupport;
    uint public fixedFee;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    // Allow contract to receive ETH.
    receive() external payable {}
    fallback() external payable {}

    function addTokenSupport(address tokenAddr) external override {
        tokenSupport[tokenAddr] = true;
    }

    function removeTokenSupport(address tokenAddr) external override {
        tokenSupport[tokenAddr] = false;
    }

    function deployOrganization(string calldata orgName) external override {}

    function redeemSubscriptionFees() external override {}

    function isSupportedToken(
        address token
    ) external view override returns (bool) {
        return tokenSupport[token];
    }

    function canEmergencyWithdraw(
        address caller,
        address tokenAddr
    ) external view override returns (bool) {
        return (caller == owner) && (!tokenSupport[tokenAddr]);
    }

    function getFixedFee() external view override returns (uint) {
        return fixedFee;
    }

    function updateFixedFee(uint fee) external override {
        fixedFee = fee;
    }
}

/// @title MockERC20
/// @notice A minimal ERC20 token used for testing token transfers.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK", 18) {}

    /// @notice Mint tokens to a given address.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Override transfer for testing.
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(msg.sender, to, amount);
        return true;
    }
}

/// @title OrgTest
/// @notice Test suite for the Organization contract with extended branch coverage.
contract OrgTest is Test {
    Organization org;
    MockRegistry mockRegistry;
    MockPaynest mockPaynest;
    MockERC20 token;

    address ownerAddr = address(100);
    address nonOwner = address(101);
    address employee = address(102);

    error InvalidSubscriptionPeriod();


    function setUp() public {
        // Deploy and override Registry at the address defined in Constants.
        mockRegistry = new MockRegistry();
        bytes memory regCode = address(mockRegistry).code;
        vm.etch(Constants.REGISTRY, regCode);

        // Deploy MockPaynest from ownerAddr.
        vm.prank(ownerAddr);
        mockPaynest = new MockPaynest();

        // Deploy a MockERC20 token and add its support in Paynest.
        token = new MockERC20();
        vm.prank(ownerAddr);
        mockPaynest.addTokenSupport(address(token));

        // Deploy Organization with owner set to ownerAddr.
        // Organization uses msg.sender (MockPaynest) as its IPaynest.
        vm.prank(address(mockPaynest));
        org = new Organization(ownerAddr, "TestOrg");

        // Fund Organization with ETH.
        vm.deal(address(org), 10 ether);
    }

    /// ------------------------------------------------------------------------
    /// Basic Organization Tests (already present)
    /// ------------------------------------------------------------------------

    /// @notice Test that the owner can update the organization name.
    function testUpdateOrgName() public {
        vm.prank(ownerAddr);
        org.updateOrgName("NewOrgName");
    }

    /// @notice Test that a non-owner cannot update the organization name.
    function testNonOwnerCannotUpdateOrgName() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        org.updateOrgName("ShouldFail");
    }

    /// @notice Test creating a one-time schedule payment.
    function testCreateSchedule() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("alice", employee);
        vm.prank(ownerAddr);
        uint40 oneTimePayoutDate = uint40(block.timestamp + 31 days);
        uint amount = 1 ether;
        org.createSchedule{value: 0}("alice", amount, address(token), oneTimePayoutDate);

        IOrg.Schedule memory sched = org.getSchedule("alice");
        assertEq(sched.token, address(token));
        assertEq(sched.nextPayout, oneTimePayoutDate);
        assertTrue(sched.isOneTime);
        assertTrue(sched.active);
        assertEq(sched.amount, amount);
    }

    /// @notice Test creating a real-time payment stream.
    function testCreateStream() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("bob", employee);
        vm.prank(ownerAddr);
        uint40 endStream = uint40(block.timestamp + 10 days);
        uint amount = 0.01 ether;
        org.createStream{value: 0}("bob", amount, address(token), endStream);

        IOrg.Stream memory stream = org.getStream("bob");
        assertEq(stream.amount, amount);
        assertEq(stream.token, address(token));
        assertEq(stream.lastPayout, uint40(block.timestamp));
        assertEq(stream.endStream, endStream);
        assertTrue(stream.active);
    }

    /// @notice Test requesting a one-time schedule payout.
    function testRequestSchedulePayout() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("carol", employee);
        vm.prank(ownerAddr);
        uint40 oneTimePayoutDate = uint40(block.timestamp + 1 days);
        uint amount = 1 ether;
        org.createSchedule{value: 0}("carol", amount, address(token), oneTimePayoutDate);

        // Mint tokens into Organization to cover the payout.
        vm.prank(ownerAddr);
        token.mint(address(org), amount);

        vm.warp(block.timestamp + 2 days);
        uint256 preBalance = token.balanceOf(employee);
        vm.prank(employee);
        org.requestSchedulePayout("carol");
        uint256 postBalance = token.balanceOf(employee);
        assertEq(postBalance - preBalance, amount);

        IOrg.Schedule memory sched = org.getSchedule("carol");
        assertTrue(!sched.active);
    }

    /// @notice Test requesting a stream payout after 1 day.
    function testRequestStreamPayout() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("dave", employee);
        vm.prank(ownerAddr);
        uint40 endStream = uint40(block.timestamp + 10 days);
        uint amount = 0.001 ether;
        org.createStream{value: 0}("dave", amount, address(token), endStream);

        uint256 expectedPayout = 86400 * amount; // 1 day's payout.
        vm.prank(ownerAddr);
        token.mint(address(org), expectedPayout);

        uint40 startTime = uint40(block.timestamp);
        vm.warp(startTime + 1 days);
        uint256 preBalance = token.balanceOf(employee);
        vm.prank(employee);
        org.requestStreamPayout("dave");
        uint256 postBalance = token.balanceOf(employee);
        assertEq(postBalance - preBalance, expectedPayout);
    }

    /// @notice Test cancelling a stream using the owner.
    function testCancelStream() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("eve", employee);
        vm.prank(ownerAddr);
        uint40 endStream = uint40(block.timestamp + 5 days);
        uint amount = 0.002 ether;
        org.createStream{value: 0}("eve", amount, address(token), endStream);
        // Mint tokens to cover any payout.
        vm.prank(ownerAddr);
        token.mint(address(org), 1 ether);
        // Ensure the cancel call is made as owner.
        vm.prank(ownerAddr);
        org.cancelStream("eve");
        IOrg.Stream memory stream = org.getStream("eve");
        assertTrue(!stream.active);
    }

    /// @notice Test cancelling a schedule.
    function testCancelSchedule() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("frank", employee);
        vm.prank(ownerAddr);
        uint40 oneTimePayoutDate = uint40(block.timestamp + 10 days);
        uint amount = 1 ether;
        org.createSchedule{value: 0}("frank", amount, address(token), oneTimePayoutDate);

        vm.prank(ownerAddr);
        org.cancelSchedule("frank");

        IOrg.Schedule memory sched = org.getSchedule("frank");
        assertTrue(!sched.active);
    }

    /// @notice Test editing a stream's payment amount.
    function testEditStream() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("grace", employee);
        vm.prank(ownerAddr);
        uint40 endStream = uint40(block.timestamp + 7 days);
        uint amount = 0.001 ether;
        org.createStream{value: 0}("grace", amount, address(token), endStream);

        vm.prank(ownerAddr);
        uint newAmount = 0.002 ether;
        org.editStream("grace", newAmount);

        IOrg.Stream memory stream = org.getStream("grace");
        assertEq(stream.amount, newAmount);
    }

    /// @notice Test editing a schedule's payment amount when allowed.
    function testEditSchedule() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("heidi", employee);
        vm.prank(ownerAddr);
        uint40 payoutDate = uint40(block.timestamp);
        uint amount = 1 ether;
        org.createSchedule{value: 0}("heidi", amount, address(token), payoutDate);

        IOrg.Schedule memory sched = org.getSchedule("heidi");
        vm.warp(uint256(sched.nextPayout) - 2 days);
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.editSchedule("heidi", 2 ether);

        IRegistry(Constants.REGISTRY).updateUserAddress("heidi2", employee);
        vm.prank(ownerAddr);
        org.createSchedule{value: 0}("heidi2", amount, address(token), payoutDate);
        vm.prank(ownerAddr);
        org.editSchedule("heidi2", 2 ether);
        IOrg.Schedule memory sched2 = org.getSchedule("heidi2");
        assertEq(sched2.amount, 2 ether);
    }

    /// @notice Test emergency ETH withdrawal.
    function testEmergencyWithdraw() public {
        vm.prank(ownerAddr);
        mockPaynest.removeTokenSupport(Constants.ETH);
        uint256 orgBalBefore = address(org).balance;
        vm.prank(ownerAddr);
        org.emergencyWithdraw(Constants.ETH);
        assertEq(address(org).balance, 0);
    }

    /// @notice Test subscribing with a nonzero fixed fee.
    function testSubscribe() public {
        vm.prank(ownerAddr);
        mockPaynest.updateFixedFee(1 wei);
        uint40 currentSub = uint40(block.timestamp);
        uint40 validUntil = currentSub + 100 seconds;
        uint orgBalBefore = address(org).balance;
        uint paynestBalBefore = address(mockPaynest).balance;

        vm.prank(ownerAddr);
        org.subscribe(validUntil);

        uint extendedPeriod = validUntil - currentSub;
        uint totalFee = 1 wei * extendedPeriod;
        uint orgBalAfter = address(org).balance;
        uint paynestBalAfter = address(mockPaynest).balance;

        assertEq(orgBalBefore - orgBalAfter, totalFee);
        assertEq(paynestBalAfter - paynestBalBefore, totalFee);
    }

    /// @notice Test getSubscriptionDetails returns the correct subscribedUntil value.
    function testGetSubscriptionDetails() public {
        uint256 sub = org.getSubscriptionDetails();
        assertEq(sub, block.timestamp);
        vm.prank(ownerAddr);
        mockPaynest.updateFixedFee(1 wei);
        uint40 newSub = uint40(block.timestamp + 100);
        vm.prank(ownerAddr);
        org.subscribe(newSub);
        uint256 subAfter = org.getSubscriptionDetails();
        assertEq(subAfter, newSub);
    }

    // ------------------------------------------------------------------------
    // Additional Branch Tests for Uncovered Paths
    // ------------------------------------------------------------------------

    /// @notice Test createSchedule reverts when token is not supported.
    function testCreateScheduleUnsupportedToken() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("unsupported", employee);
        vm.prank(ownerAddr);
        vm.expectRevert(); // Expect revert because token is unsupported.
        org.createSchedule{value: 0}("unsupported", 1 ether, address(0xBAD), uint40(block.timestamp + 31 days));
    }

    /// @notice Test createSchedule reverts when amount is zero.
    function testCreateScheduleZeroAmount() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("zeroAmount", employee);
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.createSchedule{value: 0}("zeroAmount", 0, address(token), uint40(block.timestamp + 31 days));
    }

    /// @notice Test createSchedule reverts when a schedule is already active.
    function testCreateScheduleAlreadyActive() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("duplicate", employee);
        vm.prank(ownerAddr);
        org.createSchedule{value: 0}("duplicate", 1 ether, address(token), uint40(block.timestamp + 31 days));
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.createSchedule{value: 0}("duplicate", 1 ether, address(token), uint40(block.timestamp + 31 days));
    }

    /// @notice Test createSchedule creates a recurring schedule when oneTimePayoutDate <= block.timestamp.
    function testCreateRecurringSchedule() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("recurring2", employee);
        vm.prank(ownerAddr);
        uint40 recurringDate = uint40(block.timestamp); // Not in the future
        org.createSchedule{value: 0}("recurring2", 1 ether, address(token), recurringDate);
        IOrg.Schedule memory sched = org.getSchedule("recurring2");
        assertEq(sched.nextPayout, uint40(block.timestamp + 30 days));
        assertTrue(!sched.isOneTime);
    }

    /// @notice Test createStream reverts when token is not supported.
    function testCreateStreamUnsupportedToken() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("streamUnsupported", employee);
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.createStream{value: 0}("streamUnsupported", 1 ether, address(0xBAD), uint40(block.timestamp + 10 days));
    }

    /// @notice Test createStream reverts when amount is zero.
    function testCreateStreamZeroAmount() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("streamZero", employee);
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.createStream{value: 0}("streamZero", 0, address(token), uint40(block.timestamp + 10 days));
    }

    /// @notice Test createStream reverts when endStream <= block.timestamp.
    function testCreateStreamInvalidEnd() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("streamInvalidEnd", employee);
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.createStream{value: 0}("streamInvalidEnd", 1 ether, address(token), uint40(block.timestamp));
    }

    /// @notice Test createStream reverts when a stream is already active.
    function testCreateStreamAlreadyActive() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("streamDuplicate", employee);
        vm.prank(ownerAddr);
        org.createStream{value: 0}("streamDuplicate", 1 ether, address(token), uint40(block.timestamp + 10 days));
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.createStream{value: 0}("streamDuplicate", 1 ether, address(token), uint40(block.timestamp + 10 days));
    }

    /// @notice Test requestSchedulePayout reverts if called before nextPayout.
    function testRequestSchedulePayoutTooEarly() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("earlySchedule", employee);
        vm.prank(ownerAddr);
        uint40 oneTimePayoutDate = uint40(block.timestamp + 1 days);
        org.createSchedule{value: 0}("earlySchedule", 1 ether, address(token), oneTimePayoutDate);
        vm.warp(block.timestamp + 12 hours);
        vm.prank(employee);
        vm.expectRevert();
        org.requestSchedulePayout("earlySchedule");
    }

    /// @notice Test requestStreamPayout after stream end calculates remaining payout and deactivates the stream.
    function testRequestStreamPayoutAfterEnd() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("streamAfter", employee);
        vm.prank(ownerAddr);
        uint40 endStream = uint40(block.timestamp + 2 days);
        uint amount = 0.001 ether;
        org.createStream{value: 0}("streamAfter", amount, address(token), endStream);
        uint256 expectedPayout = (endStream - uint40(block.timestamp)) * amount;
        vm.prank(ownerAddr);
        token.mint(address(org), expectedPayout);
        vm.warp(endStream + 1);
        uint256 preBalance = token.balanceOf(employee);
        vm.prank(employee);
        org.requestStreamPayout("streamAfter");
        uint256 postBalance = token.balanceOf(employee);
        assertEq(postBalance - preBalance, expectedPayout);
        IOrg.Stream memory stream = org.getStream("streamAfter");
        assertTrue(!stream.active);
    }

    /// @notice Test editStream reverts when new amount is zero.
    function testEditStreamZeroAmount() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("editStreamZero", employee);
        vm.prank(ownerAddr);
        uint40 endStream = uint40(block.timestamp + 5 days);
        org.createStream{value: 0}("editStreamZero", 1 ether, address(token), endStream);
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.editStream("editStreamZero", 0);
    }

    /// @notice Test editStream reverts when the stream is inactive.
    function testEditStreamInactive() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("editStreamInactive", employee);
        vm.prank(ownerAddr);
        uint40 endStream = uint40(block.timestamp + 5 days);
        org.createStream{value: 0}("editStreamInactive", 1 ether, address(token), endStream);
        vm.prank(ownerAddr);
        org.cancelStream("editStreamInactive");
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.editStream("editStreamInactive", 2 ether);
    }

    /// @notice Test editSchedule reverts when new amount is zero.
    function testEditScheduleZeroAmount() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("editScheduleZero", employee);
        vm.prank(ownerAddr);
        uint40 oneTimePayoutDate = uint40(block.timestamp + 31 days);
        org.createSchedule{value: 0}("editScheduleZero", 1 ether, address(token), oneTimePayoutDate);
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.editSchedule("editScheduleZero", 0);
    }

    /// @notice Test editSchedule reverts when the schedule is inactive.
    function testEditScheduleInactive() public {
        IRegistry(Constants.REGISTRY).updateUserAddress("editScheduleInactive", employee);
        vm.prank(ownerAddr);
        uint40 oneTimePayoutDate = uint40(block.timestamp + 1 days);
        org.createSchedule{value: 0}("editScheduleInactive", 1 ether, address(token), oneTimePayoutDate);
        vm.prank(ownerAddr);
        token.mint(address(org), 1 ether);
        vm.warp(block.timestamp + 2 days);
        vm.prank(employee);
        org.requestSchedulePayout("editScheduleInactive");
        vm.prank(ownerAddr);
        vm.expectRevert();
        org.editSchedule("editScheduleInactive", 2 ether);
    }

    /// @notice Test that calling subscribe with a validUntil lower than the current subscribedUntil reverts.
    /// First, we call subscribe with a higher value to update subscribedUntil. Then, we attempt to call subscribe
    /// with a lower value (e.g., 140 < 150) and expect a revert.
    function testSubscribeInvalid() public {
        // Warp to a known time.
        vm.warp(100);
        // Update fixed fee so that subscribe does not simply return.
        vm.prank(ownerAddr);
        mockPaynest.updateFixedFee(1);
        
        // First call: subscribe with 150. Since Organization was deployed earlier (with subscribedUntil set to its block.timestamp),
        // and our current block.timestamp is now 100, the first valid call sets subscribedUntil to 150.
        vm.prank(ownerAddr);
        org.subscribe(150);
        
        // Second call: try to update subscription to a lower value (e.g., 140) which should revert.
        vm.prank(ownerAddr);
        vm.expectRevert(abi.encodeWithSelector(InvalidSubscriptionPeriod.selector));
        org.subscribe(140);
    }
}
