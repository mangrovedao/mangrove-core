// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {CoreKandelTest, CoreKandel, IMangrove, HasIndexedOffers} from "./CoreKandel.t.sol";
import {AaveKandel, AavePooledRouter} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandel.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";

contract AaveKandelTest is CoreKandelTest {
  function deployKandel() internal virtual override returns (CoreKandel kdl_) {
    HasIndexedOffers.MangroveWithBaseQuote memory mangroveWithBaseQuote =
      HasIndexedOffers.MangroveWithBaseQuote({mgv: IMangrove($(mgv)), base: weth, quote: usdc});
    vm.prank(maker);
    kdl_ = new AaveKandel({
      mangroveWithBaseQuote: mangroveWithBaseQuote,
      gasreq: GASREQ,
      gasprice: bufferedGasprice,
      owner: maker
    });

    router.bind(address(aaveKdl));
    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20
    aaveKdl.initialize(router);
    return aaveKdl;
  }
}
