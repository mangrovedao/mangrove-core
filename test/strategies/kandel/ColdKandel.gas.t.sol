// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./abstract/CoreKandel.gas.t.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {Kandel} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";

contract ColdKandelGasTest is CoreKandelGasTest {
  function __setForkEnvironment__() internal virtual override {
    super.__setForkEnvironment__();

    base.transferResponse(TestToken.MethodResponse.MissingReturn);
    quote.approveResponse(TestToken.MethodResponse.MissingReturn);
  }

  function __deployKandel__(address deployer, address reserveId) internal override returns (GeometricKandel kdl_) {
    uint GASREQ = 128_000; // can be 77_000 when all offers are initialized.
    vm.prank(deployer);
    kdl_ = new Kandel({
      mgv: IMangrove($(mgv)),
      base: base,
      quote: quote,
      gasreq: GASREQ,
      gasprice: bufferedGasprice,
      reserveId: reserveId
    });
  }

  function setUp() public override {
    super.setUp();
    completeFill_ = 0.1 ether;
    partialFill_ = 0.05 ether;
  }
}
