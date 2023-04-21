// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./abstract/CoreKandel.gas.t.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {Kandel} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";

contract ColdKandelGasTest is CoreKandelGasTest {
  function setUp() public override {
    super.setUp();
    completeFill_ = 0.1 ether;
    partialFill_ = 0.05 ether;
  }
}
