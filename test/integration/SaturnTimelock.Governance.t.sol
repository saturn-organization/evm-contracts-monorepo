// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAllowlist} from "@layerzerolabs/utils-evm-contracts/contracts/interfaces/IAllowlist.sol";
import {SaturnOFT} from "../../contracts/evm/SaturnOFT.sol";
import {
    AllowlistRBACUpgradeable
} from "@layerzerolabs/utils-upgradeable-evm-contracts/contracts/allowlist/AllowlistRBACUpgradeable.sol";
import {SaturnTimelock} from "../../contracts/common/SaturnTimelock.sol";

/// @dev End-to-end: `SaturnTimelock` holds `DEFAULT_ADMIN_ROLE` on `SaturnOFT` and administers role grants,
///      allowlist mutations, and pause via the standard schedule/execute timelock cycle.
///
/// @dev Discrepancy flagged: the audit text says "Grant DEFAULT_ADMIN_ROLE to the timelock and renounce from
///      deployer." `AccessControl2StepUpgradeable` forbids both `grantRole(DEFAULT_ADMIN_ROLE,_)` and
///      `renounceRole(DEFAULT_ADMIN_ROLE,_)` — they revert with `AccessControlEnforcedDefaultAdminRules`.
///      Transfer goes through the 2-step flow (`beginDefaultAdminTransfer` → `acceptDefaultAdminTransfer`),
///      exactly as `script/wire/ProposeAcceptAdmin.s.sol` and `ExecuteAcceptAdmin.s.sol` perform it in prod.
contract SaturnTimelockGovernanceTest is Test {
    SaturnOFT internal token;
    SaturnTimelock internal timelock;

    address internal deployer = makeAddr("deployer");
    address internal proposer = makeAddr("proposer");
    address internal proxyOwner = makeAddr("proxyOwner");
    address internal newPool = makeAddr("newPool");
    address internal blockedUser = makeAddr("blockedUser");

    uint256 internal constant MIN_DELAY = 2 days;

    function setUp() public {
        // 1. Deploy SaturnOFT behind a TransparentUpgradeableProxy.
        SaturnOFT impl = new SaturnOFT(18);
        bytes memory initData = abi.encodeCall(SaturnOFT.initialize, ("Saturn USD", "USDat", deployer));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyOwner, initData);
        token = SaturnOFT(address(proxy));

        // 2. Deploy SaturnTimelock with `proposer` as the only proposer and permissionless execution.
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution
        timelock = new SaturnTimelock(MIN_DELAY, proposers, executors);

        // 3. Begin admin transfer to timelock; timelock accepts (no delay needed for acceptance itself).
        vm.prank(deployer);
        token.beginDefaultAdminTransfer(address(timelock));
        vm.prank(address(timelock));
        token.acceptDefaultAdminTransfer();

        // Sanity
        assertEq(token.defaultAdmin(), address(timelock));
        assertTrue(token.hasRole(bytes32(0), address(timelock)));
        assertFalse(token.hasRole(bytes32(0), deployer));
    }

    // ---------- Helpers ----------

    function _schedule(bytes memory payload) internal returns (bytes32) {
        bytes32 id = timelock.hashOperation(address(token), 0, payload, bytes32(0), bytes32(0));
        vm.prank(proposer);
        timelock.schedule(address(token), 0, payload, bytes32(0), bytes32(0), MIN_DELAY);
        return id;
    }

    function _execute(bytes memory payload) internal {
        timelock.execute(address(token), 0, payload, bytes32(0), bytes32(0));
    }

    // ---------- Role grant via timelock ----------

    function test_timelock_grantsMinterRoleViaSchedule() public {
        bytes memory payload = abi.encodeCall(IAccessControl.grantRole, (token.MINTER_ROLE(), newPool));

        bytes32 id = _schedule(payload);

        // Must NOT be executable before delay elapses.
        vm.expectRevert();
        _execute(payload);

        skip(MIN_DELAY);
        _execute(payload);

        assertTrue(token.hasRole(token.MINTER_ROLE(), newPool));
        assertTrue(timelock.isOperationDone(id));

        // The newly-granted role actually works.
        vm.prank(newPool);
        token.mint(makeAddr("recipient"), 1e18);
        assertEq(token.balanceOf(makeAddr("recipient")), 1e18);
    }

    // ---------- Allowlist mutation via timelock ----------

    function test_timelock_blacklistsUserViaSchedule() public {
        // The blacklister sub-role isn't granted yet; the timelock owns DEFAULT_ADMIN_ROLE and uses it to
        // grant itself BLACKLISTER_ROLE, then we schedule the blacklist mutation.
        bytes memory grantPayload =
            abi.encodeCall(IAccessControl.grantRole, (token.BLACKLISTER_ROLE(), address(timelock)));
        _schedule(grantPayload);
        skip(MIN_DELAY);
        _execute(grantPayload);
        assertTrue(token.hasRole(token.BLACKLISTER_ROLE(), address(timelock)));

        IAllowlist.SetAllowlistParam[] memory params = new IAllowlist.SetAllowlistParam[](1);
        params[0] = IAllowlist.SetAllowlistParam({user: blockedUser, isEnabled: true});
        bytes memory blacklistPayload = abi.encodeCall(AllowlistRBACUpgradeable.setBlacklisted, (params));

        _schedule(blacklistPayload);
        skip(MIN_DELAY);
        _execute(blacklistPayload);

        assertTrue(token.isBlacklisted(blockedUser));
        assertFalse(token.isAllowlisted(blockedUser));
    }

    // ---------- Pre-delay execution reverts with the expected error ----------

    function test_timelock_executeBeforeDelay_reverts() public {
        bytes memory payload = abi.encodeCall(IAccessControl.grantRole, (token.MINTER_ROLE(), newPool));
        bytes32 id = _schedule(payload);

        bytes32 readyBitmap = bytes32(1 << uint8(TimelockController.OperationState.Ready));
        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockUnexpectedOperationState.selector, id, readyBitmap)
        );
        _execute(payload);
    }

    // ---------- Schedule below minDelay reverts ----------

    function test_timelock_scheduleBelowMinDelay_reverts() public {
        bytes memory payload = abi.encodeCall(IAccessControl.grantRole, (token.MINTER_ROLE(), newPool));

        vm.expectRevert(
            abi.encodeWithSelector(TimelockController.TimelockInsufficientDelay.selector, MIN_DELAY - 1, MIN_DELAY)
        );
        vm.prank(proposer);
        timelock.schedule(address(token), 0, payload, bytes32(0), bytes32(0), MIN_DELAY - 1);
    }
}
