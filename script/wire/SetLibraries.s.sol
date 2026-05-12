// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/**
 * Sets the send and receive message libraries on the LayerZero V2 Endpoint
 * for the OFT's pathway to the remote chain. Must be called by the OFT's
 * delegate (synced to DEFAULT_ADMIN_ROLE in the RBAC variant).
 *
 * Required env vars:
 *   LZ_ENDPOINT             LayerZero V2 endpoint on this chain
 *   OAPP_ADDRESS            deployed OFT proxy
 *   REMOTE_EID              endpoint id of the remote chain (Ethereum)
 *   SEND_LIB_ADDRESS        SendUln302 address on this chain
 *   RECEIVE_LIB_ADDRESS     ReceiveUln302 address on this chain
 *   DEPLOYER_PRIVATE_KEY    signer (must be the OFT delegate)
 *
 * Optional env vars:
 *   GRACE_PERIOD            blocks of grace before old receive lib expires
 *                           (default 0 = immediate switch)
 */
contract SetLibraries is Script {
    function run() external {
        address endpoint = vm.envAddress("LZ_ENDPOINT");
        address oapp = vm.envAddress("OAPP_ADDRESS");
        uint32 remoteEid = uint32(vm.envUint("REMOTE_EID"));
        address sendLib = vm.envAddress("SEND_LIB_ADDRESS");
        address receiveLib = vm.envAddress("RECEIVE_LIB_ADDRESS");
        uint256 gracePeriod = vm.envOr("GRACE_PERIOD", uint256(0));

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        ILayerZeroEndpointV2(endpoint).setSendLibrary(oapp, remoteEid, sendLib);
        ILayerZeroEndpointV2(endpoint).setReceiveLibrary(oapp, remoteEid, receiveLib, gracePeriod);

        vm.stopBroadcast();

        console2.log("Send lib set   :", sendLib);
        console2.log("Receive lib set:", receiveLib);
        console2.log("Remote EID     :", remoteEid);
    }
}
