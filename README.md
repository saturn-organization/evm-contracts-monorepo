## USDat BNB Config
Deployer:              0x59Ebb7143dDDd7b045dE7B0bd0F99446143F1624
Predicted token proxy: 0x0Bb150DFa86EA5d7742F07FEfCD8E8edA81D64eF
Token impl:  0x65458213Bb2398f968cA1760b806956966B9adAc
Token proxy: 0x0Bb150DFa86EA5d7742F07FEfCD8E8edA81D64eF
Chainlink Adapter:   0x904939A965eDc2Efbd44Fd4db223f07680510C61

## sUSDat BNB Config
Deployer:              0x59Ebb7143dDDd7b045dE7B0bd0F99446143F1624
Predicted token proxy: 0x9cd57D3685E6868caCaA8BDCaAf52CBdEBf4fA25
Token impl:  0x5885f15E70BD20bF2FBa9382B03aeDB2608B3Ad2
Token proxy: 0x9cd57D3685E6868caCaA8BDCaAf52CBdEBf4fA25
Chainlink Adapter:   0xe2f5aEFf1C065Fac95e7F48ba854470d41B66B7c


# 1. Propose (multisig via Fireblocks)
fireblocks-json-rpc --http -- forge script script/wire/ProposeAcceptAdmin.s.sol \
  --sender $ADMIN_TIMELOCK_PROPOSER --slow --broadcast --unlocked --rpc-url {}

# 2. Wait for timelock delay

# 3. Execute (deployer)
forge script script/wire/ExecuteAcceptAdmin.s.sol --rpc-url $RPC_URL --broadcast


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
