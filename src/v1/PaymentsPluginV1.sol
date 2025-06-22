// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {DAO, IDAO, Action} from "@aragon/osx/core/dao/DAO.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IPaymentsV1} from "./interfaces/IPaymentsV1.sol";
import {IRegistryV1} from "./interfaces/IRegistryV1.sol";
import {ILlamaPayFactory, ILlamaPay, IERC20WithDecimals} from "./interfaces/ILlamaPay.sol";

/// @title PaymentsPluginV1
/// @notice Aragon plugin for managing streaming and scheduled payments with username resolution
/// @dev Implements the IPaymentsV1 interface and integrates with LlamaPay for streaming and AddressRegistry for usernames
contract PaymentsPluginV1 is PluginUUPSUpgradeable, IPaymentsV1 {
    /// @notice Permission required to manage payments
    bytes32 public constant MANAGER_PERMISSION_ID = keccak256("MANAGER_PERMISSION");

    /// @notice Address registry for username resolution
    IRegistryV1 public registry;

    /// @notice LlamaPay factory for creating streaming contracts
    ILlamaPayFactory public llamaPayFactory;

    /// @notice Mapping from username to stream data
    mapping(string => Stream) public streams;

    /// @notice Mapping from username to stream recipient addresses
    mapping(string => address) public streamRecipients;

    /// @notice Mapping from username to schedule data
    mapping(string => Schedule) public schedules;

    /// @notice Cache of token addresses to their LlamaPay contracts
    mapping(address => address) public tokenToLlamaPay;

    /// @notice Storage gap for upgrades
    uint256[46] private __gap;

    /// @notice Constructor disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice Custom errors for gas-efficient error handling
    error UsernameNotFound();
    error StreamNotActive();
    error ScheduleNotActive();
    error PaymentNotDue();
    error InsufficientDAOBalance();
    error LlamaPayOperationFailed();
    error InvalidToken();
    error InvalidAmount();
    error StreamAlreadyExists();
    error ScheduleAlreadyExists();
    error InvalidEndDate();
    error InvalidFirstPaymentDate();
    error AmountPerSecondOverflow();
    error UnauthorizedMigration();
    error StreamNotFound();
    error NoMigrationNeeded();

    /// @notice Initialize the plugin
    /// @param _dao The DAO this plugin belongs to
    /// @param _registryAddress Address of the username registry
    /// @param _llamaPayFactoryAddress Address of the LlamaPay factory
    function initialize(IDAO _dao, address _registryAddress, address _llamaPayFactoryAddress) external initializer {
        __PluginUUPSUpgradeable_init(_dao);

        if (_registryAddress == address(0)) revert InvalidToken();
        if (_llamaPayFactoryAddress == address(0)) revert InvalidToken();

        registry = IRegistryV1(_registryAddress);
        llamaPayFactory = ILlamaPayFactory(_llamaPayFactoryAddress);
    }

    /// @notice Create a new streaming payment
    /// @param username The username to stream to
    /// @param amount Total amount to stream over the duration
    /// @param token Token contract address
    /// @param endStream Timestamp when stream should end
    function createStream(string calldata username, uint256 amount, address token, uint40 endStream)
        external
        auth(MANAGER_PERMISSION_ID)
    {
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) revert InvalidToken();
        if (endStream <= block.timestamp) revert InvalidEndDate();
        if (streams[username].active) revert StreamAlreadyExists();

        // Resolve username to address
        address recipient = _resolveUsername(username);

        // Get or deploy LlamaPay contract for token
        address llamaPayContract = _getLlamaPayContract(token);

        // Calculate amount per second with proper decimals
        uint256 duration = endStream - block.timestamp;
        uint216 amountPerSec = _calculateAmountPerSec(amount, duration, token);

        // Ensure DAO has funds and approve LlamaPay
        _ensureDAOApproval(token, llamaPayContract, amount);

        // Execute DAO actions to deposit and create stream
        _depositToLlamaPay(token, llamaPayContract, amount);
        _createLlamaPayStream(llamaPayContract, recipient, amountPerSec, username);

        // Store stream metadata
        streams[username] = Stream({
            token: token,
            endDate: endStream,
            active: true,
            amount: amountPerSec,
            lastPayout: uint40(block.timestamp)
        });
        streamRecipients[username] = recipient;

        emit StreamActive(username, token, endStream, amount);
    }

    /// @notice Cancel an existing stream
    /// @param username The username to cancel stream for
    function cancelStream(string calldata username) external auth(MANAGER_PERMISSION_ID) {
        Stream storage stream = streams[username];
        if (!stream.active) revert StreamNotActive();

        // Get stored recipient address (for streams that may have different recipient than current username)
        address recipient = streamRecipients[username];

        // Get LlamaPay contract
        address llamaPayContract = tokenToLlamaPay[stream.token];

        // Cancel the LlamaPay stream
        _cancelLlamaPayStream(llamaPayContract, recipient, stream.amount);

        // Withdraw remaining funds back to DAO
        _withdrawRemainingFunds(llamaPayContract);

        // Clear stream metadata
        stream.active = false;
        delete streamRecipients[username];

        emit PaymentStreamCancelled(username, stream.token);
    }

    /// @notice Edit an existing stream amount
    /// @param username The username to edit stream for
    /// @param amount New total amount for the stream
    function editStream(string calldata username, uint256 amount) external auth(MANAGER_PERMISSION_ID) {
        if (amount == 0) revert InvalidAmount();

        Stream storage stream = streams[username];
        if (!stream.active) revert StreamNotActive();

        // Resolve username to current address
        address recipient = _resolveUsername(username);

        // Get LlamaPay contract
        address llamaPayContract = tokenToLlamaPay[stream.token];

        // Cancel existing stream
        _cancelLlamaPayStream(llamaPayContract, recipient, stream.amount);

        // Calculate new amount per second
        uint256 remainingDuration = stream.endDate - block.timestamp;
        uint216 newAmountPerSec = _calculateAmountPerSec(amount, remainingDuration, stream.token);

        // Create new stream with updated amount
        _createLlamaPayStream(llamaPayContract, recipient, newAmountPerSec, username);

        // Update stream metadata
        stream.amount = newAmountPerSec;

        emit StreamUpdated(username, stream.token, amount);
    }

    /// @notice Request payout from a stream
    /// @param username The username to request payout for
    /// @return amount The amount paid out
    function requestStreamPayout(string calldata username) external payable returns (uint256 amount) {
        // Resolve username first (will revert with UsernameNotFound if invalid)
        address recipient = _resolveUsername(username);

        // Check if stream is active
        Stream storage stream = streams[username];
        if (!stream.active) revert StreamNotActive();

        // Get LlamaPay contract
        address llamaPayContract = tokenToLlamaPay[stream.token];

        // Get withdrawable amount before withdrawal
        (uint256 withdrawableAmount,,) =
            ILlamaPay(llamaPayContract).withdrawable(address(dao()), recipient, stream.amount);

        // Withdraw on behalf of recipient
        if (withdrawableAmount > 0) {
            ILlamaPay(llamaPayContract).withdraw(address(dao()), recipient, stream.amount);
        }

        // Update last payout timestamp
        stream.lastPayout = uint40(block.timestamp);

        emit StreamPayout(username, stream.token, withdrawableAmount);
        return withdrawableAmount;
    }

    /// @notice Create a new scheduled payment
    /// @param username The username to schedule payments for
    /// @param amount Amount per payment
    /// @param token Token contract address
    /// @param interval Payment interval
    /// @param isOneTime Whether this is a one-time payment
    /// @param firstPaymentDate When the first payment should occur
    function createSchedule(
        string calldata username,
        uint256 amount,
        address token,
        IntervalType interval,
        bool isOneTime,
        uint40 firstPaymentDate
    ) external auth(MANAGER_PERMISSION_ID) {
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) revert InvalidToken();
        if (firstPaymentDate <= block.timestamp) revert InvalidFirstPaymentDate();
        if (schedules[username].active) revert ScheduleAlreadyExists();

        // Validate username exists
        _resolveUsername(username);

        // Store schedule metadata
        schedules[username] = Schedule({
            token: token,
            amount: amount,
            interval: interval,
            isOneTime: isOneTime,
            active: true,
            firstPaymentDate: firstPaymentDate,
            nextPayout: firstPaymentDate
        });

        emit ScheduleActive(username, token, amount, interval, isOneTime, firstPaymentDate);
    }

    /// @notice Cancel an existing schedule
    /// @param username The username to cancel schedule for
    function cancelSchedule(string calldata username) external auth(MANAGER_PERMISSION_ID) {
        Schedule storage schedule = schedules[username];
        if (!schedule.active) revert ScheduleNotActive();

        // Mark as inactive
        schedule.active = false;

        emit PaymentScheduleCancelled(username, schedule.token);
    }

    /// @notice Edit an existing schedule amount
    /// @param username The username to edit schedule for
    /// @param amount New amount per payment
    function editSchedule(string calldata username, uint256 amount) external auth(MANAGER_PERMISSION_ID) {
        if (amount == 0) revert InvalidAmount();

        Schedule storage schedule = schedules[username];
        if (!schedule.active) revert ScheduleNotActive();

        // Update schedule amount
        schedule.amount = amount;

        emit ScheduleUpdated(username, schedule.token, amount);
    }

    /// @notice Request payout from a schedule
    /// @param username The username to request payout for
    function requestSchedulePayout(string calldata username) external payable {
        Schedule storage schedule = schedules[username];
        if (!schedule.active) revert ScheduleNotActive();
        if (block.timestamp < schedule.nextPayout) revert PaymentNotDue();

        // Resolve username to current address
        address recipient = _resolveUsername(username);

        // Calculate how many periods have passed (eager payout)
        uint256 periodsToPayFor = 1;
        if (!schedule.isOneTime) {
            uint256 intervalSeconds = _getIntervalSeconds(schedule.interval);
            uint256 timePassed = block.timestamp - schedule.nextPayout;
            periodsToPayFor = 1 + (timePassed / intervalSeconds);
        }

        // Calculate total amount to pay
        uint256 totalAmount = schedule.amount * periodsToPayFor;

        // Execute DAO action to transfer tokens
        _executeDirectTransfer(schedule.token, recipient, totalAmount);

        // Update schedule state
        if (schedule.isOneTime) {
            schedule.active = false;
        } else {
            uint256 intervalSeconds = _getIntervalSeconds(schedule.interval);
            schedule.nextPayout = uint40(schedule.nextPayout + (periodsToPayFor * intervalSeconds));
        }

        emit SchedulePayout(username, schedule.token, totalAmount, periodsToPayFor);
    }

    /// @notice Get stream data for a username
    /// @param username The username to get stream for
    /// @return stream The stream data
    function getStream(string calldata username) external view returns (Stream memory stream) {
        return streams[username];
    }

    /// @notice Get schedule data for a username
    /// @param username The username to get schedule for
    /// @return schedule The schedule data
    function getSchedule(string calldata username) external view returns (Schedule memory schedule) {
        return schedules[username];
    }

    /// @notice Migrate user's stream to their current address
    /// @param username The username to migrate stream for
    function migrateStream(string calldata username) external {
        // Only current address holder can migrate
        address currentAddress = registry.getUserAddress(username);
        if (msg.sender != currentAddress) revert UnauthorizedMigration();

        Stream storage stream = streams[username];
        if (!stream.active) revert StreamNotFound();

        // Get the current stream recipient (where the stream is actually pointing)
        address oldStreamRecipient = streamRecipients[username];

        // Check if migration is needed (stream tied to old address)
        if (oldStreamRecipient == currentAddress) revert NoMigrationNeeded();

        // Migrate stream from current stream recipient to new current address
        _migrateStreamToNewAddress(username, oldStreamRecipient, currentAddress);

        emit StreamMigrated(username, oldStreamRecipient, currentAddress);
    }

    /// @notice Resolve username to address via registry
    /// @param username The username to resolve
    /// @return recipient The resolved address
    function _resolveUsername(string calldata username) internal view returns (address recipient) {
        recipient = registry.getUserAddress(username);
        if (recipient == address(0)) revert UsernameNotFound();
        return recipient;
    }

    /// @notice Get or deploy LlamaPay contract for a token
    /// @param token The token address
    /// @return llamaPayContract The LlamaPay contract address
    function _getLlamaPayContract(address token) internal returns (address llamaPayContract) {
        llamaPayContract = tokenToLlamaPay[token];
        if (llamaPayContract == address(0)) {
            (address predicted, bool deployed) = llamaPayFactory.getLlamaPayContractByToken(token);
            if (!deployed) {
                llamaPayContract = llamaPayFactory.createLlamaPayContract(token);
            } else {
                llamaPayContract = predicted;
            }
            tokenToLlamaPay[token] = llamaPayContract;
        }
        return llamaPayContract;
    }

    /// @notice Calculate amount per second with proper decimals for LlamaPay
    /// @param totalAmount Total amount to stream
    /// @param duration Duration in seconds
    /// @param token Token contract address
    /// @return amountPerSec Amount per second in LlamaPay's 20-decimal precision
    function _calculateAmountPerSec(uint256 totalAmount, uint256 duration, address token)
        internal
        view
        returns (uint216 amountPerSec)
    {
        // Get token decimals
        uint8 tokenDecimals = IERC20WithDecimals(token).decimals();
        uint256 decimalsMultiplier = 10 ** (20 - tokenDecimals);

        // Convert to per-second rate with 20 decimal precision
        uint256 amountPerSecRaw = (totalAmount * decimalsMultiplier) / duration;

        // Ensure fits in uint216
        if (amountPerSecRaw > type(uint216).max) revert AmountPerSecondOverflow();

        return uint216(amountPerSecRaw);
    }

    /// @notice Ensure DAO has approved LlamaPay contract to spend tokens
    /// @param token Token contract address
    /// @param llamaPayContract LlamaPay contract address
    /// @param amount Amount that will be spent
    function _ensureDAOApproval(address token, address llamaPayContract, uint256 amount) internal {
        // Check current allowance
        uint256 currentAllowance = IERC20WithDecimals(token).allowance(address(dao()), llamaPayContract);

        if (currentAllowance < amount) {
            // Create action to approve LlamaPay contract
            Action[] memory actions = new Action[](1);
            actions[0].to = token;
            actions[0].value = 0;
            actions[0].data = abi.encodeCall(IERC20WithDecimals.approve, (llamaPayContract, type(uint256).max));

            // Execute via DAO
            DAO(payable(address(dao()))).execute(keccak256(abi.encodePacked("approve-llamapay-", token)), actions, 0);
        }
    }

    /// @notice Deposit tokens to LlamaPay contract
    /// @param token Token contract address
    /// @param llamaPayContract LlamaPay contract address
    /// @param amount Amount to deposit
    function _depositToLlamaPay(address token, address llamaPayContract, uint256 amount) internal {
        // Create action to deposit to LlamaPay
        Action[] memory actions = new Action[](1);
        actions[0].to = llamaPayContract;
        actions[0].value = 0;
        actions[0].data = abi.encodeCall(ILlamaPay.deposit, (amount));

        // Execute via DAO
        DAO(payable(address(dao()))).execute(keccak256(abi.encodePacked("deposit-llamapay-", token)), actions, 0);
    }

    /// @notice Create a LlamaPay stream
    /// @param llamaPayContract LlamaPay contract address
    /// @param recipient Stream recipient
    /// @param amountPerSec Amount per second
    /// @param username Username for the reason
    function _createLlamaPayStream(
        address llamaPayContract,
        address recipient,
        uint216 amountPerSec,
        string calldata username
    ) internal {
        // Create action to create stream
        Action[] memory actions = new Action[](1);
        actions[0].to = llamaPayContract;
        actions[0].value = 0;
        actions[0].data = abi.encodeCall(
            ILlamaPay.createStreamWithReason,
            (recipient, amountPerSec, string(abi.encodePacked("PayNest stream for ", username)))
        );

        // Execute via DAO
        DAO(payable(address(dao()))).execute(keccak256(abi.encodePacked("create-stream-", username)), actions, 0);
    }

    /// @notice Cancel a LlamaPay stream
    /// @param llamaPayContract LlamaPay contract address
    /// @param recipient Stream recipient
    /// @param amountPerSec Amount per second that was being streamed
    function _cancelLlamaPayStream(address llamaPayContract, address recipient, uint216 amountPerSec) internal {
        // Create action to cancel stream
        Action[] memory actions = new Action[](1);
        actions[0].to = llamaPayContract;
        actions[0].value = 0;
        actions[0].data = abi.encodeCall(ILlamaPay.cancelStream, (recipient, amountPerSec));

        // Execute via DAO
        DAO(payable(address(dao()))).execute(
            keccak256(abi.encodePacked("cancel-stream-", recipient, amountPerSec)), actions, 0
        );
    }

    /// @notice Withdraw remaining funds from LlamaPay back to DAO
    /// @param llamaPayContract LlamaPay contract address
    function _withdrawRemainingFunds(address llamaPayContract) internal {
        // Create action to withdraw all remaining funds
        Action[] memory actions = new Action[](1);
        actions[0].to = llamaPayContract;
        actions[0].value = 0;
        actions[0].data = abi.encodeCall(ILlamaPay.withdrawPayerAll, ());

        // Execute via DAO
        DAO(payable(address(dao()))).execute(keccak256(abi.encodePacked("withdraw-all-", llamaPayContract)), actions, 0);
    }

    /// @notice Execute direct token transfer from DAO to recipient
    /// @param token Token contract address
    /// @param recipient Recipient address
    /// @param amount Amount to transfer
    function _executeDirectTransfer(address token, address recipient, uint256 amount) internal {
        // Create action to transfer tokens
        Action[] memory actions = new Action[](1);
        actions[0].to = token;
        actions[0].value = 0;
        actions[0].data = abi.encodeCall(IERC20WithDecimals.transfer, (recipient, amount));

        // Execute via DAO
        DAO(payable(address(dao()))).execute(
            keccak256(abi.encodePacked("transfer-", token, recipient, amount)), actions, 0
        );
    }

    /// @notice Get interval duration in seconds
    /// @param interval The interval type
    /// @return seconds Duration in seconds
    function _getIntervalSeconds(IntervalType interval) internal pure returns (uint256) {
        if (interval == IntervalType.Weekly) return 7 days;
        if (interval == IntervalType.Monthly) return 30 days;
        if (interval == IntervalType.Quarterly) return 90 days;
        if (interval == IntervalType.Yearly) return 365 days;
        revert InvalidAmount(); // Should never reach here
    }

    /// @notice Internal function to migrate stream to new address
    /// @param username The username being migrated
    /// @param oldAddress The previous address
    /// @param newAddress The new address
    function _migrateStreamToNewAddress(string calldata username, address oldAddress, address newAddress) internal {
        Stream storage stream = streams[username];

        // Get LlamaPay contract for the token
        address llamaPayContract = tokenToLlamaPay[stream.token];

        // Cancel old LlamaPay stream (returns funds to DAO)
        _cancelLlamaPayStream(llamaPayContract, oldAddress, stream.amount);

        // Create new LlamaPay stream for new address with same parameters
        _createLlamaPayStream(llamaPayContract, newAddress, stream.amount, username);

        // Update stream recipient record
        streamRecipients[username] = newAddress;
    }

    /// @notice Emitted when a stream is migrated to a new address
    /// @param username The username whose stream was migrated
    /// @param oldAddress The previous address
    /// @param newAddress The new address
    event StreamMigrated(string indexed username, address indexed oldAddress, address indexed newAddress);
}
