// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;
pragma abicoder v2;
import "../Toolbox/TestUtils.sol";

library TestInsert {
  struct TestVars {
    AbstractMangrove mgv;
    MakerDeployer makers;
    TestTaker taker;
    TestToken base;
    TestToken quote;
  }

  function run(TestUtils.Balances storage balances, TestVars memory vars)
    public
    returns (uint[] memory)
  {
    // each maker publishes an offer
    uint[] memory offerOf = new uint[](vars.makers.length());
    offerOf[1] = vars.makers.getMaker(1).newOffer({ // offer 1
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 50_000,
      pivotId: 0
    });
    offerOf[2] = vars.makers.getMaker(2).newOffer({ // offer 2
      wants: 1 ether,
      gives: 0.8 ether,
      gasreq: 80_000,
      pivotId: 1
    });
    offerOf[3] = vars.makers.getMaker(3).newOffer({ // offer 3
      wants: 0.5 ether,
      gives: 1 ether,
      gasreq: 90_000,
      pivotId: 72
    });
    (P.Global.t cfg, ) = vars.mgv.config(
      address(vars.base),
      address(vars.quote)
    );
    offerOf[0] = vars.makers.getMaker(0).newOffer({ //failer offer 4
      wants: 20 ether,
      gives: 10 ether,
      gasreq: cfg.gasmax(),
      pivotId: 0
    });
    //TestUtils.printOfferBook(mgv);
    //Checking makers have correctly provisoned their offers
    for (uint i = 0; i < vars.makers.length(); i++) {
      uint gasreq_i = TestUtils.getOfferInfo(
        vars.mgv,
        address(vars.base),
        address(vars.quote),
        TestUtils.Info.gasreq,
        offerOf[i]
      );
      uint provision_i = TestUtils.getProvision(
        vars.mgv,
        address(vars.base),
        address(vars.quote),
        gasreq_i
      );
      TestEvents.eq(
        vars.mgv.balanceOf(address(vars.makers.getMaker(i))),
        balances.makersBalanceWei[i] - provision_i,
        TestUtils.append(
          "Incorrect wei balance for maker ",
          TestUtils.uint2str(i)
        )
      );
    }
    //Checking offers are correctly positioned (3 > 2 > 1 > 0)
    uint offerId = vars.mgv.best(address(vars.base), address(vars.quote));
    uint expected_maker = 3;
    while (offerId != 0) {
      (P.OfferStruct memory offer, P.OfferDetailStruct memory od) = vars
        .mgv
        .offerInfo(address(vars.base), address(vars.quote), offerId);
      TestEvents.eq(
        od.maker,
        address(vars.makers.getMaker(expected_maker)),
        TestUtils.append(
          "Incorrect maker address at offer ",
          TestUtils.uint2str(offerId)
        )
      );

      unchecked {
        expected_maker -= 1;
      }
      offerId = offer.next;
    }
    return offerOf;
  }
}
