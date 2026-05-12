// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IRateLimiter} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/IRateLimiter.sol";

/**
 * Configures GLOBAL rate limits on the OFT/adapter with hardcoded defaults.
 *
 * Pre-handoff pattern: the deployer (which still holds DEFAULT_ADMIN_ROLE) grants
 * itself RATE_LIMITER_MANAGER_ROLE, configures the limits, then revokes the role.
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY    deployer key (must still hold DEFAULT_ADMIN_ROLE)
 *   OAPP_ADDRESS            deployed OFT/adapter proxy
 *
 * Optional env vars:
 *   TOKEN_DECIMALS          default 18
 *
 * Run:
 *   forge script script/wire/SetRateLimits.s.sol --rpc-url $RPC_URL --broadcast
 */
contract SetRateLimits is Script {
    bytes32 internal constant RATE_LIMITER_MANAGER_ROLE = keccak256("RATE_LIMITER_MANAGER_ROLE");

    uint256 internal constant LIMIT_TOKENS = 1_000_000;
    uint32 internal constant WINDOW = 3_600;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address oapp = vm.envAddress("OAPP_ADDRESS");
        uint8 tokenDecimals = uint8(vm.envOr("TOKEN_DECIMALS", uint256(18)));
        uint96 limit = uint96(LIMIT_TOKENS * 10 ** tokenDecimals);

        IRateLimiter.SetRateLimitConfigParam[] memory params = new IRateLimiter.SetRateLimitConfigParam[](1);
        params[0] = IRateLimiter.SetRateLimitConfigParam({
            id: 0,
            config: IRateLimiter.RateLimitConfig({
                overrideDefaultConfig: true,
                outboundEnabled: true,
                inboundEnabled: true,
                netAccountingEnabled: true,
                addressExemptionEnabled: false,
                outboundLimit: limit,
                inboundLimit: limit,
                outboundWindow: WINDOW,
                inboundWindow: WINDOW
            })
        });

        vm.startBroadcast(deployerKey);
        IAccessControl(oapp).grantRole(RATE_LIMITER_MANAGER_ROLE, deployer);
        IRateLimiter(oapp).setRateLimitConfigs(params);
        IRateLimiter(oapp).setRateLimitGlobalConfig(
            IRateLimiter.RateLimitGlobalConfig({useGlobalState: true, isGloballyDisabled: false})
        );
        IAccessControl(oapp).revokeRole(RATE_LIMITER_MANAGER_ROLE, deployer);
        vm.stopBroadcast();

        console2.log("Global rate limit configured on:", oapp);
        console2.log("Limit (out=in):", limit);
        console2.log("Window:", WINDOW);
    }
}
