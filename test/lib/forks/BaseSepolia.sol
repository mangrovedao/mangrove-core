// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract BaseSepoliaFork is GenericFork {
  constructor() {
    CHAIN_ID = 84532;
    NAME = "base sepolia";
    NETWORK = "base sepolia";
  }
}
