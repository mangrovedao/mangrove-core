// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "../abstract/GeometricKandel.gas.t.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {Kandel, LongKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";

contract ColdLongKandelGasTest is GeometricKandelGasTest {
  function setUp() public override {
    super.setUp();
    completeFill_ = 0.1 ether;
    partialFill_ = 0.05 ether;
    // funding Kandel
    LongKandel kdl_ = LongKandel($(kdl));
    uint pendingBase = uint(-kdl.pending(Ask));
    uint pendingQuote = uint(-kdl.pending(Bid));
    deal($(base), maker, pendingBase);
    deal($(quote), maker, pendingQuote);
    expectFrom($(kdl));
    emit Credit(base, pendingBase);
    expectFrom($(kdl));
    emit Credit(quote, pendingQuote);
    vm.prank(maker);
    kdl_.depositFunds(pendingBase, pendingQuote);
  }
}
