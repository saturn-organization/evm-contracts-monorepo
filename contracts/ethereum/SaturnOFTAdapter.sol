// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    OFTLockUnlockExtendedRBACUpgradeable
} from "@layerzerolabs/oft-upgradeable-evm-contracts/contracts/extended/OFTLockUnlockExtendedRBACUpgradeable.sol";

contract SaturnOFTAdapter is OFTLockUnlockExtendedRBACUpgradeable {
    constructor(address _token, address _endpoint, uint8 _rateLimiterScaleDecimals)
        OFTLockUnlockExtendedRBACUpgradeable(_token, _endpoint, _rateLimiterScaleDecimals)
    {
        _disableInitializers();
    }
}
