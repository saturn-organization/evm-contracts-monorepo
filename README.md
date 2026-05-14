## USDat BNB Config -- TODO complete admin transfer
Deployer:              0x59Ebb7143dDDd7b045dE7B0bd0F99446143F1624
Predicted token proxy: 0x0Bb150DFa86EA5d7742F07FEfCD8E8edA81D64eF
Predicted OFT proxy:   0xA347D34AA2c94784ab355B7c3c3304469Cd56524
Token impl:  0x65458213Bb2398f968cA1760b806956966B9adAc
Token proxy: 0x0Bb150DFa86EA5d7742F07FEfCD8E8edA81D64eF
AdapterOFT impl:    0x9827C419eb1ef2798276842124a373Dc369754Ab
AdapterOFT proxy:   0xA347D34AA2c94784ab355B7c3c3304469Cd56524

## sUSDat BNB Config -- TODO complete admin transfer
Deployer:              0x59Ebb7143dDDd7b045dE7B0bd0F99446143F1624
Predicted token proxy: 0x9cd57D3685E6868caCaA8BDCaAf52CBdEBf4fA25
Predicted OFT proxy:   0xecD684Ec8416d17512172166724E5736c95b47cc
Token impl:  0x5885f15E70BD20bF2FBa9382B03aeDB2608B3Ad2
Token proxy: 0x9cd57D3685E6868caCaA8BDCaAf52CBdEBf4fA25
AdapterOFT impl:    0x97974dAc5C287E03B12Da9410FebC0CcaBB033B1
AdapterOFT proxy:   0xecD684Ec8416d17512172166724E5736c95b47cc

## USDat Ethereum Config -- TODO complete admin transfer
Deployer:         0x59Ebb7143dDDd7b045dE7B0bd0F99446143F1624
Predicted proxy:  0xA347D34AA2c94784ab355B7c3c3304469Cd56524
Implementation:  0x9eD7580F54207266972C1562813243A7dF575765
AdapterProxy:           0xA347D34AA2c94784ab355B7c3c3304469Cd56524

## sUSDat Ethereum Config -- TODO complete admin transfer
Deployer:         0x59Ebb7143dDDd7b045dE7B0bd0F99446143F1624
Predicted proxy:  0xecD684Ec8416d17512172166724E5736c95b47cc
Implementation:  0x106E999f46C9F564FFD6E5b7feDCBAF23d3Eec8c
AdapterProxy:           0xecD684Ec8416d17512172166724E5736c95b47cc


# 1. SetLibraries (deployer)
forge script script/wire/SetLibraries.s.sol \
  --rpc-url $RPC_URL --broadcast

# 2. SetSendConfig (deployer)
forge script script/wire/SetSendConfig.s.sol \
  --rpc-url $RPC_URL --broadcast

# 3. SetReceiveConfig (deployer)
forge script script/wire/SetReceiveConfig.s.sol \
  --rpc-url $RPC_URL --broadcast

# 4. SetEnforcedOptions (deployer)
forge script script/wire/SetEnforcedOptions.s.sol \
  --rpc-url $RPC_URL --broadcast

# 5. SetRateLimits (multisig via Fireblocks)

forge script script/wire/SetRateLimits.s.sol \
  --rpc-url $RPC_URL --broadcast

fireblocks-json-rpc --http -- forge script script/wire/SetRateLimits.s.sol \
  --sender $RATE_LIMITER_MANAGER_ADDRESS --slow --broadcast --unlocked --rpc-url {}

# 6. SetPeers (deployer) — only after the OTHER chain (ethereum) is deployed
forge script script/wire/SetPeers.s.sol \
  --rpc-url $RPC_URL --broadcast


# 7. Propose (multisig via Fireblocks)
fireblocks-json-rpc --http -- forge script script/wire/ProposeAcceptAdmin.s.sol \
  --sender $ADMIN_TIMELOCK_PROPOSER --slow --broadcast --unlocked --rpc-url {}

# 8. Wait for timelock delay

# 9. Execute (deployer)
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
