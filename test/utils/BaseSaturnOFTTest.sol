// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAllowlist} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/IAllowlist.sol";
import {SaturnOFT} from "../../contracts/evm/SaturnOFT.sol";

/// @dev Shared harness: deploys a `SaturnOFT` behind a `TransparentUpgradeableProxy`, grants every sub-role
///      to a named address, and exposes helpers for the most common state mutations.
abstract contract BaseSaturnOFTTest is Test {
    SaturnOFT internal token;
    SaturnOFT internal impl;

    // Named principals
    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");
    address internal blacklister = makeAddr("blacklister");
    address internal whitelister = makeAddr("whitelister");
    address internal minter = makeAddr("minter");
    address internal burner = makeAddr("burner");
    address internal user = makeAddr("user");
    address internal recipient = makeAddr("recipient");
    address internal pool = makeAddr("pool");
    address internal router = makeAddr("router");
    address internal proxyOwner = makeAddr("proxyOwner");
    address internal stranger = makeAddr("stranger");

    string internal constant TOKEN_NAME = "Saturn USD";
    string internal constant TOKEN_SYMBOL = "USDat";
    uint8 internal constant TOKEN_DECIMALS = 18;

    function setUp() public virtual {
        impl = new SaturnOFT(TOKEN_DECIMALS);
        bytes memory initData = abi.encodeCall(SaturnOFT.initialize, (TOKEN_NAME, TOKEN_SYMBOL, admin));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyOwner, initData);
        token = SaturnOFT(address(proxy));

        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.BURNER_ROLE(), burner);
        token.grantRole(token.PAUSER_ROLE(), pauser);
        token.grantRole(token.UNPAUSER_ROLE(), unpauser);
        token.grantRole(token.BLACKLISTER_ROLE(), blacklister);
        token.grantRole(token.WHITELISTER_ROLE(), whitelister);
        vm.stopPrank();
    }

    // ============ Allowlist helpers ============

    function _setBlacklisted(address _user, bool _enabled) internal {
        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam({user: _user, isEnabled: _enabled});
        vm.prank(blacklister);
        token.setBlacklisted(params);
    }

    function _setWhitelisted(address _user, bool _enabled) internal {
        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam({user: _user, isEnabled: _enabled});
        vm.prank(whitelister);
        token.setWhitelisted(params);
    }

    function _setMode(IAllowlist.AllowlistMode _mode) internal {
        vm.prank(admin);
        token.setAllowlistMode(_mode);
    }

    // ============ Pause helpers ============

    function _pause() internal {
        vm.prank(pauser);
        token.pause();
    }

    function _unpause() internal {
        vm.prank(unpauser);
        token.unpause();
    }

    // ============ Token helpers ============

    function _mint(address _to, uint256 _amount) internal {
        vm.prank(minter);
        token.mint(_to, _amount);
    }

    function _burn(address _from, uint256 _amount) internal {
        vm.prank(burner);
        token.burn(_from, _amount);
    }
}
