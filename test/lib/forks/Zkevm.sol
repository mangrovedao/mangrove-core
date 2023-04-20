// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract Zkevm is GenericFork {
  constructor() {
    CHAIN_ID = 1101;
    NAME = "zkevm";
    NETWORK = "zkevm";
  }
}
