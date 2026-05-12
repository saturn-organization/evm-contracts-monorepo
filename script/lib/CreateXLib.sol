// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ICreateX {
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address);
    function computeCreate3Address(bytes32 salt) external view returns (address);
}

library CreateXLib {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function computeSalt(address deployer, string memory contractName) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(bytes20(deployer), bytes1(0), bytes11(keccak256(bytes(contractName)))));
    }

    function getCreate3Address(address deployer, bytes32 salt) internal view returns (address) {
        bytes32 guardedSalt;
        bytes32 deployerWord = bytes32(uint256(uint160(deployer)));
        assembly ("memory-safe") {
            mstore(0x00, deployerWord)
            mstore(0x20, salt)
            guardedSalt := keccak256(0x00, 0x40)
        }
        return CREATEX.computeCreate3Address(guardedSalt);
    }
}
