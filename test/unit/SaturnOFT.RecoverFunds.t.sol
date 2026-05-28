// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseSaturnOFTTest} from "../utils/BaseSaturnOFTTest.sol";

/// @dev Audit finding 3.1, recommendation #2: `recoverFunds` invariant.
///      "Test that funds are successfully transferred from a blacklisted address, that the call reverts
///       with `CannotRecoverFromAllowlisted` when `_from` is allowlisted, and that balances update
///       correctly."
contract SaturnOFTRecoverFundsTest is BaseSaturnOFTTest {
    uint256 internal constant AMOUNT = 1_000e18;

    error CannotRecoverFromAllowlisted(address user);

    function test_recoverFunds_happyPath_blacklistedFrom() public {
        _mint(user, AMOUNT);
        _setBlacklisted(user, true);

        assertFalse(token.isAllowlisted(user));

        vm.prank(admin);
        token.recoverFunds(user, recipient, AMOUNT);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(recipient), AMOUNT);
    }

    function test_recoverFunds_revertsWhenFromIsAllowlisted() public {
        // Default Blacklist mode: an address not on the blacklist counts as allowlisted.
        _mint(user, AMOUNT);
        assertTrue(token.isAllowlisted(user));

        vm.expectRevert(abi.encodeWithSelector(CannotRecoverFromAllowlisted.selector, user));
        vm.prank(admin);
        token.recoverFunds(user, recipient, AMOUNT);
    }
}
