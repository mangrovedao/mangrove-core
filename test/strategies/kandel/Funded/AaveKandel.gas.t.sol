// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "../abstract/GeometricKandel.gas.t.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {AaveKandel, FundedKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandel.sol";
import {AavePooledRouter} from "mgv_src/strategies/routers/integrations/AavePooledRouter.sol";

contract AaveKandelGasTest is GeometricKandelGasTest {
  function __deployKandel__(address deployer, address reserveId) internal override returns (GeometricKandel kdl_) {
    uint GASREQ = 160_000;
    uint ROUTER_GASREQ = 280_000;
    vm.startPrank(deployer);
    kdl_ = new AaveKandel({
      mgv: IMangrove($(mgv)),
      base: base,
      quote: quote,
      gasreq: GASREQ,
      gasprice: bufferedGasprice,
      reserveId: reserveId
    });
    AavePooledRouter router = new AavePooledRouter(fork.get("Aave"), ROUTER_GASREQ);
    router.setAaveManager(msg.sender);
    router.bind(address(kdl_));
    AaveKandel(payable(kdl_)).initialize(router);
    vm.stopPrank();
  }

  function setUp() public override {
    super.setUp();
    completeFill_ = 0.1 ether;
    partialFill_ = 0.08 ether;
    // funding Kandel

    FundedKandel kdl_ = FundedKandel($(kdl));
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
