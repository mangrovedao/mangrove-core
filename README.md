# Mangrove development repo

## How to install

```
npm install
```

## How to run all tests

```
npm run test
```

#### What you can do

- Use Hardhat's `console.log` in contracts for debugging; those logs survive transaction revert. More in [Hardhat's documentation](https://hardhat.org/hardhat-network/#console-log). Example:

```
string memory s = "Hello";
uint n = 31;
console.log("Message %s number %d",s,d);
```

- Run test for a specific contract and show all events of non-reverted transactions. Example:

```
npx hardhat test-solidity --show-events
```

- Run test for `permit` function, which needs js instrumentation (cannot do reasonably it in pure solidity)

```
npx hardhat run scripts/permit.js
```

- See a Solidity stack trace on reverts

#### More on tests

To test a contract `C`, create a contract `C_Test`. You will probably use the contents of `contracts/Toolbox/TestEvents.sol`. To see how it all works, see [`test_solidity.js`](lib/test_solidity.js).

[Hardhat](https://hardhat.org) is a development framework for Ethereum. It includes an [EVM interpreter](https://hardhat.org/hardhat-network/) with special hooks for

- interpreting `console.log`-type statements
- displaying Solidity stack traces

It has an extendable task system; this repo adds a `test-solidity` task. Run `npx hardhat help test-solidity` for available options. The task itself is defined in [hardhat.config.js](./hardhat.config.js).

## Generate documentation

After running `npm install`, run `npm run doc` to generate a `doc/MgvDoc.html` file.
