## StableCoin

- **RelativeStability** : Anchored or pegged -> $1.00

  - Chainlink Price feed
  - Set a function to exchange ETC and BTC -> $$$

- **Stability Mechanism** : Algorithmic (Decentralized)
  - People can only mint the stable coin with enough collateral (coded)
- **Collateral** : Exogenous (Crypto)
  - ETH (wETH)
  - BTC (wBTC)

## Contract Layout

- version
- imports
- interfaces, libraries and contracts
- errors
- type declarations
- state variables
- events
- modifiers
- functions

## Layout of functions

- constructor
- receive function (if exists)
- fallback function (if exists)
- external
- public
- internal
- private
- view and pure functions

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
