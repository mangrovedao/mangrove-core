// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../AbstractMangrove.sol";
import "../MgvLib.sol";
import "hardhat/console.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/TestMoriartyMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";

// In these tests, the testing contract is the market maker.
contract Gas_Test is IMaker {
  receive() external payable {}

  AbstractMangrove _mgv;
  TestTaker _tkr;
  address _base;
  address _quote;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    _base = address(baseT);
    _quote = address(quoteT);
    _mgv = MgvSetup.setup(baseT, quoteT);

    bool noRevert;
    (noRevert, ) = address(_mgv).call{value: 10 ether}("");

    baseT.mint(address(this), 2 ether);
    baseT.approve(address(_mgv), 2 ether);
    quoteT.approve(address(_mgv), 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(_base, "$A");
    Display.register(_quote, "$B");
    Display.register(address(_mgv), "mgv");

    _mgv.newOffer(_base, _quote, 1 ether, 1 ether, 100_000, 0, 0);
    console.log("mgv", address(_mgv));

    _tkr = TakerSetup.setup(_mgv, _base, _quote);
    quoteT.mint(address(_tkr), 2 ether);
    _tkr.approveMgv(quoteT, 2 ether);
    Display.register(address(_tkr), "Taker");

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

  function makerExecute(ML.SingleOrder calldata)
    external
    pure
    override
    returns (bytes32)
  {
    return ""; // silence unused function parameter
  }

  function makerPosthook(
    ML.SingleOrder calldata order,
    ML.OrderResult calldata result
  ) external override {}

  function update_min_move_0_offer_test() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    //uint g = gasleft();
    //uint h;
    mgv.updateOffer(base, quote, 1 ether, 1 ether, 100_000, 0, 1, 1);
    //h = gasleft();
    //console.log("Gas used", g - h);
  }

  function update_full_offer_test() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    //uint g = gasleft();
    //uint h;
    mgv.updateOffer(base, quote, 0.5 ether, 1 ether, 100_001, 0, 1, 1);
    //h = gasleft();
    //console.log("Gas used", g - h);
  }

  function update_min_move_3_offer_before() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 0);
  }

  function update_min_move_3_offer_test() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    //uint g = gasleft();
    //uint h;
    mgv.updateOffer(base, quote, 1.0 ether, 0.1 ether, 100_00, 0, 1, 1);
    //h = gasleft();
    //console.log("Gas used", g - h);
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

  function update_min_move_6_offer_test() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    //uint g = gasleft();
    //uint h;
    mgv.updateOffer(base, quote, 1.0 ether, 0.1 ether, 100_00, 0, 1, 1);
    //h = gasleft();
    //console.log("Gas used", g - h);
  }

  function new_offer_test() public {
    (AbstractMangrove mgv, , address base, address quote) = getStored();
    //uint g = gasleft();
    //uint h;
    mgv.newOffer(base, quote, 0.1 ether, 0.1 ether, 100_000, 0, 1);
    //h = gasleft();
    //console.log("Gas used", g - h);
  }

  function take_offer_test() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    //uint g = gasleft();
    //uint h;
    tkr.snipe(mgv, base, quote, 1, 1 ether, 1 ether, 100_000);
    //h = gasleft();
    //console.log("Gas used", g - h);
  }

  function partial_take_offer_test() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    //uint g = gasleft();
    //uint h;
    tkr.snipe(mgv, base, quote, 1, 0.5 ether, 0.5 ether, 100_000);
    //h = gasleft();
    //console.log("Gas used", g - h);
  }

  function market_order_1_test() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    //uint g = gasleft();
    //uint h;
    tkr.marketOrder(mgv, base, quote, 1 ether, 1 ether);
    //h = gasleft();
    //console.log("Gas used", g - h);
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

  function market_order_8_test() public {
    (
      AbstractMangrove mgv,
      TestTaker tkr,
      address base,
      address quote
    ) = getStored();
    //uint g = gasleft();
    //uint h;
    tkr.marketOrder(mgv, base, quote, 2 ether, 2 ether);
    //h = gasleft();
    //console.log("Gas used", g - h);
  }
}
