// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;
import {GenericFork} from "./Generic.sol";

contract PolygonFork is GenericFork {
  constructor() {
    CHAIN_ID = 137;
    NAME = "polygon";
    NETWORK = "polygon";
  }
}

contract PinnedPolygonFork is PolygonFork {
  constructor() {
    BLOCK_NUMBER = 26416000;
  }
}