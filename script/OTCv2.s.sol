// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {OTCv2} from "../src/OTCv2.sol";
import {IOTCv2} from "../src/interfaces/IOTCv2.sol";

/**
 * @title OTCv2 Deployment Script
 * @notice Script for deploying OTCv2 contracts
 * @dev Modify the deployment parameters in the run() function before deploying
 */
contract OTCv2Script is Script {
    // Deployment parameters - MODIFY THESE BEFORE DEPLOYMENT
    address constant INPUT_TOKEN = address(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d); // address(0) for ETH, or ERC20 token address
    address constant OUTPUT_TOKEN = address(0x55d398326f99059fF775485246999027B3197955); // Replace with actual output token address
    address constant CLIENT_ADDRESS = address(0xf341e3C328c22e25EF08a9a99E70EF8bDd47F7e8); // Replace with actual client address

    uint256 constant BUYBACK_PRICE = 1e18; // 1:1 ratio (adjust as needed)
    uint256 constant MIN_OUTPUT_AMOUNT = 1000 * 1e18; // 1000 USDT
    uint256 constant MIN_INPUT_AMOUNT = 0; // 1 USDc

    bool constant IS_SUPPLY = false; // true for supply-side, false for demand-side

    function run() public {
        // Get deployer (admin) address
        address admin = msg.sender;

        // Create supply stages array
        IOTCv2.Supply[] memory supplies = new IOTCv2.Supply[](0);

        // // Configure supply stages (modify as needed)
        // supplies[0] = IOTC.Supply({
        //     input: 0.5 ether, // 0.5 ETH input
        //     output: 500 * 1e18 // 500 tokens output
        // });

        // supplies[1] = IOTC.Supply({
        //     input: 0.3 ether, // 0.3 ETH input
        //     output: 300 * 1e18 // 300 tokens output
        // });

        // supplies[2] = IOTC.Supply({
        //     input: 0.2 ether, // 0.2 ETH input
        //     output: 200 * 1e18 // 200 tokens output
        // });

        vm.startBroadcast();

        // Deploy OTCv2 contract
        OTCv2 otcv2 = new OTCv2(
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
        console2.log("OTCv2 Contract deployed at:", address(otcv2));
        console2.log("Admin address:", admin);
        console2.log("Client address:", CLIENT_ADDRESS);
        console2.log("Input token:", INPUT_TOKEN == address(0) ? "ETH" : "ERC20");
        console2.log("Output token:", OUTPUT_TOKEN);
        console2.log("Supply count:", otcv2.supplyCount());
        console2.log("Current state:", otcv2.currentState());
    }

    /**
     * @notice Alternative deployment function for demand-side contracts (no supplies)
     * @dev Use this when IS_SUPPLY = false
     */
    function deployDemandSide() public {
        address admin = msg.sender;

        // Empty supplies array for demand-side
        IOTCv2.Supply[] memory supplies = new IOTCv2.Supply[](0);

        vm.startBroadcast();

        OTCv2 otcv2 = new OTCv2(
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

        console2.log("Demand-side OTCv2 Contract deployed at:", address(otcv2));
        console2.log("Admin address:", admin);
        console2.log("Client address:", CLIENT_ADDRESS);
    }
}

