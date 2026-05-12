// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    OFTLockUnlockExtendedRBACUpgradeable
} from "@layerzerolabs/oft-upgradeable-evm-contracts/contracts/extended/OFTLockUnlockExtendedRBACUpgradeable.sol";
import {
    AccessControl2StepUpgradeable
} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/access/AccessControl2StepUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {SaturnOFTAdapter} from "../../contracts/ethereum/SaturnOFTAdapter.sol";
import {CreateXLib} from "../lib/CreateXLib.sol";

contract Deploy is Script {
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 constant FEE_CONFIG_MANAGER_ROLE = keccak256("FEE_CONFIG_MANAGER_ROLE");
    bytes32 constant RATE_LIMITER_MANAGER_ROLE = keccak256("RATE_LIMITER_MANAGER_ROLE");

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address token = vm.envAddress("TOKEN_ADDRESS");
        address endpoint = vm.envAddress("LZ_ENDPOINT");
        address feeDeposit = vm.envAddress("FEE_DEPOSIT");
        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN_ROLE");
        uint8 rateLimiterScaleDecimals = uint8(vm.envOr("RATE_LIMITER_SCALE_DECIMALS", uint256(0)));
        string memory saltString = vm.envString("SALT_STRING");

        bytes32 salt = CreateXLib.computeSalt(deployer, saltString);

        console2.log("Deployer:        ", deployer);
        console2.log("Predicted proxy: ", CreateXLib.getCreate3Address(deployer, salt));

        vm.startBroadcast(deployerKey);

        address impl = address(new SaturnOFTAdapter(token, endpoint, rateLimiterScaleDecimals));

        bytes memory initData = abi.encodeCall(OFTLockUnlockExtendedRBACUpgradeable.initialize, (deployer, feeDeposit));

        address proxy = CreateXLib.CREATEX
            .deployCreate3(
                salt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode, abi.encode(impl, defaultAdmin, initData)
                )
            );

        IAccessControl(proxy).grantRole(PAUSER_ROLE, vm.envAddress("PAUSER_ROLE"));
        IAccessControl(proxy).grantRole(UNPAUSER_ROLE, vm.envAddress("UNPAUSER_ROLE"));
        IAccessControl(proxy).grantRole(FEE_CONFIG_MANAGER_ROLE, vm.envAddress("FEE_CONFIG_MANAGER_ROLE"));
        IAccessControl(proxy).grantRole(RATE_LIMITER_MANAGER_ROLE, vm.envAddress("RATE_LIMITER_MANAGER_ROLE"));

        AccessControl2StepUpgradeable(proxy).beginDefaultAdminTransfer(defaultAdmin);

        vm.stopBroadcast();

        console2.log("Implementation: ", impl);
        console2.log("Proxy:          ", proxy);
    }
}
