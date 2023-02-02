// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {CoreKandelTest, CoreKandel, IMangrove} from "./CoreKandel.t.sol";
import {AaveKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandel.sol";

contract AaveKandelTest is CoreKandelTest {
  function deployKandel() internal virtual override returns (CoreKandel kdl_) {
    vm.prank(maker);
    kdl_ = new AaveKandel({
      mgv: IMangrove($(mgv)), 
      base: weth,
      quote: usdc,
      gasreq: GASREQ,
      gasprice: bufferedGasprice,
      owner: maker
    });
  }
}
