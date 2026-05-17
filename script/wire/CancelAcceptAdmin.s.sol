// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {
    AccessControl2StepUpgradeable
} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/access/AccessControl2StepUpgradeable.sol";

/**
 * Cancels the admin handoff to the timelock for the OApp adapter only.
 *
 * Two segments, two signers:
 *   1. Fireblocks signer ($ADMIN_TIMELOCK_PROPOSER, must have CANCELLER_ROLE on the
 *      timelock) calls TimelockController.cancel(opId) for the pending
 *      acceptDefaultAdminTransfer() scheduled by ProposeAcceptAdmin.s.sol.
 *   2. Deployer (still holds DEFAULT_ADMIN_ROLE on the adapter pre-handoff) calls
 *      beginDefaultAdminTransfer(address(0)) on the adapter to clear the pending
 *      admin slot.
 *
 * Does NOT touch the token (TOKEN_ADDRESS), even on BNB.
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY    deployer key (must still hold DEFAULT_ADMIN_ROLE on OAPP_ADDRESS)
 *   DEFAULT_ADMIN_ROLE      the timelock contract (pending admin on the adapter)
 *   OAPP_ADDRESS            the adapter proxy
 *
 * Run:
 *   fireblocks-json-rpc --http -- forge script script/wire/CancelAcceptAdmin.s.sol \
 *     --sender $ADMIN_TIMELOCK_PROPOSER --slow --broadcast --unlocked --rpc-url {}
 */
contract CancelAcceptAdmin is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address timelock = vm.envAddress("DEFAULT_ADMIN_ROLE");
        address oapp = vm.envAddress("OAPP_ADDRESS");

        bytes memory data = abi.encodeCall(AccessControl2StepUpgradeable.acceptDefaultAdminTransfer, ());
        bytes32 opId = TimelockController(payable(timelock)).hashOperation(oapp, 0, data, bytes32(0), bytes32(0));

        // 1. Fireblocks: cancel the scheduled timelock op
        vm.startBroadcast();
        TimelockController(payable(timelock)).cancel(opId);
        vm.stopBroadcast();

        console2.log("Cancelled timelock op on:", timelock);
        console2.log("Operation ID:           ", uint256(opId));

        // 2. Deployer: clear the pending admin on the OApp
        vm.startBroadcast(deployerKey);
        AccessControl2StepUpgradeable(oapp).beginDefaultAdminTransfer(address(0));
        vm.stopBroadcast();

        console2.log("Cleared pending admin on:", oapp);
    }
}
