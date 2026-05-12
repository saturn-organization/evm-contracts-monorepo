// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    OFTBurnMintExtendedRBACUpgradeable
} from "@layerzerolabs/oft-upgradeable-evm-contracts/contracts/extended/OFTBurnMintExtendedRBACUpgradeable.sol";

contract SaturnOFTAdapter is OFTBurnMintExtendedRBACUpgradeable {
    constructor(
        address _token,
        address _burnerMinter,
        address _endpoint,
        bool _approvalRequired,
        bytes4 _burnSelector,
        bytes4 _mintSelector,
        uint8 _rateLimiterScaleDecimals
    )
        OFTBurnMintExtendedRBACUpgradeable(
            _token, _burnerMinter, _endpoint, _approvalRequired, _burnSelector, _mintSelector, _rateLimiterScaleDecimals
        )
    {
        _disableInitializers();
    }
}
