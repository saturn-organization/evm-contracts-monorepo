// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    AccessControl2StepUpgradeable
} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/access/AccessControl2StepUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {SaturnOFT} from "../../contracts/evm/SaturnOFT.sol";
import {CreateXLib} from "../lib/CreateXLib.sol";

contract Deploy is Script {
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 constant BLACKLISTER_ROLE = keccak256("BLACKLISTER_ROLE");
    bytes32 constant WHITELISTER_ROLE = keccak256("WHITELISTER_ROLE");

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN_ROLE");
        string memory tokenName = vm.envString("TOKEN_NAME");
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        uint8 decimals = uint8(vm.envOr("TOKEN_DECIMALS", uint256(18)));
        string memory saltString = vm.envString("SALT_STRING");

        bytes32 tokenSalt = CreateXLib.computeSalt(deployer, saltString);

        console2.log("Deployer:             ", deployer);
        console2.log("Predicted token proxy:", CreateXLib.getCreate3Address(deployer, tokenSalt));

        vm.startBroadcast(deployerKey);

        // 1. Token impl + proxy
        address tokenImpl = address(new SaturnOFT(decimals));
        address tokenProxy = CreateXLib.CREATEX
            .deployCreate3(
                tokenSalt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(
                        tokenImpl,
                        defaultAdmin,
                        abi.encodeCall(SaturnOFT.initialize, (tokenName, tokenSymbol, deployer))
                    )
                )
            );

        // 2. Token sub-roles
        IAccessControl(tokenProxy).grantRole(PAUSER_ROLE, vm.envAddress("PAUSER_ROLE"));
        IAccessControl(tokenProxy).grantRole(UNPAUSER_ROLE, vm.envAddress("UNPAUSER_ROLE"));
        IAccessControl(tokenProxy).grantRole(BLACKLISTER_ROLE, vm.envAddress("BLACKLISTER_ROLE"));
        IAccessControl(tokenProxy).grantRole(WHITELISTER_ROLE, vm.envAddress("WHITELISTER_ROLE"));

        // 3. Begin admin transfer
        AccessControl2StepUpgradeable(tokenProxy).beginDefaultAdminTransfer(defaultAdmin);

        vm.stopBroadcast();

        console2.log("Token impl: ", tokenImpl);
        console2.log("Token proxy:", tokenProxy);
    }
}
