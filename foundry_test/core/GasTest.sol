// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/tools/MangroveTest.sol";

// In these tests, the testing contract is the market maker.
contract GasTest is MangroveTest, IMaker {
  //receive() external payable {}

  AbstractMangrove _mgv;
  TestTaker _tkr;
  address _base;
  address _quote;

  function setUp() public {
    TestToken baseT = setupToken("A", "$A");
    TestToken quoteT = setupToken("B", "$B");
    _base = address(baseT);
    _quote = address(quoteT);
    _mgv = setupMangrove(baseT, quoteT);

    bool noRevert;
    (noRevert, ) = address(_mgv).call{value: 10 ether}("");

    baseT.mint(address(this), 2 ether);
    baseT.approve(address(_mgv), 2 ether);
    quoteT.approve(address(_mgv), 1 ether);

    vm.label(msg.sender, "Test Runner");
    vm.label(address(this), "Gatekeeping_Test/maker");
    vm.label(_base, "$A");
    vm.label(_quote, "$B");
    vm.label(address(_mgv), "mgv");

    _mgv.newOffer(_base, _quote, 1 ether, 1 ether, 100_000, 0, 0);
    console.log("mgv", address(_mgv));

    _tkr = setupTaker(_mgv, _base, _quote);
    quoteT.mint(address(_tkr), 2 ether);
    _tkr.approveMgv(quoteT, 2 ether);
    vm.label(address(_tkr), "Taker");

    /* set lock to 1 to avoid spurious 15k gas cost */
    uint ofr = _mgv.newOffer(
      _base,
      _quote,
      0.1 ether,
      0.1 ether,
      100_000,
      0,
      0
    );
    _tkr.take(ofr, 0.1 ether);
  }

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
    return (_mgv, _tkr, _base, _quote);
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
    uint g = gasleft();
    mgv.updateOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 1, 1);
    console.log("Gas used", g - gasleft());
  }

  function test_update_full_offer() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    uint g = gasleft();
    mgv.updateOffer(base, quote, 0.5 ether, 1 ether, 100_001, 0, 1, 1);
    console.log("Gas used", g - gasleft());
  }

  function update_min_move_3_offer_before() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
  }

  function test_update_min_move_3_offer() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    uint g = gasleft();
    mgv.updateOffer(base, quote, 1.0 ether, 0.1 ether, 100_00, 0, 1, 1);
    console.log("Gas used", g - gasleft());
  }

  function update_min_move_6_offer_before() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
  }

  function test_update_min_move_6_offer() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    uint g = gasleft();
    mgv.updateOffer(base, quote, 1.0 ether, 0.1 ether, 100_00, 0, 1, 1);
    console.log("Gas used", g - gasleft());
  }

  function test_new_offer() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    uint g = gasleft();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 1);
    console.log("Gas used", g - gasleft());
  }

  function test_take_offer() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    uint g = gasleft();
    tkr.snipe(mgv, base, quote, 1, 1 ether, 1 ether, 100_000);
    console.log("Gas used", g - gasleft());
  }

  function test_partial_take_offer() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    uint g = gasleft();
    tkr.snipe(mgv, base, quote, 1, 0.5 ether, 0.5 ether, 100_000);
    console.log("Gas used", g - gasleft());
  }

  function test_market_order_1() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    uint g = gasleft();
    tkr.marketOrder(mgv, base, quote, 1 ether, 1 ether);
    console.log("Gas used", g - gasleft());
  }

  function market_order_8_before() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
  }

  function test_market_order_8() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    uint g = gasleft();
    tkr.marketOrder(mgv, base, quote, 2 ether, 2 ether);
    console.log("Gas used", g - gasleft());
  }
}
