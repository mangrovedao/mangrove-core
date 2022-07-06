// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;
pragma abicoder v2;

import "../Toolbox/TestUtils.sol";

library TestSnipe {
  struct Bag {
    uint orderAmount;
    uint snipedId;
    uint expectedFee;
  }

  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    AbstractMangrove mgv,
    MakerDeployer makers,
    TestTaker taker,
    TestToken base,
    TestToken quote
  )
    external
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
    expectedFee = TestUtils.getFee(
      mgv,
      address(base),
      address(quote),
      bag.orderAmount
    );
    TestMaker maker = makers.getMaker(bag.snipedId); // maker whose offer will be sniped

    //(uint init_mkr_wants, uint init_mkr_gives,,,,,)=mgv.getOfferInfo(2);
    //---------------SNIPE------------------//
    {
      bool takeSuccess;
      (takeSuccess, takerGot, takerGave, , ) = taker.takeWithInfo(
        bag.snipedId,
        bag.orderAmount
      );

      TestEvents.check(takeSuccess, "snipe should be a success");
    }
    TestEvents.eq(
      base.balanceOf(TestUtils.adminOf(mgv)), //actual
      balances.mgvBalanceFees + expectedFee, // expected
      "incorrect Mangrove A balance"
    );
    TestEvents.eq(
      base.balanceOf(address(taker)), // actual
      balances.takerBalanceA + bag.orderAmount - expectedFee, // expected
      "incorrect taker A balance"
    );
    TestEvents.eq(
      takerGot,
      bag.orderAmount - expectedFee, // expected
      "Incorrect takerGot"
    );
    {
      uint shouldGive = (bag.orderAmount *
        offers[bag.snipedId][TestUtils.Info.makerWants]) /
        offers[bag.snipedId][TestUtils.Info.makerGives];
      TestEvents.eq(
        quote.balanceOf(address(taker)),
        balances.takerBalanceB - shouldGive,
        "incorrect taker B balance"
      );
      TestEvents.eq(takerGave, shouldGive, "Incorrect takerGave");
    }
    TestEvents.eq(
      base.balanceOf(address(maker)),
      balances.makersBalanceA[bag.snipedId] - bag.orderAmount,
      "incorrect maker A balance"
    );
    TestEvents.eq(
      quote.balanceOf(address(maker)),
      balances.makersBalanceB[bag.snipedId] +
        (bag.orderAmount * offers[bag.snipedId][TestUtils.Info.makerWants]) /
        offers[bag.snipedId][TestUtils.Info.makerGives],
      "incorrect maker B balance"
    );
    // Testing residual offer
    (P.OfferStruct memory ofr, ) = mgv.offerInfo(
      address(base),
      address(quote),
      bag.snipedId
    );
    TestEvents.check(ofr.gives == 0, "Offer should not have a residual");
  }
}
