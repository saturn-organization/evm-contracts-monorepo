// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {
    OAppOptionsType3RBACUpgradeable
} from "@layerzerolabs/oapp-upgradeable-evm-contracts/contracts/oapp/options-type-3/OAppOptionsType3RBACUpgradeable.sol";
import {IOAppOptionsType3} from "@layerzerolabs/oapp-evm-contracts/contracts/interfaces/IOAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm-contracts/contracts/oapp/libs/OptionsBuilder.sol";

/**
 * Sets enforced execution options on the OApp for SEND (msgType 1) for the
 * remote pathway. Must be called by the OApp's DEFAULT_ADMIN_ROLE holder.
 *
 * Required env vars:
 *   OAPP_ADDRESS            deployed adapter proxy
 *   REMOTE_EID              endpoint id of the remote chain (BNB)
 *   SEND_GAS                gas the executor allocates for lzReceive on remote
 *   DEPLOYER_PRIVATE_KEY    signer (must hold DEFAULT_ADMIN_ROLE on the OApp)
 *
 * Optional env vars:
 *   SEND_VALUE              native value forwarded with lzReceive (default 0)
 */
contract SetEnforcedOptions is Script {
    using OptionsBuilder for bytes;

    uint16 internal constant SEND = 1;

    function run() external {
        address oapp = vm.envAddress("OAPP_ADDRESS");
        uint32 remoteEid = uint32(vm.envUint("REMOTE_EID"));
        uint128 sendGas = uint128(vm.envUint("SEND_GAS"));
        uint128 sendValue = uint128(vm.envOr("SEND_VALUE", uint256(0)));

        bytes memory sendOpts = OptionsBuilder.newOptions().addExecutorLzReceiveOption(sendGas, sendValue);

        IOAppOptionsType3.EnforcedOptionParam[] memory params = new IOAppOptionsType3.EnforcedOptionParam[](1);
        params[0] = IOAppOptionsType3.EnforcedOptionParam({eid: remoteEid, msgType: SEND, options: sendOpts});

        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        OAppOptionsType3RBACUpgradeable(oapp).setEnforcedOptions(params);
        vm.stopBroadcast();

        console2.log("Enforced options set for remote EID:", remoteEid);
    }
}
