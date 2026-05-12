// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {
    OAppCoreRBACUpgradeable
} from "@layerzerolabs/oapp-upgradeable-evm-contracts/contracts/oapp/OAppCoreRBACUpgradeable.sol";

/**
 * Sets the remote OFT peer for a single pathway. Must be called by the
 * OFT's DEFAULT_ADMIN_ROLE holder. This opens the messaging channel —
 * configure libraries, configs, and enforced options first.
 *
 * Required env vars:
 *   OAPP_ADDRESS            deployed OFT proxy on this chain
 *   REMOTE_EID              endpoint id of the remote chain (Ethereum)
 *   REMOTE_PEER             remote adapter address (Ethereum)
 *   DEPLOYER_PRIVATE_KEY    signer (must hold DEFAULT_ADMIN_ROLE on the OFT)
 */
contract SetPeers is Script {
    function run() external {
        address oapp = vm.envAddress("OAPP_ADDRESS");
        uint32 remoteEid = uint32(vm.envUint("REMOTE_EID"));
        address remotePeer = vm.envAddress("REMOTE_PEER");

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        OAppCoreRBACUpgradeable(oapp).setPeer(remoteEid, bytes32(uint256(uint160(remotePeer))));
        vm.stopBroadcast();

        console2.log("Peer set: EID", remoteEid, "->", remotePeer);
    }
}
