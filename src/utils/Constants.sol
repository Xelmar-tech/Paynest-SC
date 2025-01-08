// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Constants Library
 * @dev Provides reusable constant values for the Paynest system.
 */
library Constants {
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant MAX_ORG_COUNT = 3;
    uint256 internal constant MIN_SUBSCRIPTION_FEE = 0.01 ether;
}
