// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

/**
 * Revokes MINTER_ROLE and BURNER_ROLE from every current holder on the SaturnOFT token proxy.
 *
 * Pre-handoff pattern: the deployer (which still holds DEFAULT_ADMIN_ROLE) enumerates the
 * current role members via AccessControlEnumerable and revokes each one.
 *
 * Required env vars:
 *   DEPLOYER_PRIVATE_KEY    deployer key (must still hold DEFAULT_ADMIN_ROLE on the token)
 *   TOKEN_ADDRESS           the SaturnOFT token proxy
 *
 * Run:
 *   forge script script/wire/CleanUpToken.s.sol --rpc-url $RPC_URL --broadcast
 */
contract CleanUpToken is Script {
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address token = vm.envAddress("TOKEN_ADDRESS");

        address[] memory minters = _snapshotMembers(token, MINTER_ROLE);
        address[] memory burners = _snapshotMembers(token, BURNER_ROLE);

        vm.startBroadcast(deployerKey);
        for (uint256 i = 0; i < minters.length; i++) {
            IAccessControl(token).revokeRole(MINTER_ROLE, minters[i]);
            console2.log("Revoked MINTER_ROLE from:", minters[i]);
        }
        for (uint256 i = 0; i < burners.length; i++) {
            IAccessControl(token).revokeRole(BURNER_ROLE, burners[i]);
            console2.log("Revoked BURNER_ROLE from:", burners[i]);
        }
        vm.stopBroadcast();

        console2.log("Token:                          ", token);
        console2.log(
            "Remaining MINTER_ROLE holders:  ", IAccessControlEnumerable(token).getRoleMemberCount(MINTER_ROLE)
        );
        console2.log(
            "Remaining BURNER_ROLE holders:  ", IAccessControlEnumerable(token).getRoleMemberCount(BURNER_ROLE)
        );
    }

    /// @dev Snapshot holders before mutating; revocations shift the enumerable set's indices.
    function _snapshotMembers(address _token, bytes32 _role) internal view returns (address[] memory members) {
        uint256 count = IAccessControlEnumerable(_token).getRoleMemberCount(_role);
        members = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            members[i] = IAccessControlEnumerable(_token).getRoleMember(_role, i);
        }
    }
}
