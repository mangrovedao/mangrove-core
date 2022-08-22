This package contains the Solidity implementation of Mangrove as well as deployment scripts and example Solidity offer logics.

# Installation

First, clone the repo and install the prerequisites for the monorepo described in the root [README.md](../../README.md).

Next, run the following commands:

```shell
$ cd <Mangrove monorepo>/packages/mangrove-solidity
$ yarn install   # Sets up the Mangrove monorepo and install dependencies
$ yarn build     # Compiles Mangrove and offer logics
```

After the initial installation, it is sufficient to run `yarn build` after updating the clone - this will also run `yarn install`.

# Foundry and its use in this package

This package relies heavily on the [Foundry](https://book.getfoundry.sh/) development framework for Ethereum. It includes an [EVM interpreter](https://github.com/gakonst/ethers-rs) with special hooks for

- interpreting `console.log`-type statements
- displaying Solidity stack traces on reverts.

For example, you can use `console.log` in contracts for debugging; those logs survive transaction revert. More in [Foundry's](https://book.getfoundry.sh/reference/forge-std/console-log?highlight=console#console-logging). Example:

```
string memory s = "Hello";
uint n = 31;
console.log("Message %s number %d",s,d);
```

# Tests

To run all tests in the package, just run `yarn test`.

To run specific tests or test suites, see the instructions in the following sectins.

## How to run Solidity tests for Mangrove

This package contains a comprehensive test suite for Mangrove, implemented in Solidity using [foundry](https://book.getfoundry.sh/index.html).

This test suite can be run with:

```bash
$ yarn test:solidity
```

The tests are located in [./contracts/Tests](./contracts/Tests).

Refer to the documentation of [foundry](https://book.getfoundry.sh/index.html) for details on how tests are structured and options for running it.

## How to run offer logic tests

Tests for the example offer logics are implemented in JavaScript and are located here: [./test](./test).

The tests run a on a local fork of either Ethereum or Polygon mainnet. This ensures that the offer logics use the actual mainnet versions of the DeFi bricks they use, e.g. Aave and Compound.

In order to run the tests, you must provide URLs for mainnet endpoints in the following environment variables:

```bash
# URL for an Ethereum endpoint
ETHEREUM_NODE_URL=https://eth-mainnet.alchemyapi.io/v2/<API key>
# URL for a Polygon endpoint
POLYGON_NODE_URL=https://polygon-mainnet.g.alchemy.com/v2/<API key>
```

You can set up free accounts with any endpoint provider, e.g. Infura or Alchemy.

For convencience, you can store the environment variables in `./.env.test.local`. You can use [.env.local.example](.env.local.example) as a template.

The full test suite can be run with:

```bash
# Run offer logic tests against fork of Ethereum mainnet:
$ yarn test:ethereum-mainnet

# Run offer logic tests against fork of Polygon mainnet:
$ yarn test:polygon-mainnet
```

To run specific test suites, use the `testSuites` package script:

```bash
 yarn run testSuites -n/--network <network> [testSuite1 ...]
 # Example running the basic test suite (test-basic.js) on a Polygon mainnet fork:
 yarn run testSuites -n polygon basic
```

# Deployment

## FIXME

No deployment story with foundry yet -- but foundry has the features, we just need to write the deployments and the tooling around it.

# Generate documentation

The Mangrove Solidity files contain documentation that can be extracted to a nicely formatted and navigable HTML file by running `yarn doc` which will generate a `doc/MgvDoc.html`.

# Configuration

This package uses hierarchical configurations via [node-config](https://github.com/lorenwest/node-config). The main configuration is in [./config/default.js](./config/default.js) and the other .js files in the same directory specify environment/stage specific overrides. Please refer to the documentation for node-config for details on how the configuration hierarchy is resolved.

It is possible to override parts of the configuration with environment variables. This is controlled by [./config/custom-environment-variables.json](./config/custom-environment-variables.json). The structure of this file mirrors the configuration structure but with names of environment variables in the places where these can override a part of the configuration.

For more information, please refer to the node-config's documentation of this feature: https://github.com/lorenwest/node-config/wiki/Environment-Variables#custom-environment-variables .
