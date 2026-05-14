// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {
    AccessControl2StepUpgradeable
} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/access/AccessControl2StepUpgradeable.sol";

/**
 * Executes the timelock operations scheduled by ProposeAcceptAdmin.s.sol.
 * On BNB (chainid 56) it also executes the token-proxy operation.
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY    any funded EOA — execution is permissionless
 *   DEFAULT_ADMIN_ROLE      the timelock contract
 *   OAPP_ADDRESS            the adapter proxy (must match propose)
 *   TOKEN_ADDRESS           the token proxy (only required on BNB)
 *
 * Run:
 *   forge script script/wire/ExecuteAcceptAdmin.s.sol --rpc-url $RPC_URL --broadcast
 */
contract ExecuteAcceptAdmin is Script {
    uint256 constant BNB_CHAIN_ID = 56;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address timelock = vm.envAddress("DEFAULT_ADMIN_ROLE");

        vm.startBroadcast(deployerKey);
        _execute(timelock, vm.envAddress("OAPP_ADDRESS"));
        if (block.chainid == BNB_CHAIN_ID) {
            _execute(timelock, vm.envAddress("TOKEN_ADDRESS"));
        }
        vm.stopBroadcast();
    }

    function _execute(address timelock, address target) internal {
        bytes memory data = abi.encodeCall(AccessControl2StepUpgradeable.acceptDefaultAdminTransfer, ());
        TimelockController(payable(timelock)).execute(target, 0, data, bytes32(0), bytes32(0));

        console2.log("Admin claimed on:", target);
        console2.log("via timelock:    ", timelock);
    }
}
