// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract ArbitrumFork is GenericFork {
  constructor() {
    CHAIN_ID = 42161;
    NAME = "arbitrum"; // must be id used in foundry.toml for rpc_endpoint & etherscan
    NETWORK = "arbitrum"; // must be network name inferred by ethers.js
  }
}

contract PinnedArbitrumFork is ArbitrumFork {
  constructor(uint blockNumber) {
    BLOCK_NUMBER = blockNumber;
  }
}
