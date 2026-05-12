// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SaturnTimelock} from "../contracts/common/SaturnTimelock.sol";

/**
 * @notice Deploys a SaturnTimelock. Run once per role being timelocked.
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY
 *   MIN_DELAY     delay in seconds before a scheduled action can execute
 *   PROPOSER      address that can schedule actions (e.g. multisig)
 *
 * Executors default to address(0) — anyone can execute after the delay.
 *
 * Run:
 *   forge script script/DeployTimelock.s.sol --rpc-url $RPC_URL --broadcast
 */
contract DeployTimelock is Script {
    function run() external {
        uint256 minDelay = vm.envUint("MIN_DELAY");
        address proposer = vm.envAddress("PROPOSER");

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        address[] memory executors = new address[](1);
        executors[0] = address(0);

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        SaturnTimelock timelock = new SaturnTimelock(minDelay, proposers, executors);
        vm.stopBroadcast();

        console2.log("Timelock:", address(timelock));
        console2.log("Min delay:", minDelay, "seconds");
        console2.log("Proposer:", proposer);
    }
}
