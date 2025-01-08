// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Errors
 * @dev Custom error definitions for the Paynest system.
 */
abstract contract Errors {
    // Authorization errors
    error Unauthorized();
    error OnlyOwner();

    // Token errors
    error TokenNotSupported();
    error TokenAlreadySupported();

    // Subscription errors
    error InsufficientFee();
    error MaxOrganizationsReached();
}
