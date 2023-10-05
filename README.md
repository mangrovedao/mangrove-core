[![CI](https://github.com/mangrovedao/mangrove-core/actions/workflows/node.js.yml/badge.svg)](https://github.com/mangrovedao/mangrove-core/actions/workflows/node.js.yml)

This package contains the Solidity implementation of Mangrove as well as deployment scripts and example Solidity offer logics.

# Documentation

If you are looking for the Mangrove developer documentation, the site to go to is [docs.mangrove.exchange](https://docs.mangrove.exchange).

# Use as a foundry dependency

Just `forge install mangrovedao/mangrove-core`.

⚠️ You will not get the usual remapping `mangrove-core/=lib/mangrove-core/src/` (because forge's remapping generation heuristic sees the `preprocessing/lib/` directory and decides to remap to the parent dir). Instead, you will get:

```
@mgv/src/=lib/mangrove-core/src/
@mgv/lib/=lib/mangrove-core/lib/
@mgv/test/=lib/mangrove-core/test/
@mgv/script/=lib/mangrove-core/script/
```

Use this likely-unique prefix even internally so projects that depend on Mangrove don't mess with Mangrove's internal dependencies.

# Installing prerequisites

For Linux or macOS everything should work out of the box, if you are using Windows, then we recommend installing everything from within WSL2 and expect some quirks.

1. [Node.js](https://nodejs.org/en/) 14.14+, we recommend installation through [nvm](https://github.com/nvm-sh/nvm#installing-and-updating), e.g.:

   ```shell
   $ curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
   # Reopen shell
   $ nvm install --lts
   ```

2. [Yarn 2](https://yarnpkg.com/getting-started/install), with Node.js >= 16.10:

   ```shell
   $ corepack enable
   ```

3. [Foundry](https://book.getfoundry.sh/getting-started/installation.html):

   ```shell
   $ curl -L https://foundry.paradigm.xyz | bash
   # Reopen shell
   $ foundryup
   ```

4. Clone the git repo with sub-modules

   ```shell
   $ git clone --recurse-submodules https://github.com/mangrovedao/mangrove-core.git
   # Or set the global git config once: git config --global submodule.recurse true
   ```

# Usage

The following sections describe the most common use cases in this repo.

## Initial setup

After cloning the repo, you should run `yarn install` in the root folder.

```shell
$ yarn install
```

Then you need to setup the local environment (still in the root folder). Start by copying the test file provided:

```shell
$ cp .env.example .env
```

And then open `.env` in your favorite editor and put in settings for, e.g., node urls, for instance pointing to [Alchemy](https://www.alchemy.com/). (The discussion around setting up an [environment for testing out the strat library on a local chain](https://docs.mangrove.exchange/strat-lib/getting-started/preparation#local-chain) on [docs.mangrove.exchange](https://docs.mangrove.exchange) might be helpful.)

## Build

To build, run

```shell
$ yarn build
```

## Address Configuration

When writing scripts that uses the `Generic.sol` script, you can control what addresses are read.

By default, it will try and look into the `{projectRoot}/mgvConfig.json` file, in order to find the paths to all the addresses folders you want to use. The file should look like this:

```json
{
  "addresses_paths": ["addresses/"],
  "deployment_addresses_path": "addresses/"
}
```

The `deployment_addresses_path` is the path to the folder where the addresses are written to when deploying. The `addresses_paths` is an array of paths to folders where the addresses are read from. The paths are relative to the project root.

If you want to read addresses from other folders, then you can add paths to the json file. If you do not want to change the `mgvConfig.json` file, but still want to read some extra addresses. Then you you can set `MGV_ADDRESSES_PATHS` to the addresses paths that should be read from. And if you don't want to read the `mgvConfig.json` addresses at all, then you can set `MGV_READ_ADDRESSES_PATHS` to false. The `MGV_ADDRESSES_PATHS` variable has same structure as the `mgvConfig.json`. Here is an example:

```shell
export MGV_ADDRESSES_PATHS='{ "addresses_paths": ["/addresses/"] }'
export MGV_READ_ADDRESSES_PATHS=false
```

In this example we disable the default paths and set the path to `/addresses/`. Remember the path is relative to the project root. This way you can easily read addresses from multiple sources.

When adding paths, then you have to remember to add the path in the `foundry.toml` file as well, in order for foundry to be able to read from that path.

## Tests

To run all tests in the package, just run `yarn test`.

This package contains a comprehensive test suite for Mangrove, implemented in Solidity using [Foundry](https://book.getfoundry.sh/index.html).

The tests are located in [./test](./test).

Refer to the documentation of [Foundry](https://book.getfoundry.sh/index.html) for details on how tests are structured and options for running it.

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

# Deploying on Mangrove

Mangrove uses `forge script`

[`forge script <scriptName>`](https://book.getfoundry.sh/reference/forge/forge-script) executes an arbitrary smart contract function locally. Then, any CALLs executed therein and preceded by the cheatcode [`vm.broadcast()`](https://book.getfoundry.sh/cheatcodes/broadcast) can be broadcast to a remote node by reading a forge-generated `run-*.json` field.

## Generating Mangrove address files

The log of transactions generated by `forge script` gets written to `broadcast/<scriptName>/<chainId>/run-latest.json`. It is an array of low-level transactions info with some additions like newly created contract names.

Mangrove needs to:

- Name its contract (multiple instances of the same contract may be deployed)
- Ignore script names (different scripts are used for different networks)
- Have all its deployed contracts in one place

To do the above, Mangrove adds a layer to `forge script` deployment.

- Deployment scripts should inherit the `Deployer` contract.
- You should call `outputDeployment()` at the end of your scripts.
  - When `outputDeployment()` gets called, a file with all known deployed contracts are written to `addresses/deployed.backup/<network>-latest.json`
- You should set `WRITE_DEPLOY=true` when running scripts that you want to broadcast.
  - When `WRITE_DEPLOY=true`, the contract set is also written to `addresses/deployed/<network>.json`.

(Note that for mumbai, `network=maticmum`)

## Foundry keywords for rpc and verification

We use foundry's [`[rpc_endpoints]`](https://book.getfoundry.sh/cheatcodes/rpc#examples) and [`[etherscan]`](https://book.getfoundry.sh/reference/config/etherscan?highlight=etherscan#etherscan) config sections. If the same key exists in both, you can drop the `--etherscan-api-key` from the commandline arguments. For instance if `mumbai` is defined in both sections, you can say `forge script --fork-url mumbai ... --verify` and any deployed contracts will get verified through etherscan using the `mumbai` API key of the `[etherscan]` section.

(Note: in this context, etherscan can mean "polygonscan" or any block explorer)

## Chain-dependent broadcast with private keys in .env

The `vm.broadcast()` cheatcode implicitly selects a sender for the broadcast transactions: either the default sender, or the address associated to the `--private-key` given in the CLI, or to `--mnemonic` information, etc.

It is tiring to always add `--private-key 0x..` to scripts, especially since the key may be different for each network. The `Deployer` contract has a `broadcast()` function that reads the `<NAME>_PRIVATE_KEY` var off the environment, where `NAME` is the name of the chain you're talking to.

- You should have vars such as `MUMBAI_PRIVATE_KEY` , `POLYGON_PRIVATE_KEY` in your `.env` file. You can use [.env.example](.env.example) as a template.
- You should use `broadcast()` instead of `vm.broadcast()` in scripts. The deployer contract will look for the correct private key, and fallback to the CLI-provided key if none was found.

(Note that for Mumbai, `name=”mumbai”`)

# Generate documentation

The Mangrove Solidity files contain documentation that can be extracted to a nicely formatted and navigable HTML file by running `yarn doc` which will generate a `doc/MgvDoc.html`.
