// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest, MgvReader, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {GenericFork} from "mgv_test/lib/forks/Generic.sol";
import {OLKey} from "mgv_src/MgvLib.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {GasTestBaseStored} from "./GasTestBase.t.sol";

///@notice base class for creating tests of gasreq for contracts. Compare results to implementors of OfferGasBaseBaseTest.
abstract contract OfferGasReqBaseTest is MangroveTest, GasTestBaseStored {
  TestTaker internal taker;
  GenericFork internal fork;

  function getStored() internal view override returns (IMangrove, TestTaker, OLKey memory, uint) {
    return (mgv, taker, olKey, 0);
  }

  function setUpGeneric() public virtual {
    super.setUp();
    fork = new GenericFork();
    fork.set(options.base.symbol, $(base));
    fork.set(options.quote.symbol, $(quote));
    description = "generic - gasreq";
  }

  function setUpPolygon() public virtual {
    super.setUp();
    fork = new PinnedPolygonFork(39880000);
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 200_000;
    options.defaultFee = 30;
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    description = "polygon - gasreq";
  }

  function setUpTokens(string memory baseToken, string memory quoteToken) public virtual {
    description = string.concat(description, " - ", baseToken, "/", quoteToken);
    address baseAddress = fork.get(baseToken);
    address quoteAddress = fork.get(quoteToken);
    base = TestToken(baseAddress);
    quote = TestToken(quoteAddress);
    olKey = OLKey($(base), $(quote), options.defaultTickSpacing);
    lo = OLKey($(quote), $(base), options.defaultTickSpacing);
    setupMarket(olKey);
    setupMarket(lo);

    taker = setupTaker(olKey, "Taker");
    deal($(base), address(taker), 200000 ether);
    deal($(quote), address(taker), 200000 ether);
    taker.approveMgv(quote, 200000 ether);
    taker.approveMgv(base, 200000 ether);
  }
}
