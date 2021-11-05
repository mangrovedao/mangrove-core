// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
pragma abicoder v2;

import "../Toolbox/TestUtils.sol";

library TestSnipe {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    AbstractMangrove mgv,
    MakerDeployer makers,
    TestTaker taker,
    TestToken base,
    TestToken quote
  ) external {
    uint orderAmount = 0.3 ether;
    uint snipedId = 2;
    TestMaker maker = makers.getMaker(snipedId); // maker whose offer will be sniped

    //(uint init_mkr_wants, uint init_mkr_gives,,,,,)=mgv.getOfferInfo(2);
    //---------------SNIPE------------------//
    uint takerGave;
    uint takerGot;
    {
      bool takeSuccess;
      (takeSuccess, takerGot, takerGave) = taker.takeWithInfo(
        snipedId,
        orderAmount
      );

      TestEvents.check(takeSuccess, "snipe should be a success");
    }
    TestEvents.eq(
      base.balanceOf(TestUtils.adminOf(mgv)), //actual
      balances.mgvBalanceFees +
        TestUtils.getFee(mgv, address(base), address(quote), orderAmount), //expected
      "incorrect Mangrove A balance"
    );
    TestEvents.eq(
      base.balanceOf(address(taker)), // actual
      balances.takerBalanceA +
        orderAmount -
        TestUtils.getFee(mgv, address(base), address(quote), orderAmount), // expected
      "incorrect taker A balance"
    );
    TestEvents.eq(
      takerGot,
      orderAmount -
        TestUtils.getFee(mgv, address(base), address(quote), orderAmount),
      "Incorrect takerGot"
    );
    {
      uint shouldGive = (orderAmount *
        offers[snipedId][TestUtils.Info.makerWants]) /
        offers[snipedId][TestUtils.Info.makerGives];
      TestEvents.eq(
        quote.balanceOf(address(taker)),
        balances.takerBalanceB - shouldGive,
        "incorrect taker B balance"
      );
      TestEvents.eq(takerGave, shouldGive, "Incorrect takerGave");
    }
    TestEvents.eq(
      base.balanceOf(address(maker)),
      balances.makersBalanceA[snipedId] - orderAmount,
      "incorrect maker A balance"
    );
    TestEvents.eq(
      quote.balanceOf(address(maker)),
      balances.makersBalanceB[snipedId] +
        (orderAmount * offers[snipedId][TestUtils.Info.makerWants]) /
        offers[snipedId][TestUtils.Info.makerGives],
      "incorrect maker B balance"
    );
    // Testing residual offer
    (ML.Offer memory ofr, ) = mgv.offerInfo(
      address(base),
      address(quote),
      snipedId
    );
    TestEvents.check(ofr.gives == 0, "Offer should not have a residual");
  }
}
