// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../AbstractMangrove.sol";
import "../MgvLib.sol";
import "hardhat/console.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/TestTaker.sol";
import "./Agents/MM1.sol";

contract MM1T_Test {
  receive() external payable {}

  AbstractMangrove mgv;
  TestTaker tkr;
  TestMaker mkr;
  MM1 mm1;
  address base;
  address quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = MgvSetup.setup(baseT, quoteT);
    tkr = TakerSetup.setup(mgv, base, quote);
    mkr = MakerSetup.setup(mgv, base, quote);
    mm1 = new MM1{value: 2 ether}(mgv, base, quote);

    address(tkr).transfer(10 ether);
    address(mkr).transfer(10 ether);

    //bool noRevert;
    //(noRevert, ) = address(mgv).call{value: 10 ether}("");

    mkr.provisionMgv(5 ether);

    baseT.mint(address(tkr), 10 ether);
    baseT.mint(address(mkr), 10 ether);
    baseT.mint(address(mm1), 2 ether);

    quoteT.mint(address(tkr), 10 ether);
    quoteT.mint(address(mkr), 10 ether);
    quoteT.mint(address(mm1), 2 ether);

    mm1.refresh();

    //baseT.approve(address(mgv), 1 ether);
    //quoteT.approve(address(mgv), 1 ether);
    tkr.approveMgv(quoteT, 1000 ether);
    tkr.approveMgv(baseT, 1000 ether);
    mkr.approveMgv(quoteT, 1000 ether);
    mkr.approveMgv(baseT, 1000 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(mgv), "mgv");
    Display.register(address(tkr), "taker[$A,$B]");
    //Display.register(address(dual_mkr), "maker[$B,$A]");
    Display.register(address(mkr), "maker");
    Display.register(address(mm1), "MM1");
  }

  function ta_test() public {
    TestUtils.logOfferBook(mgv, base, quote, 3);
    TestUtils.logOfferBook(mgv, quote, base, 3);
    (MgvLib.Offer memory ofr, ) = mgv.offerInfo(base, quote, 1);
    console.log("prev", ofr.prev);
    mkr.newOffer(base, quote, 0.05 ether, 0.1 ether, 200_000, 0);
    mkr.newOffer(quote, base, 0.05 ether, 0.05 ether, 200_000, 0);
    TestUtils.logOfferBook(mgv, base, quote, 3);
    TestUtils.logOfferBook(mgv, quote, base, 3);

    tkr.marketOrder(0.01 ether, 0.01 ether);
    TestUtils.logOfferBook(mgv, base, quote, 3);
    TestUtils.logOfferBook(mgv, quote, base, 3);

    mkr.newOffer(base, quote, 0.05 ether, 0.1 ether, 200_000, 0);
    mm1.refresh();
    TestUtils.logOfferBook(mgv, base, quote, 3);
    TestUtils.logOfferBook(mgv, quote, base, 3);
  }
}
