// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {IPayments} from "./interfaces/IPayments.sol";
import {Errors} from "./util/Errors.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IRegistry.sol";
import "./util/ReentrancyGuard.sol";

/**
 * @title Payments Plugin
 * @notice A plugin that manages payment schedules and streams, executing them through the DAO.
 */
contract PaymentsPlugin is
    PluginUUPSUpgradeable,
    IPayments,
    Errors,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    IRegistry private immutable Registry =
        IRegistry(0xf75150d730CE97C1551e97df39c0A049024e4C25); // Need to manually set this

    bytes32 public constant CREATE_PAYMENT_PERMISSION_ID =
        keccak256("CREATE_PAYMENT_PERMISSION");

    bytes32 public constant EDIT_PAYMENT_PERMISSION_ID =
        keccak256("EDIT_PAYMENT_PERMISSION");

    bytes32 public constant EXECUTE_PAYMENT_PERMISSION_ID =
        keccak256("EXECUTE_PAYMENT_PERMISSION");

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint40 private constant INTERVAL = uint40(30 days);
    uint40 private constant EDIT_TIMEOUT = uint40(3 days);

    mapping(string => Schedule) private schedulePayment;
    mapping(string => Stream) private streamPayment;

    /// @notice Initializes the plugin.
    /// @param _dao The DAO associated with this plugin.
    function initialize(IDAO _dao) external initializer {
        __PluginUUPSUpgradeable_init(_dao);
    }

    function getIntervalDuration(
        IntervalType interval
    ) internal pure returns (uint40) {
        if (interval == IntervalType.Weekly) return 7 days;
        if (interval == IntervalType.Monthly) return 30 days;
        if (interval == IntervalType.Quarterly) return 90 days;
        if (interval == IntervalType.Yearly) return 365 days;
        revert InvalidInterval();
    }

    function createSchedule(
        string calldata username,
        uint256 amount,
        address token,
        IntervalType interval,
        bool isOneTime,
        uint40 firstPaymentDate
    ) external override auth(CREATE_PAYMENT_PERMISSION_ID) {
        Registry.getUserAddress(username);
        if (amount == 0) revert InvalidAmount();

        Schedule memory _schedule = schedulePayment[username];
        if (_schedule.active) revert ActivePayment(username);

        uint40 _now = uint40(block.timestamp);
        if (isOneTime && firstPaymentDate < _now)
            revert InvalidFirstPaymentDate();

        uint40 payoutInterval = getIntervalDuration(interval);
        uint40 nextPayout = isOneTime
            ? firstPaymentDate
            : (_now + payoutInterval);

        schedulePayment[username] = Schedule(
            token,
            nextPayout,
            interval,
            isOneTime,
            true,
            amount
        );
        emit ScheduleActive(username, token, nextPayout, amount);
    }

    function createStream(
        string calldata username,
        uint256 amount,
        address token,
        uint40 endStream
    ) external override auth(CREATE_PAYMENT_PERMISSION_ID) {
        Registry.getUserAddress(username);
        if (amount == 0) revert InvalidAmount();

        Stream memory _stream = streamPayment[username];
        if (_stream.active) revert ActivePayment(username);

        uint40 _now = uint40(block.timestamp);
        if (endStream <= _now) revert InvalidEndDate();

        streamPayment[username] = Stream({
            token: token,
            endDate: endStream,
            active: true,
            amount: amount,
            lastPayout: _now
        });
        emit StreamActive(username, token, endStream, amount);
    }

    function requestSchedulePayout(
        string calldata username
    ) external payable override nonReentrant {
        Schedule memory _schedule = schedulePayment[username];
        if (!_schedule.active) revert InActivePayment(username);

        uint40 currentTime = uint40(block.timestamp);
        if (currentTime < _schedule.nextPayout) revert NoPayoutDue();

        address recipient = Registry.getUserAddress(username);
        uint256 payoutAmount = _schedule.amount;

        if (_schedule.isOneTime) {
            schedulePayment[username].active = false;
        } else {
            uint40 payoutInterval = getIntervalDuration(_schedule.interval);
            uint40 nextPayout = _schedule.nextPayout + payoutInterval;

            // Ensure the next payout isn't set in the past and account for missed payouts
            if (nextPayout < currentTime) {
                uint40 missedIntervals = (currentTime - _schedule.nextPayout) /
                    payoutInterval;
                payoutAmount += _schedule.amount * missedIntervals;
                nextPayout =
                    _schedule.nextPayout +
                    (missedIntervals + 1) *
                    payoutInterval;
            }

            schedulePayment[username].nextPayout = nextPayout;
        }

        // Create action to be executed by the DAO
        IDAO.Action[] memory actions = new IDAO.Action[](1);

        if (_schedule.token == ETH) {
            actions[0] = IDAO.Action({
                to: recipient,
                value: payoutAmount,
                data: ""
            });
        } else {
            actions[0] = IDAO.Action({
                to: _schedule.token,
                value: 0,
                data: abi.encodeCall(IERC20.transfer, (recipient, payoutAmount))
            });
        }

        // Execute the payment through the DAO
        dao().execute({
            _callId: bytes32(0),
            _actions: actions,
            _allowFailureMap: 0
        });

        emit Payout(username, _schedule.token, payoutAmount);
    }

    function _streamPayout(
        string calldata username
    ) private returns (uint256 payoutAmount) {
        Stream memory _stream = streamPayment[username];
        if (!_stream.active) revert InActivePayment(username);

        uint40 currentTime = uint40(block.timestamp);
        address recipient = Registry.getUserAddress(username);

        if (currentTime >= _stream.endDate) {
            uint40 timeUntilEnd = _stream.endDate - _stream.lastPayout;
            payoutAmount = timeUntilEnd * _stream.amount;
            streamPayment[username].active = false;
        } else {
            uint40 elapsedTime = currentTime - _stream.lastPayout;
            payoutAmount = elapsedTime * _stream.amount;
        }

        streamPayment[username].lastPayout = currentTime;

        IDAO.Action[] memory actions = new IDAO.Action[](1);

        if (_stream.token == ETH) {
            actions[0] = IDAO.Action({
                to: recipient,
                value: payoutAmount,
                data: ""
            });
        } else {
            actions[0] = IDAO.Action({
                to: _stream.token,
                value: 0,
                data: abi.encodeCall(IERC20.transfer, (recipient, payoutAmount))
            });
        }

        // Execute the payment through the DAO
        dao().execute({
            _callId: bytes32(0),
            _actions: actions,
            _allowFailureMap: 0
        });
        emit Payout(username, _stream.token, payoutAmount);
    }

    function _incompleteSchedulePayout(string calldata username) private {
        Schedule memory _schedule = schedulePayment[username];
        if (!_schedule.active) revert InActivePayment(username);

        uint40 currentTime = uint40(block.timestamp);
        uint40 payoutInterval = getIntervalDuration(_schedule.interval);
        uint40 elapsedTime = currentTime -
            (_schedule.nextPayout - payoutInterval);

        // Calculate the prorated payment amount
        uint256 proratedAmount = (elapsedTime * _schedule.amount) /
            payoutInterval;

        address recipient = Registry.getUserAddress(username);
        if (proratedAmount > 0) {
            IDAO.Action[] memory actions = new IDAO.Action[](1);

            if (_schedule.token == ETH) {
                actions[0] = IDAO.Action({
                    to: recipient,
                    value: proratedAmount,
                    data: ""
                });
            } else {
                actions[0] = IDAO.Action({
                    to: _schedule.token,
                    value: 0,
                    data: abi.encodeCall(
                        IERC20.transfer,
                        (recipient, proratedAmount)
                    )
                });
            }

            // Execute the payment through the DAO
            dao().execute({
                _callId: bytes32(0),
                _actions: actions,
                _allowFailureMap: 0
            });
            emit Payout(username, _schedule.token, proratedAmount);
        }
    }

    function requestStreamPayout(
        string calldata username
    ) external payable override nonReentrant returns (uint256 payoutAmount) {
        payoutAmount = _streamPayout(username);
    }

    function getStream(
        string calldata username
    ) external view override returns (Stream memory) {
        return streamPayment[username];
    }

    function getSchedule(
        string calldata username
    ) external view override returns (Schedule memory) {
        return schedulePayment[username];
    }

    function editSchedule(
        string calldata username,
        uint amount
    ) external override auth(CREATE_PAYMENT_PERMISSION_ID) {
        if (amount == 0) revert InvalidAmount();

        Schedule memory _schedule = schedulePayment[username];
        if (!_schedule.active) revert InActivePayment(username);

        uint40 currentTimestamp = uint40(block.timestamp);
        if ((_schedule.nextPayout - currentTimestamp) < EDIT_TIMEOUT)
            revert NoEditAccess();

        schedulePayment[username].amount = amount;
        emit ScheduleUpdated(username, amount);
    }

    function editStream(
        string calldata username,
        uint amount
    ) external override auth(CREATE_PAYMENT_PERMISSION_ID) {
        if (amount == 0) revert InvalidAmount();

        Stream memory _stream = streamPayment[username];
        if (!_stream.active) revert InActivePayment(username);

        streamPayment[username].amount = amount;
        emit StreamUpdated(username, amount);
    }

    function cancelSchedule(
        string calldata username,
        bool payIncomplete
    ) external override auth(CREATE_PAYMENT_PERMISSION_ID) {
        if (payIncomplete) _incompleteSchedulePayout(username);

        schedulePayment[username].active = false;
        emit PaymentScheduleCancelled(username);
    }

    function cancelStream(
        string calldata username
    ) external override auth(CREATE_PAYMENT_PERMISSION_ID) {
        _streamPayout(username);

        streamPayment[username].active = false;
        emit PaymentStreamCancelled(username);
    }
}
