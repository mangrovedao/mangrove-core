// SPDX-License-Identifier:	AGPL-3.0

// those tests should be run with -vv so correct gas estimates are shown

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";

// In these tests, the testing contract is the market maker.
contract GasTest is MangroveTest, IMaker {
  TestTaker _tkr;
  uint[] pivots = new uint[](50);
  uint ofr;

  function setUp() public override {
    super.setUp();

    mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 100_000, 0, 0);

    _tkr = setupTaker($(base), $(quote), "Taker");
    deal($(quote), address(_tkr), 2 ether);
    _tkr.approveMgv(quote, 2 ether);

    deal($(base), $(this), 100 ether);

    /* set lock to 1 to avoid spurious 15k gas cost */
    ofr = mgv.newOffer($(base), $(quote), 0.1 ether, 0.1 ether, 100_000, 0, 0);

    // to test wrong pivots, posting at price wants = 0.1 eth + i wei, gives = 0.1 eth
    // will have i offers at the same price
    pivots[0] = 1;
    for (uint i; i < 50; i++) {
      // posting at price 0.1 ether + i wei
      uint wants = 0.1 ether + i;
      for (uint j; j < i; j++) {
        uint offerId = mgv.newOffer{value: 0.1 ether}($(base), $(quote), wants, 0.1 ether, 100_000, 0, 0);
        if (pivots[i] == 0) {
          pivots[i] = offerId;
        }
      }
    }
  }

  // preload stored vars for better gas estimate
  function getStored() internal view returns (AbstractMangrove, TestTaker, address, address, uint) {
    return (mgv, _tkr, $(base), $(quote), ofr);
  }

  function makerExecute(MgvLib.SingleOrder calldata) external pure returns (bytes32) {
    return ""; // silence unused function parameter
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) external {}

  function test_update_full_offer() public {
    (AbstractMangrove mgv,, address base, address quote, uint ofr_) = getStored();
    _tkr.take(ofr_, 0.1 ether);
    _gas();
    mgv.updateOffer(base, quote, 0.5 ether, 1 ether, 100_001, 0, 1, ofr_);
    gas_();
  }

  function update_min_move_n_offers(uint n) internal returns (uint) {
    (AbstractMangrove mgv,, address base, address quote, uint ofr_) = getStored();
    uint pivotId = pivots[n];
    _gas();
    mgv.updateOffer(base, quote, 0.1 ether + n, 0.1 ether, 100_000, 0, pivotId, ofr_);
    return gas_(true);
  }

  function test_update_move_k_offers_hot_start() public {
    _tkr.take(ofr, 0.1 ether); // taking offer to make hot storage around it.

    for (uint i; i < 50; i++) {
      console.log(i, ",", update_min_move_n_offers(i));
    }
  }

  function test_update_move_k_offers_cold_start() public {
    for (uint i; i < 50; i++) {
      console.log(i, ",", update_min_move_n_offers(i));
    }
  }

  function test_new_offer() public {
    (AbstractMangrove mgv,, address base, address quote,) = getStored();
    _gas();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 1);
    gas_();
  }

  function test_take_offer() public {
    (AbstractMangrove mgv, TestTaker tkr, address base, address quote,) = getStored();
    _gas();
    tkr.snipe(mgv, base, quote, 1, 1 ether, 1 ether, 100_000);
    gas_();
  }

  function test_partial_take_offer() public {
    (AbstractMangrove mgv, TestTaker tkr, address base, address quote,) = getStored();
    _gas();
    tkr.snipe(mgv, base, quote, 1, 0.5 ether, 0.5 ether, 100_000);
    gas_();
  }

  function test_market_order_1() public {
    (AbstractMangrove mgv, TestTaker tkr, address base, address quote,) = getStored();
    _gas();
    tkr.marketOrder(mgv, base, quote, 1 ether, 1 ether);
    gas_();
  }

  function test_market_order_8() public {
    (AbstractMangrove mgv, TestTaker tkr, address base, address quote,) = getStored();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    _gas();
    tkr.marketOrder(mgv, base, quote, 2 ether, 2 ether);
    gas_();
  }
}
