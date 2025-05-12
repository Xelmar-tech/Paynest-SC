// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IPayments, IPaynest} from "./interfaces/IPayments.sol";
import {Owner} from "./util/Owner.sol";
import {Errors} from "./util/Errors.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IRegistry.sol";
import "./util/ReentrancyGuard.sol";
import "./lib/SafeTransferLib.sol";

/**
 * @title Org
 * @notice A contract that manages payment schedules and streams.
 */
contract Org is IPayments, Errors, Owner, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IRegistry private immutable Registry;
    bytes32 public immutable orgName;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint40 private constant INTERVAL = uint40(30 days);
    uint40 private constant EDIT_TIMEOUT = uint40(3 days);

    mapping(string => Schedule) private schedulePayment;
    mapping(string => Stream) private streamPayment;

    /// NOTE: This contract must be deployed via Paynest. msg.sender is expected to implement getRegistry().
    constructor(address _owner, string memory _name) payable Owner(_owner) {
        Registry = IRegistry(IPaynest(msg.sender).getRegistry());
        require(bytes(_name).length <= 32, "Org name too long");
        orgName = bytes32(bytes(_name));
    }

    receive() external payable {}

    function getIntervalDuration(
        IntervalType interval
    ) internal pure returns (uint40) {
        if (interval == IntervalType.None) return 0;
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
    ) external override {
        onlyOwner();

        Registry.getUserAddress(username);
        if (amount == 0) revert InvalidAmount();
        if (schedulePayment[username].active) revert ActivePayment(username);

        uint40 _now = uint40(block.timestamp);
        if (firstPaymentDate < _now + 1) revert InvalidFirstPaymentDate();
        if (!isOneTime && interval == IntervalType.None)
            revert InvalidInterval();

        schedulePayment[username] = Schedule(
            token,
            firstPaymentDate,
            interval,
            isOneTime,
            true,
            amount
        );
        emit ScheduleActive(username, token, firstPaymentDate, amount);
    }

    function createStream(
        string calldata username,
        uint256 amount,
        address token,
        uint40 endStream
    ) external override {
        onlyOwner();
        Registry.getUserAddress(username);
        if (amount == 0) revert InvalidAmount();

        if (streamPayment[username].active) revert ActivePayment(username);
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
            // NOTE:
            // This payout logic assumes an "eager payout" model.
            // That means:
            // - Payouts are allowed once the current time has passed the `nextPayout` timestamp.
            // - We calculate how many full intervals have passed since `nextPayout`.
            // - We then pay for all of them, including the current interval if it has already started.
            // - The `nextPayout` is advanced by (missedIntervals + 1) * interval duration to point to the *next unpaid interval*.
            //
            // Example:
            //   - Interval: 7 days
            //   - nextPayout = April 1
            //   - currentTime = April 18
            //   → Missed intervals = 3 (April 1, April 8 & April 15 started)
            //   → We pay for 3 intervals (April 1, 8, 15)
            //   → nextPayout becomes April 22 (missedIntervals + 1)

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

        if (_schedule.token == ETH)
            SafeTransferLib.safeTransferETH(recipient, payoutAmount);
        else
            SafeTransferLib.safeTransfer(
                ERC20(_schedule.token),
                recipient,
                payoutAmount
            );

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

        if (_stream.token == ETH)
            SafeTransferLib.safeTransferETH(recipient, payoutAmount);
        else
            SafeTransferLib.safeTransfer(
                ERC20(_stream.token),
                recipient,
                payoutAmount
            );

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
            if (_schedule.token == ETH)
                SafeTransferLib.safeTransferETH(recipient, proratedAmount);
            else
                SafeTransferLib.safeTransfer(
                    ERC20(_schedule.token),
                    recipient,
                    proratedAmount
                );
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
    ) external override {
        onlyOwner();
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
    ) external override {
        onlyOwner();
        if (amount == 0) revert InvalidAmount();

        Stream memory _stream = streamPayment[username];
        if (!_stream.active) revert InActivePayment(username);

        _streamPayout(username);

        streamPayment[username].amount = amount;
        emit StreamUpdated(username, amount);
    }

    function cancelSchedule(
        string calldata username,
        bool payIncomplete
    ) external override {
        onlyOwner();
        if (payIncomplete) _incompleteSchedulePayout(username);

        schedulePayment[username].active = false;
        emit PaymentScheduleCancelled(username);
    }

    function cancelStream(string calldata username) external override {
        onlyOwner();
        _streamPayout(username);

        streamPayment[username].active = false;
        emit PaymentStreamCancelled(username);
    }
}
