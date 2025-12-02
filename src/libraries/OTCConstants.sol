// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

/**
 * @title OTCConstants
 * @notice Constants used in the OTC contract
 */
library OTCConstants {
    uint64 public constant PROPOSE_FARM_ACCOUNT_LOCK_PERIOD = 10 days;
    uint64 public constant SUPPLY_LOCK_PERIOD = 10 days;
    uint64 public constant TOTAL_LOCK_PERIOD = 120 days; // ~4 months
    uint64 public constant INITIAL_LOCK_PERIOD = 120 days;

    // Price nominator (for fixed point arithmetic)
    uint256 public constant NOMINATOR = 1e18;

    // States
    uint8 public constant STATE_FUNDING = 0;
    uint8 public constant STATE_SUPPLY_IN_PROGRESS = 1;
    uint8 public constant STATE_SUPPLY_PROVIDED = 2;
    uint8 public constant STATE_WAITING_FOR_CLIENT_ANSWER = 3;
    uint8 public constant STATE_CLIENT_ACCEPTED = 4;
    uint8 public constant STATE_CLIENT_REJECTED = 5;
    uint8 public constant STATE_FINAL = 6;
}

