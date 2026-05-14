// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {
    AccessControl2StepUpgradeable
} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/access/AccessControl2StepUpgradeable.sol";

/**
 * Schedules a call from the timelock to acceptDefaultAdminTransfer() on the OApp proxy.
 * On BNB (chainid 56) it also schedules the same call for TOKEN_ADDRESS (the underlying
 * SaturnOFT token proxy), since both contracts have pending admin transfers.
 *
 * Required env vars:
 *   DEFAULT_ADMIN_ROLE    the timelock contract (pending admin on the proxies)
 *   OAPP_ADDRESS          the adapter proxy
 *   TOKEN_ADDRESS         the token proxy (only required on BNB)
 *
 * Run:
 *   fireblocks-json-rpc --http -- forge script script/wire/ProposeAcceptAdmin.s.sol \
 *     --sender $ADMIN_TIMELOCK_PROPOSER --slow --broadcast --unlocked --rpc-url {}
 */
contract ProposeAcceptAdmin is Script {
    uint256 constant BNB_CHAIN_ID = 56;

    function run() external {
        address timelock = vm.envAddress("DEFAULT_ADMIN_ROLE");
        uint256 delay = TimelockController(payable(timelock)).getMinDelay();

        vm.startBroadcast();
        _propose(timelock, vm.envAddress("OAPP_ADDRESS"), delay);
        if (block.chainid == BNB_CHAIN_ID) {
            _propose(timelock, vm.envAddress("TOKEN_ADDRESS"), delay);
        }
        vm.stopBroadcast();
    }

    function _propose(address timelock, address target, uint256 delay) internal {
        bytes memory data = abi.encodeCall(AccessControl2StepUpgradeable.acceptDefaultAdminTransfer, ());
        TimelockController(payable(timelock)).schedule(target, 0, data, bytes32(0), bytes32(0), delay);

        bytes32 opId = TimelockController(payable(timelock)).hashOperation(
            target, 0, data, bytes32(0), bytes32(0)
        );
        console2.log("Scheduled on timelock:", timelock);
        console2.log("Target:               ", target);
        console2.log("Operation ID:         ", uint256(opId));
        console2.log("Delay (seconds):      ", delay);
    }
}
