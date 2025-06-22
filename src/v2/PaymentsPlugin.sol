// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

import {DAO, IDAO, Action} from "@aragon/osx/core/dao/DAO.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {IPayments} from "./interfaces/IPayments.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {ILlamaPayFactory, ILlamaPay, IERC20WithDecimals} from "./interfaces/ILlamaPay.sol";

/// @title PaymentsPlugin
/// @notice Aragon plugin for managing multiple streaming and scheduled payments with username resolution
/// @dev V2.0 implementation supporting unlimited streams and schedules per user with flow-based streaming architecture
/// @custom:version 2.0.0
contract PaymentsPlugin is PluginUUPSUpgradeable, IPayments {
    /// @notice Permission required to manage payments
    bytes32 public constant MANAGER_PERMISSION_ID = keccak256("MANAGER_PERMISSION");

    /// @notice Maximum number of streams per user to prevent gas exhaustion
    uint256 public constant MAX_STREAMS_PER_USER = 50;

    /// @notice Maximum number of schedules per user to prevent gas exhaustion
    uint256 public constant MAX_SCHEDULES_PER_USER = 20;

    /// @notice Default funding period for indefinite streams (6 months)
    uint256 public constant DEFAULT_FUNDING_PERIOD = 180 days;

    /// @notice Address registry for username resolution
    IRegistry public registry;

    /// @notice LlamaPay factory for creating streaming contracts
    ILlamaPayFactory public llamaPayFactory;

    /// @notice Mapping from username to array of stream IDs
    mapping(string => bytes32[]) public userStreamIds;

    /// @notice Mapping from username to stream ID to stream data
    mapping(string => mapping(bytes32 => Stream)) public streams;

    /// @notice Mapping from username to stream ID to recipient address at stream creation
    mapping(string => mapping(bytes32 => address)) public streamRecipients;

    /// @notice Mapping from username to array of schedule IDs
    mapping(string => bytes32[]) public userScheduleIds;

    /// @notice Mapping from username to schedule ID to schedule data
    mapping(string => mapping(bytes32 => Schedule)) public schedules;

    /// @notice Cache of token addresses to their LlamaPay contracts
    mapping(address => address) public tokenToLlamaPay;

    /// @notice Storage gap for upgrades
    uint256[40] private __gap;

    /// @notice Constructor disables initializers for the implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice Custom errors for gas-efficient error handling
    error UsernameNotFound();
    error StreamIdNotFound();
    error ScheduleIdNotFound();
    error StreamNotActive();
    error ScheduleNotActive();
    error PaymentNotDue();
    error InsufficientDAOBalance();
    error LlamaPayOperationFailed();
    error InvalidToken();
    error InvalidAmount();
    error InvalidFlowRate();
    error FlowRateExceedsMaximum();
    error InsufficientFundingForFlowRate();
    error LlamaPayStreamNotFound();
    error InvalidEndDate();
    error InvalidFirstPaymentDate();
    error AmountPerSecondOverflow();
    error UnauthorizedMigration();
    error MigrationNotRequired();
    error MigrationAlreadyInProgress();
    error BulkMigrationPartialFailure();
    error RecipientResolutionFailed();
    error TokenNotSupported();
    error PaymentOperationFailed();
    error MaximumStreamsPerUserExceeded();
    error MaximumSchedulesPerUserExceeded();
    error DuplicateStreamParameters();
    error StreamStateMismatch();
    error ScheduleExecutionFailed();

    /// @notice Initialize the plugin
    /// @param _dao The DAO this plugin belongs to
    /// @param _registryAddress Address of the username registry
    /// @param _llamaPayFactoryAddress Address of the LlamaPay factory
    function initialize(IDAO _dao, address _registryAddress, address _llamaPayFactoryAddress) external initializer {
        __PluginUUPSUpgradeable_init(_dao);

        if (_registryAddress == address(0)) revert InvalidToken();
        if (_llamaPayFactoryAddress == address(0)) revert InvalidToken();

        registry = IRegistry(_registryAddress);
        llamaPayFactory = ILlamaPayFactory(_llamaPayFactoryAddress);
    }

    /// @inheritdoc IPayments
    function createStream(string calldata username, address token, uint216 amountPerSec)
        external
        auth(MANAGER_PERMISSION_ID)
        returns (bytes32 streamId)
    {
        if (amountPerSec == 0) revert InvalidFlowRate();
        if (token == address(0)) revert InvalidToken();
        if (userStreamIds[username].length >= MAX_STREAMS_PER_USER) revert MaximumStreamsPerUserExceeded();

        // Resolve username to current recipient address
        address recipient = _resolveUsername(username);

        // Generate unique stream ID
        streamId = _generateStreamId(username, token, amountPerSec, block.timestamp, userStreamIds[username].length);

        // Check for duplicate stream parameters to prevent conflicts
        bytes32[] memory existingIds = userStreamIds[username];
        for (uint256 i = 0; i < existingIds.length; i++) {
            Stream storage existingStream = streams[username][existingIds[i]];
            if (
                existingStream.token == token && existingStream.amountPerSec == amountPerSec
                    && existingStream.state == StreamState.Active
            ) {
                revert DuplicateStreamParameters();
            }
        }

        // Get or deploy LlamaPay contract for token
        address llamaPayContract = _getLlamaPayContract(token);

        // Calculate recommended funding amount for indefinite stream
        uint256 fundingAmount = _calculateRecommendedFunding(amountPerSec, token);

        // Execute DAO actions to fund and create LlamaPay stream
        _ensureDAOApproval(token, llamaPayContract, fundingAmount);
        _depositToLlamaPay(token, llamaPayContract, fundingAmount);
        _createLlamaPayStream(llamaPayContract, recipient, amountPerSec, username, streamId);

        // Store stream metadata
        streams[username][streamId] = Stream({
            token: token,
            amountPerSec: amountPerSec,
            state: StreamState.Active,
            startTime: uint40(block.timestamp)
        });
        streamRecipients[username][streamId] = recipient;
        userStreamIds[username].push(streamId);

        emit StreamCreated(username, streamId, token, amountPerSec, recipient);
        return streamId;
    }

    /// @inheritdoc IPayments
    function updateFlowRate(string calldata username, bytes32 streamId, uint216 newAmountPerSec)
        external
        auth(MANAGER_PERMISSION_ID)
    {
        if (newAmountPerSec == 0) revert InvalidFlowRate();

        Stream storage stream = streams[username][streamId];
        if (stream.token == address(0)) revert StreamIdNotFound();
        if (stream.state != StreamState.Active) revert StreamNotActive();

        uint216 oldAmountPerSec = stream.amountPerSec;
        address recipient = streamRecipients[username][streamId];
        address llamaPayContract = tokenToLlamaPay[stream.token];

        // Use LlamaPay's native modifyStream for efficient update
        _modifyLlamaPayStream(
            llamaPayContract, recipient, oldAmountPerSec, recipient, newAmountPerSec, username, streamId
        );

        // Update stream metadata
        stream.amountPerSec = newAmountPerSec;

        emit FlowRateUpdated(username, streamId, oldAmountPerSec, newAmountPerSec);
    }

    /// @inheritdoc IPayments
    function pauseStream(string calldata username, bytes32 streamId) external auth(MANAGER_PERMISSION_ID) {
        Stream storage stream = streams[username][streamId];
        if (stream.token == address(0)) revert StreamIdNotFound();
        if (stream.state != StreamState.Active) revert StreamNotActive();

        address recipient = streamRecipients[username][streamId];
        address llamaPayContract = tokenToLlamaPay[stream.token];

        // Pause by setting flow rate to 0, maintaining metadata
        _modifyLlamaPayStream(llamaPayContract, recipient, stream.amountPerSec, recipient, 0, username, streamId);

        StreamState oldState = stream.state;
        stream.state = StreamState.Paused;

        emit StreamStateChanged(username, streamId, oldState, StreamState.Paused);
    }

    /// @inheritdoc IPayments
    function resumeStream(string calldata username, bytes32 streamId) external auth(MANAGER_PERMISSION_ID) {
        Stream storage stream = streams[username][streamId];
        if (stream.token == address(0)) revert StreamIdNotFound();
        if (stream.state != StreamState.Paused) revert StreamStateMismatch();

        address recipient = streamRecipients[username][streamId];
        address llamaPayContract = tokenToLlamaPay[stream.token];

        // Resume by restoring original flow rate from metadata
        _modifyLlamaPayStream(llamaPayContract, recipient, 0, recipient, stream.amountPerSec, username, streamId);

        StreamState oldState = stream.state;
        stream.state = StreamState.Active;

        emit StreamStateChanged(username, streamId, oldState, StreamState.Active);
    }

    /// @inheritdoc IPayments
    function cancelStream(string calldata username, bytes32 streamId) external auth(MANAGER_PERMISSION_ID) {
        Stream storage stream = streams[username][streamId];
        if (stream.token == address(0)) revert StreamIdNotFound();
        if (stream.state == StreamState.Cancelled) revert StreamStateMismatch();

        address recipient = streamRecipients[username][streamId];
        address llamaPayContract = tokenToLlamaPay[stream.token];

        // Cancel the LlamaPay stream (handles both active and paused states)
        uint216 currentAmountPerSec = stream.state == StreamState.Active ? stream.amountPerSec : 0;
        _cancelLlamaPayStream(llamaPayContract, recipient, currentAmountPerSec);

        // Withdraw remaining funds back to DAO
        _withdrawRemainingFunds(llamaPayContract);

        StreamState oldState = stream.state;
        stream.state = StreamState.Cancelled;

        emit StreamStateChanged(username, streamId, oldState, StreamState.Cancelled);
    }

    /// @inheritdoc IPayments
    function createSchedule(
        string calldata username,
        address token,
        uint256 amount,
        IntervalType interval,
        bool isOneTime,
        uint40 firstPaymentDate
    ) external auth(MANAGER_PERMISSION_ID) returns (bytes32 scheduleId) {
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) revert InvalidToken();
        if (firstPaymentDate <= block.timestamp) revert InvalidFirstPaymentDate();
        if (userScheduleIds[username].length >= MAX_SCHEDULES_PER_USER) revert MaximumSchedulesPerUserExceeded();

        // Validate username exists
        _resolveUsername(username);

        // Generate unique schedule ID
        scheduleId =
            _generateScheduleId(username, token, amount, interval, block.timestamp, userScheduleIds[username].length);

        // Store schedule metadata
        schedules[username][scheduleId] = Schedule({
            token: token,
            amount: amount,
            interval: interval,
            isOneTime: isOneTime,
            active: true,
            firstPaymentDate: firstPaymentDate,
            nextPayout: firstPaymentDate
        });
        userScheduleIds[username].push(scheduleId);

        emit ScheduleCreated(username, scheduleId, token, amount, interval, isOneTime, firstPaymentDate);
        return scheduleId;
    }

    /// @inheritdoc IPayments
    function updateScheduleAmount(string calldata username, bytes32 scheduleId, uint256 newAmount)
        external
        auth(MANAGER_PERMISSION_ID)
    {
        if (newAmount == 0) revert InvalidAmount();

        Schedule storage schedule = schedules[username][scheduleId];
        if (schedule.token == address(0)) revert ScheduleIdNotFound();
        if (!schedule.active) revert ScheduleNotActive();

        schedule.amount = newAmount;
    }

    /// @inheritdoc IPayments
    function updateScheduleInterval(string calldata username, bytes32 scheduleId, IntervalType newInterval)
        external
        auth(MANAGER_PERMISSION_ID)
    {
        Schedule storage schedule = schedules[username][scheduleId];
        if (schedule.token == address(0)) revert ScheduleIdNotFound();
        if (!schedule.active) revert ScheduleNotActive();

        schedule.interval = newInterval;
    }

    /// @inheritdoc IPayments
    function cancelSchedule(string calldata username, bytes32 scheduleId) external auth(MANAGER_PERMISSION_ID) {
        Schedule storage schedule = schedules[username][scheduleId];
        if (schedule.token == address(0)) revert ScheduleIdNotFound();
        if (!schedule.active) revert ScheduleNotActive();

        schedule.active = false;

        emit ScheduleCancelled(username, scheduleId);
    }

    /// @inheritdoc IPayments
    function executeSchedule(string calldata username, bytes32 scheduleId) external {
        Schedule storage schedule = schedules[username][scheduleId];
        if (schedule.token == address(0)) revert ScheduleIdNotFound();
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

            // Cap periods to prevent excessive gas costs (max 10 periods at once)
            if (periodsToPayFor > 10) periodsToPayFor = 10;
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

        emit ScheduleExecuted(username, scheduleId, schedule.token, totalAmount, periodsToPayFor);
    }

    /// @inheritdoc IPayments
    function getUserStreams(string calldata username)
        external
        view
        returns (bytes32[] memory streamIds, Stream[] memory streamData)
    {
        streamIds = userStreamIds[username];
        streamData = new Stream[](streamIds.length);

        for (uint256 i = 0; i < streamIds.length; i++) {
            streamData[i] = streams[username][streamIds[i]];
        }
    }

    /// @inheritdoc IPayments
    function getUserSchedules(string calldata username)
        external
        view
        returns (bytes32[] memory scheduleIds, Schedule[] memory scheduleData)
    {
        scheduleIds = userScheduleIds[username];
        scheduleData = new Schedule[](scheduleIds.length);

        for (uint256 i = 0; i < scheduleIds.length; i++) {
            scheduleData[i] = schedules[username][scheduleIds[i]];
        }
    }

    /// @inheritdoc IPayments
    function getUserActivePayments(string calldata username)
        external
        view
        returns (
            bytes32[] memory activeStreamIds,
            bytes32[] memory activeScheduleIds,
            uint256 totalActiveStreams,
            uint256 totalActiveSchedules
        )
    {
        bytes32[] memory allStreamIds = userStreamIds[username];
        bytes32[] memory allScheduleIds = userScheduleIds[username];

        // Count active items first
        uint256 activeStreamCount = 0;
        uint256 activeScheduleCount = 0;

        for (uint256 i = 0; i < allStreamIds.length; i++) {
            if (streams[username][allStreamIds[i]].state == StreamState.Active) {
                activeStreamCount++;
            }
        }

        for (uint256 i = 0; i < allScheduleIds.length; i++) {
            if (schedules[username][allScheduleIds[i]].active) {
                activeScheduleCount++;
            }
        }

        // Fill active arrays
        activeStreamIds = new bytes32[](activeStreamCount);
        activeScheduleIds = new bytes32[](activeScheduleCount);

        uint256 streamIndex = 0;
        uint256 scheduleIndex = 0;

        for (uint256 i = 0; i < allStreamIds.length; i++) {
            if (streams[username][allStreamIds[i]].state == StreamState.Active) {
                activeStreamIds[streamIndex++] = allStreamIds[i];
            }
        }

        for (uint256 i = 0; i < allScheduleIds.length; i++) {
            if (schedules[username][allScheduleIds[i]].active) {
                activeScheduleIds[scheduleIndex++] = allScheduleIds[i];
            }
        }

        totalActiveStreams = activeStreamCount;
        totalActiveSchedules = activeScheduleCount;
    }

    /// @inheritdoc IPayments
    function getUserPaymentSummary(string calldata username) external view returns (PaymentSummary memory) {
        bytes32[] memory streamIds = userStreamIds[username];
        bytes32[] memory scheduleIds = userScheduleIds[username];

        // Track unique tokens and calculate monthly amounts
        address[] memory tokens = new address[](streamIds.length + scheduleIds.length);
        uint256[] memory monthlyAmounts = new uint256[](streamIds.length + scheduleIds.length);
        uint256[] memory pendingAmounts = new uint256[](scheduleIds.length);
        uint256 uniqueTokenCount = 0;
        uint256 activeStreams = 0;
        uint256 activeSchedules = 0;

        // Process streams for monthly flow estimates
        for (uint256 i = 0; i < streamIds.length; i++) {
            Stream storage stream = streams[username][streamIds[i]];
            if (stream.state == StreamState.Active) {
                activeStreams++;

                // Convert flow rate to monthly estimate (30 days * 24 hours * 3600 seconds)
                uint256 monthlyFlow = uint256(stream.amountPerSec) * 2592000;

                // Add to existing token or create new entry
                bool tokenFound = false;
                for (uint256 j = 0; j < uniqueTokenCount; j++) {
                    if (tokens[j] == stream.token) {
                        monthlyAmounts[j] += monthlyFlow;
                        tokenFound = true;
                        break;
                    }
                }

                if (!tokenFound) {
                    tokens[uniqueTokenCount] = stream.token;
                    monthlyAmounts[uniqueTokenCount] = monthlyFlow;
                    uniqueTokenCount++;
                }
            }
        }

        // Process schedules for pending amounts
        for (uint256 i = 0; i < scheduleIds.length; i++) {
            Schedule storage schedule = schedules[username][scheduleIds[i]];
            if (schedule.active) {
                activeSchedules++;
                pendingAmounts[i] = schedule.amount;
            }
        }

        // Trim arrays to actual size
        address[] memory finalTokens = new address[](uniqueTokenCount);
        uint256[] memory finalMonthlyAmounts = new uint256[](uniqueTokenCount);

        for (uint256 i = 0; i < uniqueTokenCount; i++) {
            finalTokens[i] = tokens[i];
            finalMonthlyAmounts[i] = monthlyAmounts[i];
        }

        return PaymentSummary({
            totalActiveStreams: activeStreams,
            totalActiveSchedules: activeSchedules,
            uniqueTokens: finalTokens,
            monthlyStreamAmounts: finalMonthlyAmounts,
            pendingScheduleAmounts: pendingAmounts
        });
    }

    /// @inheritdoc IPayments
    function pauseAllUserStreams(string calldata username)
        external
        auth(MANAGER_PERMISSION_ID)
        returns (bytes32[] memory pausedStreamIds)
    {
        bytes32[] memory streamIds = userStreamIds[username];
        uint256 pausedCount = 0;

        // Count active streams first
        for (uint256 i = 0; i < streamIds.length; i++) {
            if (streams[username][streamIds[i]].state == StreamState.Active) {
                pausedCount++;
            }
        }

        pausedStreamIds = new bytes32[](pausedCount);
        uint256 pausedIndex = 0;

        // Pause active streams
        for (uint256 i = 0; i < streamIds.length; i++) {
            bytes32 streamId = streamIds[i];
            Stream storage stream = streams[username][streamId];

            if (stream.state == StreamState.Active) {
                address recipient = streamRecipients[username][streamId];
                address llamaPayContract = tokenToLlamaPay[stream.token];

                // Pause by setting flow rate to 0
                _modifyLlamaPayStream(
                    llamaPayContract, recipient, stream.amountPerSec, recipient, 0, username, streamId
                );

                stream.state = StreamState.Paused;
                pausedStreamIds[pausedIndex++] = streamId;

                emit StreamStateChanged(username, streamId, StreamState.Active, StreamState.Paused);
            }
        }

        return pausedStreamIds;
    }

    /// @inheritdoc IPayments
    function resumeAllUserStreams(string calldata username)
        external
        auth(MANAGER_PERMISSION_ID)
        returns (bytes32[] memory resumedStreamIds)
    {
        bytes32[] memory streamIds = userStreamIds[username];
        uint256 resumedCount = 0;

        // Count paused streams first
        for (uint256 i = 0; i < streamIds.length; i++) {
            if (streams[username][streamIds[i]].state == StreamState.Paused) {
                resumedCount++;
            }
        }

        resumedStreamIds = new bytes32[](resumedCount);
        uint256 resumedIndex = 0;

        // Resume paused streams
        for (uint256 i = 0; i < streamIds.length; i++) {
            bytes32 streamId = streamIds[i];
            Stream storage stream = streams[username][streamId];

            if (stream.state == StreamState.Paused) {
                address recipient = streamRecipients[username][streamId];
                address llamaPayContract = tokenToLlamaPay[stream.token];

                // Resume by restoring original flow rate
                _modifyLlamaPayStream(
                    llamaPayContract, recipient, 0, recipient, stream.amountPerSec, username, streamId
                );

                stream.state = StreamState.Active;
                resumedStreamIds[resumedIndex++] = streamId;

                emit StreamStateChanged(username, streamId, StreamState.Paused, StreamState.Active);
            }
        }

        return resumedStreamIds;
    }

    /// @inheritdoc IPayments
    function migrateStream(string calldata username, bytes32 streamId) external {
        // Only current username controller can migrate
        address currentController = registry.getController(username);
        if (_msgSender() != currentController) revert UnauthorizedMigration();

        Stream storage stream = streams[username][streamId];
        if (stream.token == address(0)) revert StreamIdNotFound();
        if (stream.state == StreamState.Cancelled) revert StreamStateMismatch();

        // Get current and stored recipient addresses
        address currentRecipient = registry.getRecipient(username);
        address storedRecipient = streamRecipients[username][streamId];

        // Check if migration is needed
        if (storedRecipient == currentRecipient) revert MigrationNotRequired();

        // Migrate stream to new recipient address
        address llamaPayContract = tokenToLlamaPay[stream.token];
        uint216 currentAmountPerSec = stream.state == StreamState.Active ? stream.amountPerSec : 0;

        _modifyLlamaPayStream(
            llamaPayContract,
            storedRecipient,
            currentAmountPerSec,
            currentRecipient,
            currentAmountPerSec,
            username,
            streamId
        );

        // Update stored recipient
        streamRecipients[username][streamId] = currentRecipient;

        emit StreamMigrated(username, streamId, storedRecipient, currentRecipient);
    }

    /// @inheritdoc IPayments
    function migrateAllStreams(string calldata username) external returns (bytes32[] memory migratedStreamIds) {
        // Only current username controller can migrate
        address currentController = registry.getController(username);
        if (_msgSender() != currentController) revert UnauthorizedMigration();

        bytes32[] memory streamIds = userStreamIds[username];
        address currentRecipient = registry.getRecipient(username);

        // Count streams that need migration
        uint256 migrationCount = 0;
        for (uint256 i = 0; i < streamIds.length; i++) {
            bytes32 streamId = streamIds[i];
            Stream storage stream = streams[username][streamId];
            address storedRecipient = streamRecipients[username][streamId];

            if (stream.state != StreamState.Cancelled && storedRecipient != currentRecipient) {
                migrationCount++;
            }
        }

        migratedStreamIds = new bytes32[](migrationCount);
        uint256 migratedIndex = 0;

        // Migrate streams that need it
        for (uint256 i = 0; i < streamIds.length; i++) {
            bytes32 streamId = streamIds[i];
            Stream storage stream = streams[username][streamId];
            address storedRecipient = streamRecipients[username][streamId];

            if (stream.state != StreamState.Cancelled && storedRecipient != currentRecipient) {
                address llamaPayContract = tokenToLlamaPay[stream.token];
                uint216 currentAmountPerSec = stream.state == StreamState.Active ? stream.amountPerSec : 0;

                _modifyLlamaPayStream(
                    llamaPayContract,
                    storedRecipient,
                    currentAmountPerSec,
                    currentRecipient,
                    currentAmountPerSec,
                    username,
                    streamId
                );

                streamRecipients[username][streamId] = currentRecipient;
                migratedStreamIds[migratedIndex++] = streamId;

                emit StreamMigrated(username, streamId, storedRecipient, currentRecipient);
            }
        }

        return migratedStreamIds;
    }

    /// @inheritdoc IPayments
    function migrateStreamsForToken(string calldata username, address token)
        external
        returns (bytes32[] memory migratedStreamIds)
    {
        // Only current username controller can migrate
        address currentController = registry.getController(username);
        if (_msgSender() != currentController) revert UnauthorizedMigration();

        bytes32[] memory streamIds = userStreamIds[username];
        address currentRecipient = registry.getRecipient(username);

        // Count streams for specific token that need migration
        uint256 migrationCount = 0;
        for (uint256 i = 0; i < streamIds.length; i++) {
            bytes32 streamId = streamIds[i];
            Stream storage stream = streams[username][streamId];
            address storedRecipient = streamRecipients[username][streamId];

            if (stream.token == token && stream.state != StreamState.Cancelled && storedRecipient != currentRecipient) {
                migrationCount++;
            }
        }

        migratedStreamIds = new bytes32[](migrationCount);
        uint256 migratedIndex = 0;

        // Migrate streams for the specified token
        for (uint256 i = 0; i < streamIds.length; i++) {
            bytes32 streamId = streamIds[i];
            Stream storage stream = streams[username][streamId];
            address storedRecipient = streamRecipients[username][streamId];

            if (stream.token == token && stream.state != StreamState.Cancelled && storedRecipient != currentRecipient) {
                address llamaPayContract = tokenToLlamaPay[stream.token];
                uint216 currentAmountPerSec = stream.state == StreamState.Active ? stream.amountPerSec : 0;

                _modifyLlamaPayStream(
                    llamaPayContract,
                    storedRecipient,
                    currentAmountPerSec,
                    currentRecipient,
                    currentAmountPerSec,
                    username,
                    streamId
                );

                streamRecipients[username][streamId] = currentRecipient;
                migratedStreamIds[migratedIndex++] = streamId;

                emit StreamMigrated(username, streamId, storedRecipient, currentRecipient);
            }
        }

        return migratedStreamIds;
    }

    /// @inheritdoc IPayments
    function migrateSelectedStreams(string calldata username, bytes32[] calldata streamIds)
        external
        returns (bytes32[] memory migratedStreamIds)
    {
        // Only current username controller can migrate
        address currentController = registry.getController(username);
        if (_msgSender() != currentController) revert UnauthorizedMigration();

        address currentRecipient = registry.getRecipient(username);
        migratedStreamIds = new bytes32[](streamIds.length);
        uint256 migratedIndex = 0;

        // Migrate specified streams
        for (uint256 i = 0; i < streamIds.length; i++) {
            bytes32 streamId = streamIds[i];
            Stream storage stream = streams[username][streamId];

            if (stream.token == address(0)) continue; // Skip non-existent streams
            if (stream.state == StreamState.Cancelled) continue; // Skip cancelled streams

            address storedRecipient = streamRecipients[username][streamId];
            if (storedRecipient == currentRecipient) continue; // Skip if no migration needed

            address llamaPayContract = tokenToLlamaPay[stream.token];
            uint216 currentAmountPerSec = stream.state == StreamState.Active ? stream.amountPerSec : 0;

            _modifyLlamaPayStream(
                llamaPayContract,
                storedRecipient,
                currentAmountPerSec,
                currentRecipient,
                currentAmountPerSec,
                username,
                streamId
            );

            streamRecipients[username][streamId] = currentRecipient;
            migratedStreamIds[migratedIndex++] = streamId;

            emit StreamMigrated(username, streamId, storedRecipient, currentRecipient);
        }

        // Trim array to actual migrated count
        bytes32[] memory finalMigratedIds = new bytes32[](migratedIndex);
        for (uint256 i = 0; i < migratedIndex; i++) {
            finalMigratedIds[i] = migratedStreamIds[i];
        }

        return finalMigratedIds;
    }

    /// @inheritdoc IPayments
    function getMigrationPreview(string calldata username) external view returns (MigrationPreview memory) {
        address currentRecipient = registry.getRecipient(username);
        bytes32[] memory streamIds = userStreamIds[username];
        bytes32[] memory scheduleIds = userScheduleIds[username];

        // Count streams and schedules needing migration
        uint256 streamsNeedingMigration = 0;
        uint256 schedulesNeedingMigration = 0;

        for (uint256 i = 0; i < streamIds.length; i++) {
            bytes32 streamId = streamIds[i];
            Stream storage stream = streams[username][streamId];
            address storedRecipient = streamRecipients[username][streamId];

            if (stream.state != StreamState.Cancelled && storedRecipient != currentRecipient) {
                streamsNeedingMigration++;
            }
        }

        // For schedules, migration isn't needed as they resolve recipient at execution time
        // But we include them for completeness
        for (uint256 i = 0; i < scheduleIds.length; i++) {
            if (schedules[username][scheduleIds[i]].active) {
                schedulesNeedingMigration++;
            }
        }

        // Build arrays of IDs needing migration
        bytes32[] memory streamsMigrationIds = new bytes32[](streamsNeedingMigration);
        bytes32[] memory schedulesMigrationIds = new bytes32[](schedulesNeedingMigration);

        uint256 streamIndex = 0;
        uint256 scheduleIndex = 0;

        for (uint256 i = 0; i < streamIds.length; i++) {
            bytes32 streamId = streamIds[i];
            Stream storage stream = streams[username][streamId];
            address storedRecipient = streamRecipients[username][streamId];

            if (stream.state != StreamState.Cancelled && storedRecipient != currentRecipient) {
                streamsMigrationIds[streamIndex++] = streamId;
            }
        }

        for (uint256 i = 0; i < scheduleIds.length; i++) {
            if (schedules[username][scheduleIds[i]].active) {
                schedulesMigrationIds[scheduleIndex++] = scheduleIds[i];
            }
        }

        // Estimate gas cost (rough estimate: 50k per stream migration)
        uint256 estimatedGasCost = streamsNeedingMigration * 50000;
        bool migrationRequired = streamsNeedingMigration > 0;

        return MigrationPreview({
            currentRecipient: currentRecipient,
            streamsNeedingMigration: streamsMigrationIds,
            schedulesNeedingMigration: schedulesMigrationIds,
            estimatedGasCost: estimatedGasCost,
            migrationRequired: migrationRequired
        });
    }

    /// @inheritdoc IPayments
    function getStream(string calldata username, bytes32 streamId) external view returns (Stream memory) {
        Stream memory stream = streams[username][streamId];
        if (stream.token == address(0)) revert StreamIdNotFound();
        return stream;
    }

    /// @inheritdoc IPayments
    function getSchedule(string calldata username, bytes32 scheduleId) external view returns (Schedule memory) {
        Schedule memory schedule = schedules[username][scheduleId];
        if (schedule.token == address(0)) revert ScheduleIdNotFound();
        return schedule;
    }

    /// @notice Generate unique stream ID using deterministic hashing
    /// @param username Target username
    /// @param token Token address
    /// @param amountPerSec Flow rate
    /// @param timestamp Current timestamp
    /// @param nonce User's stream count for uniqueness
    /// @return streamId The generated stream ID
    function _generateStreamId(
        string calldata username,
        address token,
        uint216 amountPerSec,
        uint256 timestamp,
        uint256 nonce
    ) internal pure returns (bytes32 streamId) {
        return keccak256(abi.encodePacked(username, token, amountPerSec, timestamp, nonce));
    }

    /// @notice Generate unique schedule ID using deterministic hashing
    /// @param username Target username
    /// @param token Token address
    /// @param amount Payment amount
    /// @param interval Payment interval
    /// @param timestamp Current timestamp
    /// @param nonce User's schedule count for uniqueness
    /// @return scheduleId The generated schedule ID
    function _generateScheduleId(
        string calldata username,
        address token,
        uint256 amount,
        IntervalType interval,
        uint256 timestamp,
        uint256 nonce
    ) internal pure returns (bytes32 scheduleId) {
        return keccak256(abi.encodePacked(username, token, amount, interval, timestamp, nonce));
    }

    /// @notice Resolve username to recipient address via registry
    /// @param username The username to resolve
    /// @return recipient The resolved recipient address
    function _resolveUsername(string calldata username) internal view returns (address recipient) {
        recipient = registry.getRecipient(username);
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

    /// @notice Calculate recommended funding amount for indefinite streams
    /// @param amountPerSec Flow rate in LlamaPay precision
    /// @param token Token contract address
    /// @return recommendedAmount Recommended funding amount
    function _calculateRecommendedFunding(uint216 amountPerSec, address token)
        internal
        view
        returns (uint256 recommendedAmount)
    {
        // Convert flow rate back to native token precision for funding calculation
        uint8 tokenDecimals = IERC20WithDecimals(token).decimals();
        uint256 decimalsMultiplier = 10 ** (20 - tokenDecimals);

        // Calculate for default funding period (6 months)
        uint256 totalFlow = uint256(amountPerSec) * DEFAULT_FUNDING_PERIOD;
        recommendedAmount = totalFlow / decimalsMultiplier;

        // Ensure minimum funding amount
        if (recommendedAmount == 0) recommendedAmount = 1;
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

    /// @notice Create a LlamaPay stream with reason including stream ID
    /// @param llamaPayContract LlamaPay contract address
    /// @param recipient Stream recipient
    /// @param amountPerSec Amount per second
    /// @param username Username for the reason
    /// @param streamId Stream ID for tracking
    function _createLlamaPayStream(
        address llamaPayContract,
        address recipient,
        uint216 amountPerSec,
        string calldata username,
        bytes32 streamId
    ) internal {
        // Create action to create stream with reason including stream ID
        Action[] memory actions = new Action[](1);
        actions[0].to = llamaPayContract;
        actions[0].value = 0;

        // Include stream ID in reason for better tracking
        string memory reason =
            string(abi.encodePacked("PayNest V2 stream for ", username, " (", _bytes32ToString(streamId), ")"));

        actions[0].data = abi.encodeCall(ILlamaPay.createStreamWithReason, (recipient, amountPerSec, reason));

        // Execute via DAO
        DAO(payable(address(dao()))).execute(
            keccak256(abi.encodePacked("create-stream-", username, streamId)), actions, 0
        );
    }

    /// @notice Modify a LlamaPay stream using native modifyStream function
    /// @param llamaPayContract LlamaPay contract address
    /// @param oldRecipient Current stream recipient
    /// @param oldAmountPerSec Current amount per second
    /// @param newRecipient New stream recipient
    /// @param newAmountPerSec New amount per second
    /// @param username Username for tracking
    /// @param streamId Stream ID for tracking
    function _modifyLlamaPayStream(
        address llamaPayContract,
        address oldRecipient,
        uint216 oldAmountPerSec,
        address newRecipient,
        uint216 newAmountPerSec,
        string calldata username,
        bytes32 streamId
    ) internal {
        // Create action to modify stream
        Action[] memory actions = new Action[](1);
        actions[0].to = llamaPayContract;
        actions[0].value = 0;
        actions[0].data =
            abi.encodeCall(ILlamaPay.modifyStream, (oldRecipient, oldAmountPerSec, newRecipient, newAmountPerSec));

        // Execute via DAO
        DAO(payable(address(dao()))).execute(
            keccak256(abi.encodePacked("modify-stream-", username, streamId)), actions, 0
        );
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
        if (interval == IntervalType.Daily) return 1 days;
        if (interval == IntervalType.Weekly) return 7 days;
        if (interval == IntervalType.BiWeekly) return 14 days;
        if (interval == IntervalType.Monthly) return 30 days;
        if (interval == IntervalType.Quarterly) return 90 days;
        if (interval == IntervalType.SemiAnnual) return 180 days;
        if (interval == IntervalType.Yearly) return 365 days;
        revert InvalidAmount(); // Should never reach here with valid enum
    }

    /// @notice Convert bytes32 to string for logging purposes
    /// @param _bytes32 The bytes32 value to convert
    /// @return string The string representation
    function _bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
