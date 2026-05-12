// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IRateLimiter} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/IRateLimiter.sol";

/**
 * Configures GLOBAL rate limits on the OFT/adapter with hardcoded defaults:
 *   20,000,000 tokens outbound / inbound, 1-day window, net accounting on.
 *
 * The script does two things, IN THIS ORDER:
 *   1. setRateLimitConfigs(id=0, ...) — configures the bucket
 *   2. setRateLimitGlobalConfig(useGlobalState=true) — activates global mode
 *
 * Required env vars:
 *   OAPP_ADDRESS            deployed OFT/adapter proxy
 *
 * Optional env vars:
 *   TOKEN_DECIMALS          default 18 — scales the 20M token cap into wei
 *
 * Run:
    fireblocks-json-rpc --http -- \
      forge script script/wire/SetRateLimits.s.sol \
      --sender $RATE_LIMITER_MANAGER_ADDRESS --slow --broadcast --unlocked --rpc-url {}
 */
contract SetRateLimits is Script {
    uint256 internal constant LIMIT_TOKENS = 1_000_000;
    uint32 internal constant WINDOW = 3_600;

    function run() external {
        address oapp = vm.envAddress("OAPP_ADDRESS");
        uint8 tokenDecimals = uint8(vm.envOr("TOKEN_DECIMALS", uint256(18)));
        uint96 limit = uint96(LIMIT_TOKENS * 10 ** tokenDecimals);

        IRateLimiter.SetRateLimitConfigParam[]
            memory params = new IRateLimiter.SetRateLimitConfigParam[](1);
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

        vm.startBroadcast();
        IRateLimiter(oapp).setRateLimitConfigs(params);
        IRateLimiter(oapp).setRateLimitGlobalConfig(
            IRateLimiter.RateLimitGlobalConfig({
                useGlobalState: true,
                isGloballyDisabled: false
            })
        );
        vm.stopBroadcast();

        console2.log("Global rate limit configured on:", oapp);
        console2.log("Limit (out=in):", limit);
        console2.log("Window:", WINDOW);
    }
}
