// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";

// In these tests, the testing contract is the market maker.
contract GasTest is MangroveTest, IMaker {
  TestTaker _tkr;

  function setUp() public override {
    super.setUp();

    mgv.newOffer($(base), $(quote), 1 ether, 1 ether, 100_000, 0, 0);

    _tkr = setupTaker($(base), $(quote), "Taker");
    deal($(quote), address(_tkr), 2 ether);
    _tkr.approveMgv(quote, 2 ether);

    deal($(base), $(this), 100 ether);

    /* set lock to 1 to avoid spurious 15k gas cost */
    uint ofr = mgv.newOffer(
      $(base),
      $(quote),
      0.1 ether,
      0.1 ether,
      100_000,
      0,
      0
    );
    _tkr.take(ofr, 0.1 ether);
  }

  // preload stored vars for better gas estimate
  function getStored()
    internal
    view
    returns (
      AbstractMangrove,
      TestTaker,
      address,
      address
    )
  {
    return (mgv, _tkr, $(base), $(quote));
  }

  function makerExecute(MgvLib.SingleOrder calldata)
    external
    pure
    returns (bytes32)
  {
    return ""; // silence unused function parameter
  }

  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external {}

  function test_update_min_move_0_offer() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    // uint g = gasleft();
    _gas();
    mgv.updateOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 1, 1);
    gas_();
    // console.log("Gas used", g - gasleft());
  }

  function test_update_full_offer() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    _gas();
    mgv.updateOffer(base, quote, 0.5 ether, 1 ether, 100_001, 0, 1, 1);
    gas_();
  }

  function update_min_move_3_offer_before() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    _gas();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    gas_();
  }

  function test_update_min_move_3_offer() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    _gas();
    mgv.updateOffer(base, quote, 1.0 ether, 0.1 ether, 100_00, 0, 1, 1);
    gas_();
  }

  function update_min_move_6_offer_before() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    _gas();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    gas_();
  }

  function test_update_min_move_6_offer() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    _gas();
    mgv.updateOffer(base, quote, 1.0 ether, 0.1 ether, 100_00, 0, 1, 1);
    gas_();
  }

  function test_new_offer() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    _gas();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 1);
    gas_();
  }

  function test_take_offer() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    _gas();
    tkr.snipe(mgv, base, quote, 1, 1 ether, 1 ether, 100_000);
    gas_();
  }

  function test_partial_take_offer() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    _gas();
    tkr.snipe(mgv, base, quote, 1, 0.5 ether, 0.5 ether, 100_000);
    gas_();
  }

  function test_market_order_1() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    _gas();
    tkr.marketOrder(mgv, base, quote, 1 ether, 1 ether);
    gas_();
  }

  function market_order_8_before() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    _gas();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    gas_();
  }

  function test_market_order_8() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    _gas();
    tkr.marketOrder(mgv, base, quote, 2 ether, 2 ether);
    gas_();
  }
}
