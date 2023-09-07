// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract PolygonFork is GenericFork {
  constructor() {
    CHAIN_ID = 137;
    NAME = "polygon"; // must be id used in foundry.toml for rpc_endpoint & etherscan
    NETWORK = "matic"; // must be network name inferred by ethers.js
  }
}

contract PinnedPolygonFork is PolygonFork {
  constructor(uint blockNumber) {
    BLOCK_NUMBER = blockNumber;
  }
}
