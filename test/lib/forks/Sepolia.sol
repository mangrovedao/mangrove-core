// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract SepoliaFork is GenericFork {
  constructor() {
    CHAIN_ID = 11155111;
    NAME = "sepolia";
    NETWORK = "sepolia";
  }
}
