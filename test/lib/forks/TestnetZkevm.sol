// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract TestnetZkevmFork is GenericFork {
  constructor() {
    CHAIN_ID = 1442;
    NAME = "testnet_zkevm";
    NETWORK = "testnet_zkevm";
  }
}
