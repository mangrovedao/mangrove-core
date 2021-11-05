// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma abicoder v2;

//import "../Mangrove.sol";
//import "../MgvLib.sol";
import "hardhat/console.sol";

import "../Toolbox/TestUtils.sol";
// import "../Toolbox/Display.sol";

import "../Agents/TestToken.sol";
import "../Agents/TestMaker.sol";
import "../Agents/TestMoriartyMaker.sol";
import "../Agents/MakerDeployer.sol";
import "../Agents/TestTaker.sol";
import "../Agents/TestDelegateTaker.sol";
import "../Agents/OfferManager.sol";

import "./TestCancelOffer.sol";
import "./TestCollectFailingOffer.sol";
import "./TestInsert.sol";
import "./TestSnipe.sol";
import "./TestFailingMarketOrder.sol";
import "./TestMarketOrder.sol";

// Pretest libraries are for deploying large contracts independently.
// Otherwise bytecode can be too large. See EIP 170 for more on size limit:
// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-170.md

contract Scenarii_Test {
  AbstractMangrove mgv;
  TestTaker taker;
  MakerDeployer makers;
  TestToken base;
  TestToken quote;
  TestUtils.Balances balances;
  uint[] offerOf;

  mapping(uint => mapping(TestUtils.Info => uint)) offers;

  receive() external payable {}

  function saveOffers() internal {
    uint offerId = mgv.best(address(base), address(quote));
    while (offerId != 0) {
      (ML.Offer memory offer, ML.OfferDetail memory offerDetail) = mgv
        .offerInfo(address(base), address(quote), offerId);
      offers[offerId][TestUtils.Info.makerWants] = offer.wants;
      offers[offerId][TestUtils.Info.makerGives] = offer.gives;
      offers[offerId][TestUtils.Info.gasreq] = offerDetail.gasreq;
      offerId = offer.next;
    }
  }

  function saveBalances() internal {
    uint[] memory balA = new uint[](makers.length());
    uint[] memory balB = new uint[](makers.length());
    uint[] memory balWei = new uint[](makers.length());
    for (uint i = 0; i < makers.length(); i++) {
      balA[i] = base.balanceOf(address(makers.getMaker(i)));
      balB[i] = quote.balanceOf(address(makers.getMaker(i)));
      balWei[i] = mgv.balanceOf(address(makers.getMaker(i)));
    }
    balances = TestUtils.Balances({
      mgvBalanceWei: address(mgv).balance,
      mgvBalanceFees: base.balanceOf(TestUtils.adminOf(mgv)),
      takerBalanceA: base.balanceOf(address(taker)),
      takerBalanceB: quote.balanceOf(address(taker)),
      takerBalanceWei: mgv.balanceOf(address(taker)),
      makersBalanceA: balA,
      makersBalanceB: balB,
      makersBalanceWei: balWei
    });
  }

  function a_deployToken_beforeAll() public {
    //console.log("IN BEFORE ALL");
    base = TokenSetup.setup("A", "$A");
    quote = TokenSetup.setup("B", "$B");

    TestUtils.not0x(address(base));
    TestUtils.not0x(address(quote));

    Display.register(address(0), "NULL_ADDRESS");
    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Mgv_Test");
    Display.register(address(base), "base");
    Display.register(address(quote), "quote");
  }

  function b_deployMgv_beforeAll() public {
    mgv = MgvSetup.setup(base, quote);
    Display.register(address(mgv), "Mgv");
    TestUtils.not0x(address(mgv));
    mgv.setFee(address(base), address(quote), 300);
  }

  function c_deployMakersTaker_beforeAll() public {
    makers = MakerDeployerSetup.setup(mgv, address(base), address(quote));
    makers.deploy(4);
    for (uint i = 1; i < makers.length(); i++) {
      Display.register(
        address(makers.getMaker(i)),
        TestUtils.append("maker-", TestUtils.uint2str(i))
      );
    }
    Display.register(address(makers.getMaker(0)), "failer");
    taker = TakerSetup.setup(mgv, address(base), address(quote));
    Display.register(address(taker), "taker");
  }

  function d_provisionAll_beforeAll() public {
    // low level tranfer because makers needs gas to transfer to each maker
    (bool success, ) = address(makers).call{gas: gasleft(), value: 80 ether}(
      ""
    ); // msg.value is distributed evenly amongst makers
    require(success, "maker transfer");

    for (uint i = 0; i < makers.length(); i++) {
      TestMaker maker = makers.getMaker(i);
      maker.provisionMgv(10 ether);
      base.mint(address(maker), 5 ether);
    }

    quote.mint(address(taker), 5 ether);
    taker.approveMgv(quote, 5 ether);
    taker.approveMgv(base, 50 ether);
    saveBalances();
  }

  function snipe_insert_and_fail_test() public {
    offerOf = TestInsert.run(balances, mgv, makers, taker, base, quote);
    //TestUtils.printOfferBook(mgv);
    TestUtils.logOfferBook(mgv, address(base), address(quote), 4);

    //TestEvents.logString("=== Snipe test ===", 0);
    saveBalances();
    saveOffers();
    TestSnipe.run(balances, offers, mgv, makers, taker, base, quote);
    TestUtils.logOfferBook(mgv, address(base), address(quote), 4);

    // restore offer that was deleted after partial fill, minus taken amount
    makers.getMaker(2).updateOffer(
      1 ether - 0.375 ether,
      0.8 ether - 0.3 ether,
      80_000,
      0,
      2
    );

    TestUtils.logOfferBook(mgv, address(base), address(quote), 4);

    //TestEvents.logString("=== Market order test ===", 0);
    saveBalances();
    saveOffers();
    TestMarketOrder.run(balances, offers, mgv, makers, taker, base, quote);
    TestUtils.logOfferBook(mgv, address(base), address(quote), 4);

    //TestEvents.logString("=== Failling offer test ===", 0);
    saveBalances();
    saveOffers();
    TestCollectFailingOffer.run(
      balances,
      offers,
      mgv,
      offerOf[0],
      makers,
      taker,
      base,
      quote
    );
    TestUtils.logOfferBook(mgv, address(base), address(quote), 4);
    saveBalances();
    saveOffers();
  }
}

contract DeepCollect_Test {
  TestToken base;
  TestToken quote;
  AbstractMangrove mgv;
  TestTaker tkr;
  TestMoriartyMaker evil;

  receive() external payable {}

  function a_beforeAll() public {
    base = TokenSetup.setup("A", "$A");
    quote = TokenSetup.setup("B", "$B");
    mgv = MgvSetup.setup(base, quote);
    tkr = TakerSetup.setup(mgv, address(base), address(quote));

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "DeepCollect_Tester");
    Display.register(address(base), "$A");
    Display.register(address(quote), "$B");
    Display.register(address(mgv), "mgv");
    Display.register(address(tkr), "taker");

    quote.mint(address(tkr), 5 ether);
    tkr.approveMgv(quote, 20 ether);
    tkr.approveMgv(base, 20 ether);

    evil = new TestMoriartyMaker(mgv, address(base), address(quote));
    Display.register(address(evil), "Moriarty");

    (bool success, ) = address(evil).call{gas: gasleft(), value: 20 ether}("");
    require(success, "maker transfer");
    evil.provisionMgv(10 ether);
    base.mint(address(evil), 5 ether);
    evil.approveMgv(base, 5 ether);

    evil.newOffer({
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 100000,
      pivotId: 0
    });
  }

  function market_with_failures_test() public {
    //TestEvents.logString("=== DeepCollect test ===", 0);
    TestFailingMarketOrder.moWithFailures(
      mgv,
      address(base),
      address(quote),
      tkr
    );
  }
}
