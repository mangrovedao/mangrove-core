// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract GoerliFork is GenericFork {
  constructor() {
    CHAIN_ID = 5;
    NAME = "goerli";
    NETWORK = "goerli";
  }
}
