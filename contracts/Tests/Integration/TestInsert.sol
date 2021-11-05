// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
pragma abicoder v2;
import "../Toolbox/TestUtils.sol";

library TestInsert {
  function run(
    TestUtils.Balances storage balances,
    AbstractMangrove mgv,
    MakerDeployer makers,
    TestTaker, /* taker */ // silence warning about unused argument
    TestToken base,
    TestToken quote
  ) public returns (uint[] memory) {
    // each maker publishes an offer
    uint[] memory offerOf = new uint[](makers.length());
    offerOf[1] = makers.getMaker(1).newOffer({ // offer 1
      wants: 1 ether,
      gives: 0.5 ether,
      gasreq: 50_000,
      pivotId: 0
    });
    offerOf[2] = makers.getMaker(2).newOffer({ // offer 2
      wants: 1 ether,
      gives: 0.8 ether,
      gasreq: 80_000,
      pivotId: 1
    });
    offerOf[3] = makers.getMaker(3).newOffer({ // offer 3
      wants: 0.5 ether,
      gives: 1 ether,
      gasreq: 90_000,
      pivotId: 72
    });
    (bytes32 cfg, ) = mgv.config(address(base), address(quote));
    offerOf[0] = makers.getMaker(0).newOffer({ //failer offer 4
      wants: 20 ether,
      gives: 10 ether,
      gasreq: MP.global_unpack_gasmax(cfg),
      pivotId: 0
    });
    //TestUtils.printOfferBook(mgv);
    //Checking makers have correctly provisoned their offers
    for (uint i = 0; i < makers.length(); i++) {
      uint gasreq_i = TestUtils.getOfferInfo(
        mgv,
        address(base),
        address(quote),
        TestUtils.Info.gasreq,
        offerOf[i]
      );
      uint provision_i = TestUtils.getProvision(
        mgv,
        address(base),
        address(quote),
        gasreq_i
      );
      TestEvents.eq(
        mgv.balanceOf(address(makers.getMaker(i))),
        balances.makersBalanceWei[i] - provision_i,
        TestUtils.append(
          "Incorrect wei balance for maker ",
          TestUtils.uint2str(i)
        )
      );
    }
    //Checking offers are correctly positioned (3 > 2 > 1 > 0)
    uint offerId = mgv.best(address(base), address(quote));
    uint expected_maker = 3;
    while (offerId != 0) {
      (ML.Offer memory offer, ML.OfferDetail memory od) = mgv.offerInfo(
        address(base),
        address(quote),
        offerId
      );
      TestEvents.eq(
        od.maker,
        address(makers.getMaker(expected_maker)),
        TestUtils.append(
          "Incorrect maker address at offer ",
          TestUtils.uint2str(offerId)
        )
      );

      expected_maker -= 1;
      offerId = offer.next;
    }
    return offerOf;
  }
}
