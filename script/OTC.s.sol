// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {OTC} from "../src/OTC.sol";
import {IOTC} from "../src/interfaces/IOTC.sol";

/**
 * @title OTC Deployment Script
 * @notice Script for deploying OTC contracts
 * @dev Modify the deployment parameters in the run() function before deploying
 */
contract OTCScript is Script {
    // Deployment parameters - MODIFY THESE BEFORE DEPLOYMENT
    address constant INPUT_TOKEN = address(0); // address(0) for ETH, or ERC20 token address
    address constant OUTPUT_TOKEN = address(0); // Replace with actual output token address
    address constant CLIENT_ADDRESS = address(0); // Replace with actual client address

    uint256 constant BUYBACK_PRICE = 1e18; // 1:1 ratio (adjust as needed)
    uint256 constant MIN_OUTPUT_AMOUNT = 1000 * 1e18; // Minimum 1000 tokens
    uint256 constant MIN_INPUT_AMOUNT = 1 ether; // Minimum 1 ETH or 1 token

    bool constant IS_SUPPLY = true; // true for supply-side, false for demand-side

    function run() public {
        // Get deployer (admin) address
        address admin = msg.sender;

        // Create supply stages array
        IOTC.Supply[] memory supplies = new IOTC.Supply[](3);

        // Configure supply stages (modify as needed)
        supplies[0] = IOTC.Supply({
            input: 0.5 ether, // 0.5 ETH input
            output: 500 * 1e18 // 500 tokens output
        });

        supplies[1] = IOTC.Supply({
            input: 0.3 ether, // 0.3 ETH input
            output: 300 * 1e18 // 300 tokens output
        });

        supplies[2] = IOTC.Supply({
            input: 0.2 ether, // 0.2 ETH input
            output: 200 * 1e18 // 200 tokens output
        });

        vm.startBroadcast();

        // Deploy OTC contract
        OTC otc = new OTC(
            INPUT_TOKEN,
            OUTPUT_TOKEN,
            admin,
            CLIENT_ADDRESS,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            IS_SUPPLY
        );

        vm.stopBroadcast();

        // Log deployment info
        console2.log("OTC Contract deployed at:", address(otc));
        console2.log("Admin address:", admin);
        console2.log("Client address:", CLIENT_ADDRESS);
        console2.log("Input token:", INPUT_TOKEN == address(0) ? "ETH" : "ERC20");
        console2.log("Output token:", OUTPUT_TOKEN);
        console2.log("Supply count:", otc.supplyCount());
        console2.log("Current state:", otc.currentState());
    }

    /**
     * @notice Alternative deployment function for demand-side contracts (no supplies)
     * @dev Use this when IS_SUPPLY = false
     */
    function deployDemandSide() public {
        address admin = msg.sender;

        // Empty supplies array for demand-side
        IOTC.Supply[] memory supplies = new IOTC.Supply[](0);

        vm.startBroadcast();

        OTC otc = new OTC(
            INPUT_TOKEN,
            OUTPUT_TOKEN,
            admin,
            CLIENT_ADDRESS,
            supplies,
            BUYBACK_PRICE,
            MIN_OUTPUT_AMOUNT,
            MIN_INPUT_AMOUNT,
            false // IS_SUPPLY = false for demand-side
        );

        vm.stopBroadcast();

        console2.log("Demand-side OTC Contract deployed at:", address(otc));
        console2.log("Admin address:", admin);
        console2.log("Client address:", CLIENT_ADDRESS);
    }
}

