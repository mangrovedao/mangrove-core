// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract MegaETHTestnetFork is GenericFork {
  constructor() {
    CHAIN_ID = 6342;
    NAME = "megaeth-testnet"; // must be id used in foundry.toml for rpc_endpoint & etherscan
    NETWORK = "megaeth-testnet"; // must be network name inferred by ethers.js
  }
}

contract PinnedMegaETHTestnetFork is MegaETHTestnetFork {
  constructor(uint blockNumber) {
    BLOCK_NUMBER = blockNumber;
  }
}
