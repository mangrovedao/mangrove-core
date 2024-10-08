// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract BaseFork is GenericFork {
  constructor() {
    CHAIN_ID = 8453;
    NAME = "base";
    NETWORK = "base";
  }
}
