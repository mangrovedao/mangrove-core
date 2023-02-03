// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {CoreKandelTest, CoreKandel, GeometricKandel, IMangrove, HasIndexedOffers} from "./CoreKandel.t.sol";
import {AaveKandel, AavePooledRouter} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandel.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";

contract AaveKandelTest is CoreKandelTest {
  PinnedPolygonFork fork;

  function __setForkEnvironment__() internal override {
    fork = new PinnedPolygonFork();
    fork.setUp();
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH"));
    quote = TestToken(fork.get("USDC"));
    setupMarket(base, quote);
  }

  function __deployKandel__(address deployer) internal virtual override returns (GeometricKandel) {
    // 474_000 theoretical in mock up of router
    // 218_000 observed in tests of router
    uint router_gasreq = 318 * 1000;
    uint kandel_gasreq = 128 * 1000;
    AavePooledRouter router = new AavePooledRouter(fork.get("Aave"), router_gasreq);
    HasIndexedOffers.MangroveWithBaseQuote memory mangroveWithBaseQuote =
      HasIndexedOffers.MangroveWithBaseQuote({mgv: IMangrove($(mgv)), base: base, quote: quote});

    AaveKandel aaveKandel = new AaveKandel({
      mangroveWithBaseQuote: mangroveWithBaseQuote,
      gasreq: kandel_gasreq,
      gasprice: 0,
      owner: deployer
    });

    router.bind(address(aaveKandel));
    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20
    aaveKandel.initialize(router);
    aaveKandel.setAdmin(deployer);
    assertEq(aaveKandel.offerGasreq(), kandel_gasreq + router_gasreq, "Incorrect gasreq");
    return aaveKandel;
  }
}
