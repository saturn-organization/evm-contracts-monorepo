// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

struct UlnConfig {
    uint64 confirmations;
    uint8 requiredDVNCount;
    uint8 optionalDVNCount;
    uint8 optionalDVNThreshold;
    address[] requiredDVNs;
    address[] optionalDVNs;
}

/**
 * Configures the receive-side ULN (DVNs + confirmations) on the Endpoint
 * for messages flowing FROM the remote chain TO this chain. Must be called
 * by the OApp's delegate.
 *
 * Required env vars:
 *   LZ_ENDPOINT             LayerZero V2 endpoint on this chain
 *   OAPP_ADDRESS            deployed adapter proxy
 *   REMOTE_EID              endpoint id of the remote chain (BNB)
 *   RECEIVE_LIB_ADDRESS     ReceiveUln302 address on this chain
 *   CONFIRMATIONS           min source confirmations before accepting message
 *   REQUIRED_DVNS           comma-separated DVN addresses, sorted ascending
 *   DEPLOYER_PRIVATE_KEY    signer (must be the OApp delegate)
 *
 * Optional env vars:
 *   OPTIONAL_DVNS           comma-separated optional DVN addresses (default empty)
 *   OPTIONAL_DVN_THRESHOLD  default 0
 */
contract SetReceiveConfig is Script {
    uint32 internal constant ULN_CONFIG_TYPE = 2;

    function run() external {
        address endpoint = vm.envAddress("LZ_ENDPOINT");
        address oapp = vm.envAddress("OAPP_ADDRESS");
        uint32 remoteEid = uint32(vm.envUint("REMOTE_EID"));
        address receiveLib = vm.envAddress("RECEIVE_LIB_ADDRESS");

        uint64 confirmations = uint64(vm.envUint("CONFIRMATIONS_RECEIVE"));
        address[] memory requiredDVNs = vm.envAddress("REQUIRED_DVNS", ",");
        address[] memory empty;
        address[] memory optionalDVNs = vm.envOr("OPTIONAL_DVNS", ",", empty);
        uint8 optionalDVNThreshold = uint8(vm.envOr("OPTIONAL_DVN_THRESHOLD", uint256(0)));

        UlnConfig memory uln = UlnConfig({
            confirmations: confirmations,
            requiredDVNCount: uint8(requiredDVNs.length),
            optionalDVNCount: uint8(optionalDVNs.length),
            optionalDVNThreshold: optionalDVNThreshold,
            requiredDVNs: requiredDVNs,
            optionalDVNs: optionalDVNs
        });

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({eid: remoteEid, configType: ULN_CONFIG_TYPE, config: abi.encode(uln)});

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        ILayerZeroEndpointV2(endpoint).setConfig(oapp, receiveLib, params);
        vm.stopBroadcast();

        console2.log("Receive config set for remote EID:", remoteEid);
    }
}
