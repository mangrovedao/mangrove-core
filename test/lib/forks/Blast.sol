// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract BlastFork is GenericFork {
  constructor() {
    CHAIN_ID = 81457;
    NAME = "blast";
    NETWORK = "blast";
  }
}
