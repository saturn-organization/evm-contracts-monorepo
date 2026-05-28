// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseSaturnOFTTest} from "../utils/BaseSaturnOFTTest.sol";
import {IAllowlist} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/IAllowlist.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @dev Audit finding 3.1, recommendation #4: access control matrix.
///      "For each role-gated function (mint, burn, recoverFunds, pause/unpause, allowlist management),
///       assert that an unauthorized caller is rejected with the correct error."
contract SaturnOFTAccessControlTest is BaseSaturnOFTTest {
    function _expectMissingRole(address caller, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, role));
        vm.prank(caller);
    }

    function test_mint_rejectsCallerWithoutMinterRole() public {
        _expectMissingRole(stranger, token.MINTER_ROLE());
        token.mint(recipient, 1e18);
    }

    function test_burn_rejectsCallerWithoutBurnerRole() public {
        _mint(user, 1e18);
        _expectMissingRole(stranger, token.BURNER_ROLE());
        token.burn(user, 1e18);
    }

    function test_recoverFunds_rejectsCallerWithoutAdminRole() public {
        _expectMissingRole(stranger, bytes32(0)); // DEFAULT_ADMIN_ROLE == 0x00..00
        token.recoverFunds(user, recipient, 1e18);
    }

    function test_pause_rejectsCallerWithoutPauserRole() public {
        _expectMissingRole(stranger, token.PAUSER_ROLE());
        token.pause();
    }

    function test_unpause_rejectsCallerWithoutUnpauserRole() public {
        _pause();
        _expectMissingRole(stranger, token.UNPAUSER_ROLE());
        token.unpause();
    }

    function test_setBlacklisted_rejectsCallerWithoutBlacklisterRole() public {
        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam({user: user, isEnabled: true});
        _expectMissingRole(stranger, token.BLACKLISTER_ROLE());
        token.setBlacklisted(params);
    }

    function test_setWhitelisted_rejectsCallerWithoutWhitelisterRole() public {
        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam({user: user, isEnabled: true});
        _expectMissingRole(stranger, token.WHITELISTER_ROLE());
        token.setWhitelisted(params);
    }
}
