// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * Grants MINTER_ROLE and BURNER_ROLE to the new bridge on the SaturnOFT token proxy.
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY    deployer key (must still hold DEFAULT_ADMIN_ROLE on TOKEN_ADDRESS)
 *   TOKEN_ADDRESS           the SaturnOFT token proxy
 *   BRIDGE_ADDRESS          the new bridge to be granted mint/burn rights
 *
 * Run:
 *   forge script script/wire/SetBridgeRoles.s.sol --rpc-url $RPC_URL --broadcast
 */
contract SetBridgeRoles is Script {
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address token = vm.envAddress("TOKEN_ADDRESS");
        address bridge = vm.envAddress("BRIDGE_ADDRESS");

        vm.startBroadcast(deployerKey);
        IAccessControl(token).grantRole(MINTER_ROLE, bridge);
        IAccessControl(token).grantRole(BURNER_ROLE, bridge);
        vm.stopBroadcast();

        console2.log("Token:  ", token);
        console2.log("Bridge: ", bridge);
        console2.log("Granted MINTER_ROLE and BURNER_ROLE");
    }
}
