// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract BlastSepoliaFork is GenericFork {
  constructor() {
    CHAIN_ID = 168587773;
    NAME = "blast_sepolia";
    NETWORK = "blast-sepolia";
  }
}
