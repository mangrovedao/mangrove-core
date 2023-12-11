// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";
import {TestMoriartyMaker} from "@mgv/test/lib/agents/TestMoriartyMaker.sol";

contract ScenariiTest is MangroveTest {
  TestTaker taker;
  MakerDeployer makers;
  Balances balances;
  uint constant testFee = 250;
  uint[] offerOf;

  mapping(uint => mapping(Info => uint)) offers;

  //receive() external payable {}

  function saveOffers() internal {
    uint offerId = mgv.best(olKey);
    while (offerId != 0) {
      (OfferUnpacked memory offer, OfferDetailUnpacked memory offerDetail) = reader.offerInfo(olKey, offerId);
      console.log("Saving Info for offer id", offerId);
      console.log("  wants", offer.wants());
      console.log("  gives", offer.gives);
      offers[offerId][Info.makerWants] = offer.wants();
      offers[offerId][Info.makerGives] = offer.gives;
      offers[offerId][Info.gasreq] = offerDetail.gasreq;
      offerId = reader.nextOfferIdById(olKey, offerId);
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
      mgvBalanceWei: $(mgv).balance,
      mgvBalanceBase: base.balanceOf(address(mgv)),
      takerBalanceA: base.balanceOf(address(taker)),
      takerBalanceB: quote.balanceOf(address(taker)),
      takerBalanceWei: mgv.balanceOf(address(taker)),
      makersBalanceA: balA,
      makersBalanceB: balB,
      makersBalanceWei: balWei
    });
  }

  function setUp() public override {
    super.setUp();

    mgv.setFee(olKey, testFee);

    makers = setupMakerDeployer(olKey);
    makers.deploy(4);
    for (uint i = 1; i < makers.length(); i++) {
      vm.label(address(makers.getMaker(i)), string.concat("maker-", vm.toString(i)));
    }
    vm.label(address(makers.getMaker(0)), "failer");
    taker = setupTaker(olKey, "taker");

    deal(address(makers), 80 ether);
    makers.dispatch();

    for (uint i = 0; i < makers.length(); i++) {
      TestMaker maker = makers.getMaker(i);
      maker.provisionMgv(10 ether);
      deal($(base), address(maker), 5 ether);
    }

    deal($(quote), address(taker), 5 ether);
    taker.approveMgv(quote, 5 ether);
    taker.approveMgv(base, 50 ether);
    saveBalances();
  }

  /* **************** TEST ROUTINES ************* */

  function collectFailingOffer(uint failingOfferId) internal {
    // executing failing offer
    try taker.clean(failingOfferId, 0.5 ether) {
      // failingOffer should have been removed from Mgv
      {
        assertTrue(!mgv.offers(olKey, failingOfferId).isLive(), "Failing offer should have been removed from Mgv");
      }
      uint provision = reader.getProvision(olKey, offers[failingOfferId][Info.gasreq], 0);
      uint returned = mgv.balanceOf(address(makers.getMaker(0))) - balances.makersBalanceWei[0];
      assertEq(
        $(mgv).balance,
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
    _offerOf[1] = makers.getMaker(1).newOfferByVolume({ // offer 1
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 50_000
    });
    _offerOf[2] = makers.getMaker(2).newOfferByVolume({ // offer 2
      wants: 1 ether,
      gives: 0.8 ether,
      gasreq: 80_000
    });
    _offerOf[3] = makers.getMaker(3).newOfferByVolume({ // offer 3
      wants: 0.5 ether,
      gives: 1 ether,
      gasreq: 90_000
    });
    (Global cfg,) = mgv.config(olKey);
    _offerOf[0] = makers.getMaker(0).newOfferByVolume({ //failer offer 4
      wants: 20 ether,
      gives: 10 ether,
      gasreq: cfg.gasmax()
    });
    //Checking makers have correctly provisoned their offers
    for (uint i = 0; i < makers.length(); i++) {
      uint gasreq_i = mgv.offerDetails(olKey, _offerOf[i]).gasreq();
      uint provision_i = reader.getProvision(olKey, gasreq_i, 0);
      assertEq(
        mgv.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceWei[i] - provision_i,
        string.concat("Incorrect wei balance for maker ", vm.toString(i))
      );
    }
    //Checking offers are correctly positioned (3 > 2 > 1 > 0)
    uint offerId = mgv.best(olKey);
    uint expected_maker = 3;
    while (offerId != 0) {
      (, OfferDetailUnpacked memory od) = reader.offerInfo(olKey, offerId);
      assertEq(
        od.maker,
        address(makers.getMaker(expected_maker)),
        string.concat("Incorrect maker address at offer ", vm.toString(offerId))
      );

      unchecked {
        expected_maker -= 1;
      }
      offerId = reader.nextOfferIdById(olKey, offerId);
    }
    return _offerOf;
  }

  function mo() internal {
    uint takerWants = 1.5 ether; // of B token
    uint takerGives = 2 ether; // of A token

    (uint takerGot, uint takerGave) = taker.marketOrder(takerWants, takerGives);

    // Checking Makers balances
    for (uint i = 2; i < 4; i++) {
      // offers 2 and 3 were consumed entirely
      assertEq(
        base.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceA[i] - offers[i][Info.makerGives],
        string.concat("Incorrect A balance for maker ", vm.toString(i))
      );
      assertEq(
        quote.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceB[i] + offers[i][Info.makerWants],
        string.concat("Incorrect B balance for maker ", vm.toString(i))
      );
    }
    uint leftMkrWants;
    {
      uint leftTkrWants = takerWants - (offers[2][Info.makerGives] + offers[3][Info.makerGives]);

      leftMkrWants = (offers[1][Info.makerWants] * leftTkrWants) / offers[1][Info.makerGives];

      assertEq(
        base.balanceOf(address(makers.getMaker(1))),
        balances.makersBalanceA[1] - leftTkrWants,
        "Incorrect A balance for maker 1"
      );
    }

    assertApproxEqRel(
      quote.balanceOf(address(makers.getMaker(1))),
      balances.makersBalanceB[1] + leftMkrWants,
      relError(10),
      "Incorrect B balance for maker 1"
    );

    // Checking taker balance
    assertEq(
      base.balanceOf(address(taker)), // actual
      balances.takerBalanceA + reader.minusFee(olKey, takerWants), // expected
      "incorrect taker A balance"
    );

    assertEq(takerGot, reader.minusFee(olKey, takerWants), "Incorrect declared takerGot");

    uint shouldGive = (offers[3][Info.makerWants] + offers[2][Info.makerWants] + leftMkrWants);
    assertApproxEqRel(
      quote.balanceOf(address(taker)), // actual
      balances.takerBalanceB - shouldGive, // expected
      relError(10),
      "incorrect taker B balance"
    );

    assertApproxEqRel(takerGave, shouldGive, relError(10), "Incorrect declared takerGave");

    // Checking DEX Fee Balance
    assertEq(
      base.balanceOf(address(mgv)), //actual
      balances.mgvBalanceBase + reader.getFee(olKey, takerWants), //expected
      "incorrect Mangrove balances"
    );
  }

  struct Bag {
    uint orderAmount;
    uint snipedId;
    uint expectedFee;
  }
}

contract DeepCollectTest is MangroveTest {
  TestTaker tkr;
  TestMoriartyMaker evil;

  //receive() external payable {}

  function setUp() public override {
    options.density96X32 = 10 << 32;
    super.setUp();
    tkr = setupTaker(olKey, "taker");

    deal($(quote), address(tkr), 5 ether);
    tkr.approveMgv(quote, 20 ether);
    tkr.approveMgv(base, 20 ether);

    evil = new TestMoriartyMaker(mgv, olKey);
    vm.label(address(evil), "Moriarty");
    deal(address(evil), 20 ether);
    evil.provisionMgv(10 ether);
    deal($(base), address(evil), 5 ether);
    evil.approveMgv(base, 5 ether);

    evil.newOfferByVolume({wants: 1 ether, gives: 0.5 ether, gasreq: 100000});
  }

  function test_market_with_failures() public {
    moWithFailures();
  }

  function moWithFailures() internal {
    tkr.marketOrderWithFail({wants: 10 ether, gives: 30 ether});
    assertTrue(reader.isEmptyOB(olKey), "Order book should be empty");
  }
}
