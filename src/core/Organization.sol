// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


import "../interfaces/IRegistry.sol";
import "../interfaces/IPaynest.sol";
import "../interfaces/IOrg.sol";
import "../utils/Errors.sol";
import "../utils/Constants.sol";
import "../utils/Owner.sol";
import "../utils/ReentrancyGuard.sol";
import "../ext_lib/SafeTransferLib.sol";
import "../ext_lib/ERC20.sol";

contract Organization is IOrg, Errors, Owner, ReentrancyGuard {
    IRegistry immutable private Registry = IRegistry(Constants.REGISTRY);
    IPaynest immutable private Paynest = IPaynest(msg.sender);

    uint40 private subscribedUntil = uint40(block.timestamp);
    string private name;

    mapping(string => Schedule) private schedulePayment;
    mapping(string => Stream) private streamPayment;

    constructor(address _owner, string memory _name) payable Owner(_owner) {
        name = _name;
        emit OrgNameChange(_name);
    }
    
    receive() external payable {
        emit ETHReceived(name, msg.value);
    }

    function checkSubscription(uint40 validUntil) private {
        if(validUntil > subscribedUntil){
            subscribe(validUntil);
        }
    }

    function updateOrgName(string calldata newName) external override {
        onlyOwner();

        name = newName;
        emit OrgNameChange(newName);
    }


    function createSchedule(string calldata username, uint256 amount, address token, uint40 oneTimePayoutDate) external payable override {
        onlyOwner();

        Registry.getUserAddress(username);

        if (Paynest.isSupportedToken(token) == false) revert TokenNotSupported();
        if (amount == 0) revert InvalidAmount();

        Schedule memory _schedule = schedulePayment[username];
        if (_schedule.active) revert ActivePayment(username);

        uint40 _now = uint40(block.timestamp);
        bool isOneTime = oneTimePayoutDate > _now;
        uint40 nextPayout = isOneTime ? oneTimePayoutDate : (_now + uint40(30 days));

        checkSubscription(nextPayout);

        schedulePayment[username] = Schedule(token, nextPayout, isOneTime, true, amount);
        emit PaymentScheduleActive(username, token, nextPayout, amount);
    }

    function createStream(string calldata username, uint256 amount, address token, uint40 endStream) external payable override {
        onlyOwner();

        Registry.getUserAddress(username);

        if (Paynest.isSupportedToken(token) == false) revert TokenNotSupported();
        if (amount == 0) revert InvalidAmount();
        if (endStream <= block.timestamp) revert InvalidStreamEnd();

        Stream memory _stream = streamPayment[username];
        if (_stream.active) revert ActivePayment(username);

        uint40 _now = uint40(block.timestamp);
        checkSubscription(endStream);

        streamPayment[username] = Stream(amount, token, _now, endStream, true);
        emit PaymentStreamActive(username, token, _now, amount);
    }

    function _streamPayout(string calldata username, bool request) private {
        Stream memory _stream = streamPayment[username];
        if (!_stream.active) revert InActivePayment(username);

        uint40 currentTime = uint40(block.timestamp);
        if (request && currentTime < (_stream.lastPayout + 1 days)) revert NoPayoutDue();

        address recipient = Registry.getUserAddress(username);
        uint256 payoutAmount;

        if (currentTime >= _stream.endStream) {
            uint40 timeUntilEnd = _stream.endStream - _stream.lastPayout;
            payoutAmount = timeUntilEnd * _stream.amount;
            streamPayment[username].active = false;
        } else {
            uint40 elapsedTime = currentTime - _stream.lastPayout;
            payoutAmount = elapsedTime * _stream.amount;
        }

        streamPayment[username].lastPayout = currentTime;
        
        if(_stream.token == Constants.ETH) SafeTransferLib.safeTransferETH(recipient, payoutAmount);
        else SafeTransferLib.safeTransfer(ERC20(_stream.token), recipient, payoutAmount);
        emit Payout(username, _stream.token, payoutAmount);       
    }

    function requestStreamPayout(string calldata username) external payable override nonReentrant {
        _streamPayout(username, true);        
    }

    function requestSchedulePayout(string calldata username) external payable override nonReentrant {
        Schedule memory _schedule = schedulePayment[username];
        if (!_schedule.active) revert InActivePayment(username);

        uint40 currentTime = uint40(block.timestamp);
        if (currentTime < _schedule.nextPayout) revert NoPayoutDue();

        address recipient = Registry.getUserAddress(username);

        uint256 payoutAmount = _schedule.amount;

        if (_schedule.isOneTime) {
            schedulePayment[username].active = false;
        } else {
            uint40 interval = uint40(30 days);
            uint40 nextPayout = _schedule.nextPayout + interval;

            // Ensure the next payout isn't set in the past and account for missed payouts
            if (nextPayout < currentTime) {
                uint40 missedIntervals = (currentTime - _schedule.nextPayout) / interval;
                payoutAmount += _schedule.amount * missedIntervals;
                nextPayout = _schedule.nextPayout + (missedIntervals + 1) * interval;
            }

            schedulePayment[username].nextPayout = nextPayout;
        }
        
        if(_schedule.token == Constants.ETH) SafeTransferLib.safeTransferETH(recipient, payoutAmount);
        else SafeTransferLib.safeTransfer(ERC20(_schedule.token), recipient, payoutAmount);
        emit Payout(username, _schedule.token, payoutAmount);
    }

    function cancelStream(string calldata username) external override {
        onlyOwner();

        _streamPayout(username, false);
        
        streamPayment[username].active = false;
        emit PaymentStreamCancelled(username);
    }

    function cancelSchedule(string calldata username) external override {
        onlyOwner(); 

        Schedule memory _schedule = schedulePayment[username];
        if (!_schedule.active) revert InActivePayment(username);

        uint40 currentTime = uint40(block.timestamp);
        uint40 elapsedTime = currentTime - (_schedule.nextPayout - uint40(30 days));

        // Calculate the prorated payment amount
        uint256 proratedAmount = (elapsedTime * _schedule.amount) / uint40(30 days);

        address recipient = Registry.getUserAddress(username);
        if (proratedAmount > 0) {
            if(_schedule.token == Constants.ETH) SafeTransferLib.safeTransferETH(recipient, proratedAmount);
            else SafeTransferLib.safeTransfer(ERC20(_schedule.token), recipient, proratedAmount);
            emit Payout(username, _schedule.token, proratedAmount);
        }

        schedulePayment[username].active = false;
        emit PaymentScheduleCancelled(username);
    }

    function subscribe(uint40 validUntil) public {
        onlyOwner();

        uint fixedFee = Paynest.getFixedFee();
        if(fixedFee == 0) return;
        uint40 extendedPeriod = validUntil - subscribedUntil;
        uint totalFee = fixedFee * extendedPeriod;
        SafeTransferLib.safeTransferETH(address(Paynest), totalFee);
        subscribedUntil = validUntil;
    }
    
    function getSubscriptionDetails() external view returns (uint256){
        return subscribedUntil;
    }

    function emergencyWithdraw(address tokenAddr) external  {
        bool canWithdraw = Paynest.canEmergencyWithdraw(msg.sender, tokenAddr);
        if(!canWithdraw) revert NotAuthorized();

        if(tokenAddr == Constants.ETH){
            uint amount = address(this).balance;
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            ERC20 token = ERC20(tokenAddr);
            uint amount = token.balanceOf(address(this));
            SafeTransferLib.safeTransfer(token, msg.sender, amount);
        }
    }
}