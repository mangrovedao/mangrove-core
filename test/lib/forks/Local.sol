// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

/* Local fork for when the context expects a Fork contract but we are on a local, fresh chain */
contract LocalFork is GenericFork {
  constructor() {
    CHAIN_ID = 31337;
    NAME = "local";
    NETWORK = "local";
  }
}
