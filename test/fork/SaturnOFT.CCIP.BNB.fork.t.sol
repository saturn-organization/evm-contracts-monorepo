// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {SaturnOFT} from "../../contracts/evm/SaturnOFT.sol";

/// @dev BNB Chain CCIP integration — simulates `BurnWithFromMintTokenPool` calls into `SaturnOFT`.
///
///      The pool contract itself is a Chainlink contract that is not part of this repo. We attach to it by
///      address (`BRIDGE_ADDRESS` env var) and use `vm.prank(bridge)` to make the exact calls the deployed
///      pool would make. This exercises every guard the audit asks about without depending on Chainlink's
///      pool bytecode being importable.
///
///      Per the production wiring (`script/wire/SetBridgeRoles.s.sol`), the pool holds BOTH `BURNER_ROLE`
///      and `MINTER_ROLE` on the token. The test grants those before exercising the flows.
contract SaturnOFTCCIPBNBForkTest is Test {
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
        string memory rpc = vm.envOr("BNB_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            console2.log("SKIP: BNB_RPC_URL is not set");
            skipped = true;
            return;
        }

        uint256 forkBlock = vm.envOr("BNB_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpc);
        } else {
            vm.createSelectFork(rpc, forkBlock);
        }

        bridge = vm.envOr("BRIDGE_ADDRESS", makeAddr("ccipPool"));

        // Deploy a fresh SaturnOFT on the BNB fork. We don't attach to the existing proxy so we can control
        // role state deterministically — the audit's allowlist / pause behaviors are properties of the
        // token contract, identical regardless of which chain the bytecode runs on.
        SaturnOFT impl = new SaturnOFT(6);
        bytes memory initData = abi.encodeCall(SaturnOFT.initialize, ("Saturn USD", "USDat", admin));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), proxyOwner, initData);
        token = SaturnOFT(address(proxy));

        // Mirror SetBridgeRoles.s.sol: pool gets both MINTER and BURNER.
        vm.startPrank(admin);
        token.grantRole(token.MINTER_ROLE(), bridge);
        token.grantRole(token.BURNER_ROLE(), bridge);
        token.grantRole(token.PAUSER_ROLE(), admin);
        token.grantRole(token.UNPAUSER_ROLE(), admin);
        token.grantRole(token.BLACKLISTER_ROLE(), admin);
        vm.stopPrank();

        // Seed user with tokens via the pool's MINTER_ROLE.
        vm.prank(bridge);
        token.mint(user, AMOUNT);

        // User pre-approves the router so a CCIP-style `transferFrom(user, pool, amount)` can run.
        vm.prank(user);
        token.approve(router, type(uint256).max);
    }

    function _maybeSkip() internal view returns (bool) {
        if (skipped) {
            console2.log("Skipping: BNB_RPC_URL unset");
            return true;
        }
        return false;
    }

    // ---------- 1. Pool holds both BURNER_ROLE and MINTER_ROLE ----------

    function test_bnb_poolHoldsBurnAndMintRoles() public view {
        if (skipped) return;
        assertTrue(token.hasRole(token.BURNER_ROLE(), bridge));
        assertTrue(token.hasRole(token.MINTER_ROLE(), bridge));
    }

    // ---------- 2. Outbound (lockOrBurn) happy path ----------

    function test_bnb_outbound_lockOrBurn_happyPath() public {
        if (_maybeSkip()) return;

        uint256 totalSupplyBefore = token.totalSupply();
        uint256 userBalanceBefore = token.balanceOf(user);

        // Router yanks the tokens to the pool.
        vm.prank(router);
        token.transferFrom(user, bridge, AMOUNT);

        // Pool burns from itself.
        vm.prank(bridge);
        token.burn(bridge, AMOUNT);

        assertEq(token.balanceOf(user), userBalanceBefore - AMOUNT);
        assertEq(token.balanceOf(bridge), 0);
        assertEq(token.totalSupply(), totalSupplyBefore - AMOUNT);
    }

    // ---------- 3. Outbound — pause blocks burn ----------

    function test_bnb_outbound_burnRevertsWhenPaused() public {
        if (_maybeSkip()) return;

        vm.prank(router);
        token.transferFrom(user, bridge, AMOUNT);

        vm.prank(admin);
        token.pause();

        // Burn must revert via `whenNotPaused`.
        vm.expectRevert();
        vm.prank(bridge);
        token.burn(bridge, AMOUNT);
    }

    // ---------- 4. Inbound (releaseOrMint) happy path ----------

    function test_bnb_inbound_releaseOrMint_happyPath() public {
        if (_maybeSkip()) return;

        uint256 totalSupplyBefore = token.totalSupply();

        vm.prank(bridge);
        token.mint(recipient, AMOUNT);

        assertEq(token.balanceOf(recipient), AMOUNT);
        assertEq(token.totalSupply(), totalSupplyBefore + AMOUNT);
    }

    // ---------- 6. Inbound is pause-insensitive ----------

    function test_bnb_inbound_mintSucceedsWhilePaused() public {
        if (_maybeSkip()) return;

        vm.prank(admin);
        token.pause();
        assertTrue(token.isPaused());

        // Audited expected behavior on BNB: inbound mints from CCIP must not be blocked by the local
        // pause, otherwise in-flight messages would be lost. Contrast with Ethereum's lock/release path,
        // where pause blocks both directions (see `test_eth_pauseBlocksBothDirections`).
        vm.prank(bridge);
        token.mint(recipient, AMOUNT);

        assertEq(token.balanceOf(recipient), AMOUNT);
    }
}
