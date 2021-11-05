// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
import "../Toolbox/TestUtils.sol";

library TestMarketOrder {
  function run(
    TestUtils.Balances storage balances,
    mapping(uint => mapping(TestUtils.Info => uint)) storage offers,
    AbstractMangrove mgv,
    MakerDeployer makers,
    TestTaker taker,
    TestToken base,
    TestToken quote
  ) external {
    uint takerWants = 1.6 ether; // of B token
    uint takerGives = 2 ether; // of A token

    (uint takerGot, uint takerGave) = taker.marketOrder(takerWants, takerGives);

    // Checking Makers balances
    for (uint i = 2; i < 4; i++) {
      // offers 2 and 3 were consumed entirely
      TestEvents.eq(
        base.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceA[i] - offers[i][TestUtils.Info.makerGives],
        TestUtils.append(
          "Incorrect A balance for maker ",
          TestUtils.uint2str(i)
        )
      );
      TestEvents.eq(
        quote.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceB[i] + offers[i][TestUtils.Info.makerWants],
        TestUtils.append(
          "Incorrect B balance for maker ",
          TestUtils.uint2str(i)
        )
      );
    }
    uint leftMkrWants;
    {
      uint leftTkrWants = takerWants -
        (offers[2][TestUtils.Info.makerGives] +
          offers[3][TestUtils.Info.makerGives]);

      leftMkrWants =
        (offers[1][TestUtils.Info.makerWants] * leftTkrWants) /
        offers[1][TestUtils.Info.makerGives];

      TestEvents.eq(
        base.balanceOf(address(makers.getMaker(1))),
        balances.makersBalanceA[1] - leftTkrWants,
        "Incorrect A balance for maker 1"
      );
    }

    TestEvents.eq(
      quote.balanceOf(address(makers.getMaker(1))),
      balances.makersBalanceB[1] + leftMkrWants,
      "Incorrect B balance for maker 1"
    );

    // Checking taker balance
    TestEvents.eq(
      base.balanceOf(address(taker)), // actual
      balances.takerBalanceA +
        takerWants -
        TestUtils.getFee(mgv, address(base), address(quote), takerWants), // expected
      "incorrect taker A balance"
    );

    TestEvents.eq(
      takerGot,
      takerWants -
        TestUtils.getFee(mgv, address(base), address(quote), takerWants),
      "Incorrect declared takerGot"
    );

    uint shouldGive = (offers[3][TestUtils.Info.makerWants] +
      offers[2][TestUtils.Info.makerWants] +
      leftMkrWants);
    TestEvents.eq(
      quote.balanceOf(address(taker)), // actual
      balances.takerBalanceB - shouldGive, // expected
      "incorrect taker B balance"
    );

    TestEvents.eq(takerGave, shouldGive, "Incorrect declared takerGave");

    // Checking DEX Fee Balance
    TestEvents.eq(
      base.balanceOf(TestUtils.adminOf(mgv)), //actual
      balances.mgvBalanceFees +
        TestUtils.getFee(mgv, address(base), address(quote), takerWants), //expected
      "incorrect Mangrove balances"
    );
  }
}
