// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./abstract/CoreKandel.gas.t.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {AaveKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandel.sol";
import {AavePooledRouter} from "mgv_src/strategies/routers/integrations/AavePooledRouter.sol";

contract AaveKandelGasTest is CoreKandelGasTest {
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
    AavePooledRouter router = new AavePooledRouter(fork.get("AaveAddressProvider"), ROUTER_GASREQ);
    router.setAaveManager(msg.sender);
    router.bind(address(kdl_));
    AaveKandel(payable(kdl_)).initialize(router);
    vm.stopPrank();
  }

  function setUp() public override {
    super.setUp();
    completeFill_ = 0.1 ether;
    partialFill_ = 0.08 ether;
  }
}
