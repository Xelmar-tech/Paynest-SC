// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Errors
 * @dev Custom error definitions for the Paynest system.
 */
abstract contract Errors {
    // Authorization errors
    error NotAuthorized();

    // Token errors
    error TokenNotSupported();
    error TokenAlreadySupported();
    error InsufficientBalance();

    // Subscription errors
    error InsufficientFee();
    error MaxOrganizationsReached();

    // Directory errors
    error UserNotFound(string username);
    error IncompatibleUserAddress();

    // Payment Errors
    error ActivePayment(string username);
    error InActivePayment(string username);
    error InvalidAmount();
    error InvalidStreamEnd();
    error NoPayoutDue();
}
