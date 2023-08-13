// SPDX-License-Identifier:	AGPL-3.0

// those tests should be run with -vv so correct gas estimates are shown

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";

// In these tests, the testing contract is the market maker.
contract GasTest is MangroveTest, IMaker {
  TestTaker _tkr;
  uint ofr;

  function setUp() public override {
    super.setUp();

    mgv.newOfferByVolume(ol, 1 ether, 1 ether, 100_000, 0);

    _tkr = setupTaker(ol, "Taker");
    deal($(quote), address(_tkr), 2 ether);
    _tkr.approveMgv(quote, 2 ether);

    deal($(base), $(this), 100 ether);

    /* set lock to 1 to avoid spurious 15k gas cost */
    ofr = mgv.newOfferByVolume(ol, 0.1 ether, 0.1 ether, 100_000, 0);

    // will have i offers at the same price
    for (uint i; i < 50; i++) {
      // posting at price 0.1 ether + i wei
      uint wants = 0.1 ether + i;
      for (uint j; j < i; j++) {
        mgv.newOfferByVolume{value: 0.1 ether}(ol, wants, 0.1 ether, 100_000, 0);
      }
    }
  }

  // preload stored vars for better gas estimate
  function getStored() internal view returns (AbstractMangrove, TestTaker, OL memory, uint) {
    return (mgv, _tkr, ol, ofr);
  }

  function makerExecute(MgvLib.SingleOrder calldata) external pure returns (bytes32) {
    return ""; // silence unused function parameter
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) external {}

  function test_update_full_offer() public {
    (AbstractMangrove mgv,, OL memory ol, uint ofr_) = getStored();
    _tkr.take(ofr_, 0.1 ether);
    _gas();
    mgv.updateOfferByVolume(ol, 0.5 ether, 1 ether, 100_001, 0, ofr_);
    gas_();
  }

  function update_min_move_n_offers(uint n) internal returns (uint) {
    (AbstractMangrove mgv,, OL memory ol, uint ofr_) = getStored();
    _gas();
    mgv.updateOfferByVolume(ol, 0.1 ether + n, 0.1 ether, 100_000, 0, ofr_);
    return gas_(true);
  }

  // function test_update_move_k_offers_hot_start() public {
  //   _tkr.take(ofr, 0.1 ether); // taking offer to make hot storage around it.

  //   for (uint i; i < 50; i++) {
  //     console.log(i, ",", update_min_move_n_offers(i));
  //   }
  // }

  // function test_update_move_k_offers_cold_start() public {
  //   for (uint i; i < 50; i++) {
  //     console.log(i, ",", update_min_move_n_offers(i));
  //   }
  // }

  function test_new_offer() public {
    (AbstractMangrove mgv,, OL memory ol,) = getStored();
    _gas();
    mgv.newOfferByVolume(ol, 0.1 ether, 0.1 ether, 100_000, 0);
    gas_();
  }

  function test_take_offer() public {
    (AbstractMangrove mgv, TestTaker tkr, OL memory ol,) = getStored();
    _gas();
    tkr.snipeByVolume(mgv, ol, 1, 1 ether, 100_000);
    gas_();
  }

  function test_partial_take_offer() public {
    (AbstractMangrove mgv, TestTaker tkr, OL memory ol,) = getStored();
    _gas();
    tkr.snipeByVolume(mgv, ol, 1, 0.5 ether, 100_000);
    gas_();
  }

  function test_market_order_1() public {
    (AbstractMangrove mgv, TestTaker tkr, OL memory ol,) = getStored();
    _gas();
    tkr.marketOrder(mgv, ol, 1 ether, 1 ether);
    gas_();
  }

  function test_market_order_8() public {
    (AbstractMangrove mgv, TestTaker tkr, OL memory ol,) = getStored();
    mgv.newOfferByVolume(ol, 0.1 ether, 0.1 ether, 100_000, 0);
    mgv.newOfferByVolume(ol, 0.1 ether, 0.1 ether, 100_000, 0);
    mgv.newOfferByVolume(ol, 0.1 ether, 0.1 ether, 100_000, 0);
    mgv.newOfferByVolume(ol, 0.1 ether, 0.1 ether, 100_000, 0);
    mgv.newOfferByVolume(ol, 0.1 ether, 0.1 ether, 100_000, 0);
    mgv.newOfferByVolume(ol, 0.1 ether, 0.1 ether, 100_000, 0);
    mgv.newOfferByVolume(ol, 0.1 ether, 0.1 ether, 100_000, 0);
    _gas();
    tkr.marketOrder(mgv, ol, 2 ether, 2 ether);
    gas_();
  }

  function test_retract_cached() public {
    (AbstractMangrove mgv,, OL memory ol,) = getStored();
    mgv.newOfferByVolume(ol, 1 ether, 1 ether, 1_000_000, 0);
    uint offer = mgv.newOfferByVolume(ol, 1.0001 ether, 1 ether, 1_000_000, 0);
    _gas();
    mgv.retractOffer(ol, offer, false);
    gas_();
  }

  function test_retract_not_cached() public {
    (AbstractMangrove mgv,, OL memory ol,) = getStored();
    mgv.newOfferByVolume(ol, 1 ether, 1 ether, 1_000_000, 0);
    uint offer = mgv.newOfferByVolume(ol, 1000 ether, 1 ether, 1_000_000, 0);
    _gas();
    mgv.retractOffer(ol, offer, false);
    gas_();
  }

  function test_retract_best_new_is_not_cached() public {
    (AbstractMangrove mgv,, OL memory ol,) = getStored();
    mgv.newOfferByVolume(ol, 1 ether, 1 ether, 1_000_000, 0);
    uint offer = mgv.newOfferByVolume(ol, 1 ether, 1000 ether, 1_000_000, 0);
    _gas();
    mgv.retractOffer(ol, offer, false);
    gas_();
  }

  function test_retract_best_new_is_cached() public {
    (AbstractMangrove mgv,, OL memory ol,) = getStored();
    mgv.newOfferByVolume(ol, 1 ether, 1 ether, 1_000_000, 0);
    uint offer = mgv.newOfferByVolume(ol, 1 ether, 1.0001 ether, 1_000_000, 0);
    _gas();
    mgv.retractOffer(ol, offer, false);
    gas_();
  }

  // add best_cached
}
