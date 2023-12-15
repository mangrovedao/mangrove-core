// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {GenericFork} from "./Generic.sol";

contract MumbaiFork is GenericFork {
  constructor() {
    CHAIN_ID = 80001;
    NAME = "mumbai";
    NETWORK = "maticmum";
  }
}
