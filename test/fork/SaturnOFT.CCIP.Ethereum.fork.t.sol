// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {SaturnOFT} from "../../contracts/evm/SaturnOFT.sol";

/// @dev Ethereum mainnet CCIP integration — simulates `LockReleaseTokenPool` calls into `SaturnOFT`.
///
///      No `MINTER_ROLE` / `BURNER_ROLE` grants are needed on Ethereum (see audit §3 and the fact that
///      `script/wire/SetBridgeRoles.s.sol` is not run on Ethereum). Outbound is `transferFrom` (lock)
///      and inbound is `transfer` (release). Allowlist coverage on every participating address is what
///      determines success.
///
///      Per `SaturnOFT.transferFrom`, the modifiers `onlyAllowlisted(msg.sender)`, `onlyAllowlisted(_from)`,
///      and `onlyAllowlisted(_to)` all apply. So a lock requires (router, user, pool) all allowlisted.
///      A release via `transfer` requires (pool, recipient) all allowlisted.
contract SaturnOFTCCIPEthereumForkTest is Test {
    SaturnOFT internal token;

    address internal admin = makeAddr("admin");
    address internal bridge; // = BRIDGE_ADDRESS (the CCIP pool)
    address internal router = makeAddr("ccipRouter");
    address internal user = makeAddr("user");
    address internal recipient = makeAddr("recipient");
    address internal proxyOwner = makeAddr("proxyOwner");

    uint256 internal constant AMOUNT = 100e18;

    bool internal skipped;

    function setUp() public {
        string memory rpc = vm.envOr("ETHEREUM_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            console2.log("SKIP: ETHEREUM_RPC_URL is not set");
            skipped = true;
            return;
        }

        uint256 forkBlock = vm.envOr("ETHEREUM_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpc);
        } else {
            vm.createSelectFork(rpc, forkBlock);
        }

        bridge = vm.envOr("BRIDGE_ADDRESS", makeAddr("ccipPool"));

        SaturnOFT impl = new SaturnOFT(18);
        bytes memory initData = abi.encodeCall(SaturnOFT.initialize, ("Saturn USD", "USDat", admin));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyOwner, initData);
        token = SaturnOFT(address(proxy));

        // Sub-roles needed to mutate state during tests. NO MINTER/BURNER for the bridge — that's the
        // whole point of the lock/release design on Ethereum.
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), admin);
        token.grantRole(token.PAUSER_ROLE(), admin);
        token.grantRole(token.UNPAUSER_ROLE(), admin);
        token.grantRole(token.BLACKLISTER_ROLE(), admin);
        vm.stopPrank();

        // Seed the user.
        vm.prank(admin);
        token.mint(user, AMOUNT);

        vm.prank(user);
        token.approve(router, type(uint256).max);
    }

    function _maybeSkip() internal view returns (bool) {
        if (skipped) {
            console2.log("Skipping: ETHEREUM_RPC_URL unset");
            return true;
        }
        return false;
    }

    // ---------- 1. Outbound (lock) happy path ----------

    function test_eth_outbound_lock_happyPath() public {
        if (_maybeSkip()) return;

        vm.prank(router);
        token.transferFrom(user, bridge, AMOUNT);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(bridge), AMOUNT);
        // Locked, not burned — total supply unchanged.
        assertEq(token.totalSupply(), AMOUNT);
    }

    // ---------- 2. Inbound (release) happy path ----------

    function test_eth_inbound_release_happyPath() public {
        if (_maybeSkip()) return;

        // Pre-position locked balance on the pool.
        vm.prank(admin);
        token.mint(bridge, AMOUNT);

        vm.prank(bridge);
        token.transfer(recipient, AMOUNT);

        assertEq(token.balanceOf(bridge), 0);
        assertEq(token.balanceOf(recipient), AMOUNT);
    }

    // ---------- 3. Pause blocks BOTH directions ----------
    //
    // Contrast with BNB's `test_bnb_inbound_mintSucceedsWhilePaused`: on BNB the inbound side uses
    // `mint`, which has no pause guard. On Ethereum the inbound side uses `transfer`, which carries
    // `whenNotPaused` — so a local pause halts the lock/release path in both directions.

    function test_eth_pauseBlocksBothDirections() public {
        if (_maybeSkip()) return;

        // Pre-position locked balance on the pool so the inbound side has something to release.
        vm.prank(admin);
        token.mint(bridge, AMOUNT);

        vm.prank(admin);
        token.pause();
        assertTrue(token.isPaused());

        // Outbound (lock) blocked.
        vm.expectRevert();
        vm.prank(router);
        token.transferFrom(user, bridge, AMOUNT);

        // Inbound (release) blocked.
        vm.expectRevert();
        vm.prank(bridge);
        token.transfer(recipient, AMOUNT);
    }
}
