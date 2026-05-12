// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {
    OFTBurnMintExtendedRBACUpgradeable
} from "@layerzerolabs/oft-upgradeable-evm-contracts/contracts/extended/OFTBurnMintExtendedRBACUpgradeable.sol";
import {
    AccessControl2StepUpgradeable
} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/access/AccessControl2StepUpgradeable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {SaturnOFT} from "../../contracts/evm/SaturnOFT.sol";
import {SaturnOFTAdapter} from "../../contracts/evm/SaturnOFTAdapter.sol";
import {CreateXLib} from "../lib/CreateXLib.sol";

contract Deploy is Script {
    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 constant BLACKLISTER_ROLE = keccak256("BLACKLISTER_ROLE");
    bytes32 constant WHITELISTER_ROLE = keccak256("WHITELISTER_ROLE");
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 constant FEE_CONFIG_MANAGER_ROLE = keccak256("FEE_CONFIG_MANAGER_ROLE");
    bytes32 constant RATE_LIMITER_MANAGER_ROLE = keccak256("RATE_LIMITER_MANAGER_ROLE");

    bytes4 constant BURN_SELECTOR = 0x9dc29fac; // burn(address,uint256)
    bytes4 constant MINT_SELECTOR = 0x40c10f19; // mint(address,uint256)

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address endpoint = vm.envAddress("LZ_ENDPOINT");
        address feeDeposit = vm.envAddress("FEE_DEPOSIT");
        address defaultAdmin = vm.envAddress("DEFAULT_ADMIN_ROLE");
        string memory tokenName = vm.envString("TOKEN_NAME");
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        uint8 decimals = uint8(vm.envOr("TOKEN_DECIMALS", uint256(18)));
        uint8 rateLimiterScaleDecimals = uint8(vm.envOr("RATE_LIMITER_SCALE_DECIMALS", uint256(0)));
        string memory saltString = vm.envString("SALT_STRING");

        bytes32 tokenSalt = CreateXLib.computeSalt(deployer, saltString);
        bytes32 oftSalt = CreateXLib.computeSalt(deployer, string.concat(saltString, ".oft"));

        console2.log("Deployer:             ", deployer);
        console2.log("Predicted token proxy:", CreateXLib.getCreate3Address(deployer, tokenSalt));
        console2.log("Predicted OFT proxy:  ", CreateXLib.getCreate3Address(deployer, oftSalt));

        vm.startBroadcast(deployerKey);

        // 1. Token impl + proxy
        address tokenImpl = address(new SaturnOFT(decimals));
        address tokenProxy = CreateXLib.CREATEX.deployCreate3(
            tokenSalt,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(tokenImpl, defaultAdmin, abi.encodeCall(SaturnOFT.initialize, (tokenName, tokenSymbol, deployer)))
            )
        );

        // 2. OFT impl + proxy
        address oftImpl = address(
            new SaturnOFTAdapter(tokenProxy, tokenProxy, endpoint, false, BURN_SELECTOR, MINT_SELECTOR, rateLimiterScaleDecimals)
        );
        address oftProxy = CreateXLib.CREATEX.deployCreate3(
            oftSalt,
            abi.encodePacked(
                type(TransparentUpgradeableProxy).creationCode,
                abi.encode(oftImpl, defaultAdmin, abi.encodeCall(OFTBurnMintExtendedRBACUpgradeable.initialize, (deployer, feeDeposit)))
            )
        );

        // 3. Grant the bridge mint/burn rights on the token
        IAccessControl(tokenProxy).grantRole(MINTER_ROLE, oftProxy);
        IAccessControl(tokenProxy).grantRole(BURNER_ROLE, oftProxy);

        // 4. Token sub-roles
        IAccessControl(tokenProxy).grantRole(PAUSER_ROLE, vm.envAddress("PAUSER_ROLE"));
        IAccessControl(tokenProxy).grantRole(UNPAUSER_ROLE, vm.envAddress("UNPAUSER_ROLE"));
        IAccessControl(tokenProxy).grantRole(BLACKLISTER_ROLE, vm.envAddress("BLACKLISTER_ROLE"));
        IAccessControl(tokenProxy).grantRole(WHITELISTER_ROLE, vm.envAddress("WHITELISTER_ROLE"));

        // 5. OFT sub-roles
        IAccessControl(oftProxy).grantRole(PAUSER_ROLE, vm.envAddress("PAUSER_ROLE"));
        IAccessControl(oftProxy).grantRole(UNPAUSER_ROLE, vm.envAddress("UNPAUSER_ROLE"));
        IAccessControl(oftProxy).grantRole(FEE_CONFIG_MANAGER_ROLE, vm.envAddress("FEE_CONFIG_MANAGER_ROLE"));
        IAccessControl(oftProxy).grantRole(RATE_LIMITER_MANAGER_ROLE, vm.envAddress("RATE_LIMITER_MANAGER_ROLE"));

        // 6. Begin admin transfers on both
        AccessControl2StepUpgradeable(tokenProxy).beginDefaultAdminTransfer(defaultAdmin);
        AccessControl2StepUpgradeable(oftProxy).beginDefaultAdminTransfer(defaultAdmin);

        vm.stopBroadcast();

        console2.log("Token impl: ", tokenImpl);
        console2.log("Token proxy:", tokenProxy);
        console2.log("OFT impl:   ", oftImpl);
        console2.log("OFT proxy:  ", oftProxy);
    }
}
