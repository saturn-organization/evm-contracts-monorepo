// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {
    OAppCoreRBACUpgradeable
} from "@layerzerolabs/oapp-upgradeable-evm-contracts/contracts/oapp/OAppCoreRBACUpgradeable.sol";

/**
 * Disconnects a SaturnOFTAdapter by clearing the configured peer for a single pathway.
 *
 * Calls setPeer(REMOTE_EID, bytes32(0)), which closes both inbound and outbound
 * messaging on that pathway. Run on each chain that has a deployed adapter
 * (ethereum/ and evm/ variants share the same OAppCoreRBAC surface).
 *
 * Pre-handoff pattern: the deployer must still hold DEFAULT_ADMIN_ROLE on the
 * adapter. After admin handoff to the timelock, route the same call through
 * propose/execute instead.
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY    signer (must hold DEFAULT_ADMIN_ROLE on OAPP_ADDRESS)
 *   OAPP_ADDRESS            adapter proxy on this chain
 *   REMOTE_EID              endpoint id of the remote chain whose peer should be cleared
 *
 * Run:
 *   forge script script/wire/CleanUpAdapter.s.sol --rpc-url $RPC_URL --broadcast
 */
contract CleanUpAdapter is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address oapp = vm.envAddress("OAPP_ADDRESS");
        uint32 remoteEid = uint32(vm.envUint("REMOTE_EID"));

        bytes32 prior = OAppCoreRBACUpgradeable(oapp).peers(remoteEid);
        if (prior == bytes32(0)) {
            console2.log("Adapter:", oapp);
            console2.log("EID    :", remoteEid);
            console2.log("Peer already cleared, nothing to do");
            return;
        }

        vm.startBroadcast(deployerKey);
        OAppCoreRBACUpgradeable(oapp).setPeer(remoteEid, bytes32(0));
        vm.stopBroadcast();

        console2.log("Adapter:    ", oapp);
        console2.log("EID:        ", remoteEid);
        console2.log("Cleared peer (prior value, hex):");
        console2.logBytes32(prior);
    }
}
