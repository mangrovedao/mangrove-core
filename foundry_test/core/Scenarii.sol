// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";

contract Scenarii_Test is MangroveTest {
  AbstractMangrove mgv;
  TestTaker taker;
  MakerDeployer makers;
  TestToken base;
  TestToken quote;
  Balances balances;
  uint constant testFee = 300;
  uint[] offerOf;

  mapping(uint => mapping(Info => uint)) offers;

  //receive() external payable {}

  function saveOffers() internal {
    uint offerId = mgv.best(address(base), address(quote));
    while (offerId != 0) {
      (P.OfferStruct memory offer, P.OfferDetailStruct memory offerDetail) = mgv
        .offerInfo(address(base), address(quote), offerId);
      offers[offerId][Info.makerWants] = offer.wants;
      offers[offerId][Info.makerGives] = offer.gives;
      offers[offerId][Info.gasreq] = offerDetail.gasreq;
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
    balances = Balances({
      mgvBalanceWei: address(mgv).balance,
      mgvBalanceFees: base.balanceOf(adminOf(mgv)),
      takerBalanceA: base.balanceOf(address(taker)),
      takerBalanceB: quote.balanceOf(address(taker)),
      takerBalanceWei: mgv.balanceOf(address(taker)),
      makersBalanceA: balA,
      makersBalanceB: balB,
      makersBalanceWei: balWei
    });
  }

  function setUp() public {
    //console.log("IN BEFORE ALL");
    base = setupToken("A", "$A");
    quote = setupToken("B", "$B");

    not0x(address(base));
    not0x(address(quote));

    vm.label(address(0), "NULL_ADDRESS");
    vm.label(msg.sender, "Test Runner");
    vm.label(address(this), "Mgv_Test");
    vm.label(address(base), "base");
    vm.label(address(quote), "quote");

    mgv = setupMangrove(base, quote);
    vm.label(address(mgv), "Mgv");
    not0x(address(mgv));
    mgv.setFee(address(base), address(quote), testFee);

    makers = setupMakerDeployer(mgv, address(base), address(quote));
    makers.deploy(4);
    for (uint i = 1; i < makers.length(); i++) {
      vm.label(address(makers.getMaker(i)), append("maker-", uint2str(i)));
    }
    vm.label(address(makers.getMaker(0)), "failer");
    taker = setupTaker(mgv, address(base), address(quote));
    vm.label(address(taker), "taker");

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

  function test_snipe_insert_and_fail() public {
    offerOf = insert();
    //printOfferBook(mgv);
    logOfferBook(mgv, address(base), address(quote), 4);

    saveBalances();
    saveOffers();
    expectFrom(address(mgv));
    emit OrderStart();
    expectFrom(address(mgv));
    emit OrderComplete(
      address(base),
      address(quote),
      address(taker),
      0.291 ether, // should not be hardcoded
      0.375 ether, // should not be hardcoded
      0,
      0.009 ether // should not be hardcoded
    );

    snipe();
    logOfferBook(mgv, address(base), address(quote), 4);

    // restore offer that was deleted after partial fill, minus taken amount
    makers.getMaker(2).updateOffer(
      1 ether - 0.375 ether,
      0.8 ether - 0.3 ether,
      80_000,
      0,
      2
    );

    logOfferBook(mgv, address(base), address(quote), 4);

    saveBalances();
    saveOffers();
    mo();
    logOfferBook(mgv, address(base), address(quote), 4);

    saveBalances();
    saveOffers();
    collectFailingOffer(offerOf[0]);
    logOfferBook(mgv, address(base), address(quote), 4);
    saveBalances();
    saveOffers();
  }

  /* **************** TEST ROUTINES ************* */

  function collectFailingOffer(uint failingOfferId) internal {
    // executing failing offer
    try taker.takeWithInfo(failingOfferId, 0.5 ether) returns (
      bool success,
      uint takerGot,
      uint takerGave,
      uint,
      uint
    ) {
      // take should return false not throw
      assertTrue(!success, "Failer should fail");
      assertEq(takerGot, 0, "Failed offer should declare 0 takerGot");
      assertEq(takerGave, 0, "Failed offer should declare 0 takerGave");
      // failingOffer should have been removed from Mgv
      {
        assertTrue(
          !mgv.isLive(
            mgv.offers(address(base), address(quote), failingOfferId)
          ),
          "Failing offer should have been removed from Mgv"
        );
      }
      uint provision = getProvision(
        mgv,
        address(base),
        address(quote),
        offers[failingOfferId][Info.gasreq]
      );
      uint returned = mgv.balanceOf(address(makers.getMaker(0))) -
        balances.makersBalanceWei[0];
      assertEq(
        address(mgv).balance,
        balances.mgvBalanceWei - (provision - returned),
        "Mangrove has not send the correct amount to taker"
      );
    } catch (bytes memory errorMsg) {
      string memory err = abi.decode(errorMsg, (string));
      fail(err);
    }
  }

  function insert() public returns (uint[] memory) {
    // each maker publishes an offer
    uint[] memory _offerOf = new uint[](makers.length());
    _offerOf[1] = makers.getMaker(1).newOffer({ // offer 1
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 50_000,
      pivotId: 0
    });
    _offerOf[2] = makers.getMaker(2).newOffer({ // offer 2
      wants: 1 ether,
      gives: 0.8 ether,
      gasreq: 80_000,
      pivotId: 1
    });
    _offerOf[3] = makers.getMaker(3).newOffer({ // offer 3
      wants: 0.5 ether,
      gives: 1 ether,
      gasreq: 90_000,
      pivotId: 72
    });
    (P.Global.t cfg, ) = mgv.config(address(base), address(quote));
    _offerOf[0] = makers.getMaker(0).newOffer({ //failer offer 4
      wants: 20 ether,
      gives: 10 ether,
      gasreq: cfg.gasmax(),
      pivotId: 0
    });
    //Checking makers have correctly provisoned their offers
    for (uint i = 0; i < makers.length(); i++) {
      uint gasreq_i = getOfferInfo(
        mgv,
        address(base),
        address(quote),
        Info.gasreq,
        _offerOf[i]
      );
      uint provision_i = getProvision(
        mgv,
        address(base),
        address(quote),
        gasreq_i
      );
      assertEq(
        mgv.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceWei[i] - provision_i,
        append("Incorrect wei balance for maker ", uint2str(i))
      );
    }
    //Checking offers are correctly positioned (3 > 2 > 1 > 0)
    uint offerId = mgv.best(address(base), address(quote));
    uint expected_maker = 3;
    while (offerId != 0) {
      (P.OfferStruct memory offer, P.OfferDetailStruct memory od) = mgv
        .offerInfo(address(base), address(quote), offerId);
      assertEq(
        od.maker,
        address(makers.getMaker(expected_maker)),
        append("Incorrect maker address at offer ", uint2str(offerId))
      );

      unchecked {
        expected_maker -= 1;
      }
      offerId = offer.next;
    }
    return _offerOf;
  }

  function mo() internal {
    uint takerWants = 1.6 ether; // of B token
    uint takerGives = 2 ether; // of A token

    (uint takerGot, uint takerGave) = taker.marketOrder(takerWants, takerGives);

    // Checking Makers balances
    for (uint i = 2; i < 4; i++) {
      // offers 2 and 3 were consumed entirely
      assertEq(
        base.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceA[i] - offers[i][Info.makerGives],
        append("Incorrect A balance for maker ", uint2str(i))
      );
      assertEq(
        quote.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceB[i] + offers[i][Info.makerWants],
        append("Incorrect B balance for maker ", uint2str(i))
      );
    }
    uint leftMkrWants;
    {
      uint leftTkrWants = takerWants -
        (offers[2][Info.makerGives] + offers[3][Info.makerGives]);

      leftMkrWants =
        (offers[1][Info.makerWants] * leftTkrWants) /
        offers[1][Info.makerGives];

      assertEq(
        base.balanceOf(address(makers.getMaker(1))),
        balances.makersBalanceA[1] - leftTkrWants,
        "Incorrect A balance for maker 1"
      );
    }

    assertEq(
      quote.balanceOf(address(makers.getMaker(1))),
      balances.makersBalanceB[1] + leftMkrWants,
      "Incorrect B balance for maker 1"
    );

    // Checking taker balance
    assertEq(
      base.balanceOf(address(taker)), // actual
      balances.takerBalanceA +
        takerWants -
        getFee(mgv, address(base), address(quote), takerWants), // expected
      "incorrect taker A balance"
    );

    assertEq(
      takerGot,
      takerWants - getFee(mgv, address(base), address(quote), takerWants),
      "Incorrect declared takerGot"
    );

    uint shouldGive = (offers[3][Info.makerWants] +
      offers[2][Info.makerWants] +
      leftMkrWants);
    assertEq(
      quote.balanceOf(address(taker)), // actual
      balances.takerBalanceB - shouldGive, // expected
      "incorrect taker B balance"
    );

    assertEq(takerGave, shouldGive, "Incorrect declared takerGave");

    // Checking DEX Fee Balance
    assertEq(
      base.balanceOf(adminOf(mgv)), //actual
      balances.mgvBalanceFees +
        getFee(mgv, address(base), address(quote), takerWants), //expected
      "incorrect Mangrove balances"
    );
  }

  struct Bag {
    uint orderAmount;
    uint snipedId;
    uint expectedFee;
  }

  function snipe()
    internal
    returns (
      uint takerGot,
      uint takerGave,
      uint expectedFee
    )
  {
    Bag memory bag;
    bag.orderAmount = 0.3 ether;
    bag.snipedId = 2;
    // uint orderAmount = 0.3 ether;
    // uint snipedId = 2;
    expectedFee = getFee(mgv, address(base), address(quote), bag.orderAmount);
    TestMaker maker = makers.getMaker(bag.snipedId); // maker whose offer will be sniped

    //(uint init_mkr_wants, uint init_mkr_gives,,,,,)=mgv.getOfferInfo(2);
    //---------------SNIPE------------------//
    {
      bool takeSuccess;
      (takeSuccess, takerGot, takerGave, , ) = taker.takeWithInfo(
        bag.snipedId,
        bag.orderAmount
      );

      assertTrue(takeSuccess, "snipe should be a success");
    }
    assertEq(
      base.balanceOf(adminOf(mgv)), //actual
      balances.mgvBalanceFees + expectedFee, // expected
      "incorrect Mangrove A balance"
    );
    assertEq(
      base.balanceOf(address(taker)), // actual
      balances.takerBalanceA + bag.orderAmount - expectedFee, // expected
      "incorrect taker A balance"
    );
    assertEq(
      takerGot,
      bag.orderAmount - expectedFee, // expected
      "Incorrect takerGot"
    );
    {
      uint shouldGive = (bag.orderAmount *
        offers[bag.snipedId][Info.makerWants]) /
        offers[bag.snipedId][Info.makerGives];
      assertEq(
        quote.balanceOf(address(taker)),
        balances.takerBalanceB - shouldGive,
        "incorrect taker B balance"
      );
      assertEq(takerGave, shouldGive, "Incorrect takerGave");
    }
    assertEq(
      base.balanceOf(address(maker)),
      balances.makersBalanceA[bag.snipedId] - bag.orderAmount,
      "incorrect maker A balance"
    );
    assertEq(
      quote.balanceOf(address(maker)),
      balances.makersBalanceB[bag.snipedId] +
        (bag.orderAmount * offers[bag.snipedId][Info.makerWants]) /
        offers[bag.snipedId][Info.makerGives],
      "incorrect maker B balance"
    );
    // Testing residual offer
    (P.OfferStruct memory ofr, ) = mgv.offerInfo(
      address(base),
      address(quote),
      bag.snipedId
    );
    assertTrue(ofr.gives == 0, "Offer should not have a residual");
  }
}

contract DeepCollect_Test is MangroveTest {
  TestToken base;
  TestToken quote;
  AbstractMangrove mgv;
  TestTaker tkr;
  TestMoriartyMaker evil;

  //receive() external payable {}

  function setUp() public {
    base = setupToken("A", "$A");
    quote = setupToken("B", "$B");
    mgv = setupMangrove(base, quote);
    tkr = setupTaker(mgv, address(base), address(quote));

    vm.label(msg.sender, "Test Runner");
    vm.label(address(this), "DeepCollect_Tester");
    vm.label(address(base), "$A");
    vm.label(address(quote), "$B");
    vm.label(address(mgv), "mgv");
    vm.label(address(tkr), "taker");

    quote.mint(address(tkr), 5 ether);
    tkr.approveMgv(quote, 20 ether);
    tkr.approveMgv(base, 20 ether);

    evil = new TestMoriartyMaker(mgv, address(base), address(quote));
    vm.label(address(evil), "Moriarty");

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

  function test_market_with_failures() public {
    moWithFailures();
  }

  function moWithFailures() internal {
    tkr.marketOrderWithFail({wants: 10 ether, gives: 30 ether});
    assertTrue(
      isEmptyOB(mgv, address(base), address(quote)),
      "Offer book should be empty"
    );
  }
}
