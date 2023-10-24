// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {OfferGasBaseBaseTest} from "@mgv/test/lib/gas/OfferGasBaseBase.t.sol";

contract OfferGasBaseTest_Generic_A_B is OfferGasBaseBaseTest {
  function setUp() public override {
    super.setUpGeneric();
    this.setUpTokens(options.base.symbol, options.quote.symbol);
  }
}

contract OfferGasBaseGasreqMeasuringTest_Generic_A_B is OfferGasBaseBaseTest {
  function setUpOptions() internal virtual override {
    super.setUpOptions();
    options.measureGasusedMangrove = true;
  }

  function setUp() public override {
    super.setUpGeneric();
    this.setUpTokens(options.base.symbol, options.quote.symbol);
  }
}

contract OfferGasBaseTest_Polygon_WETH_DAI is OfferGasBaseBaseTest {
  function setUp() public override {
    super.setUpPolygon();
    this.setUpTokens("WETH", "DAI");
  }
}
