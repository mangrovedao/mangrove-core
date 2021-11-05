// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma abicoder v2;
import "../../AbstractMangrove.sol";
import "./OfferManager.sol";
import "./TestToken.sol";

contract TestDelegateTaker is ITaker {
  OfferManager ofrMgr;
  TestToken base;
  TestToken quote;

  constructor(
    OfferManager _ofrMgr,
    TestToken _base,
    TestToken _quote
  ) {
    ofrMgr = _ofrMgr;
    base = _base;
    quote = _quote;
  }

  receive() external payable {}

  function takerTrade(
    //NB this is not called if mgv is not a flashTaker mgv
    address,
    address,
    uint,
    uint shouldGive
  ) external override {
    if (msg.sender == address(ofrMgr)) {
      TestToken(quote).mint(address(this), shouldGive); // taker should have been given admin status for quote
    } // taker should have approved ofrMgr for quote
  }

  function delegateOrder(
    OfferManager mgr,
    uint wants,
    uint gives,
    AbstractMangrove mgv,
    bool invertedResidual
  ) public {
    try quote.approve(address(mgr), gives) {
      mgr.order{value: 0.01 ether}(
        mgv,
        address(base),
        address(quote),
        wants,
        gives,
        invertedResidual
      );
    } catch {
      require(false, "failed to approve mgr");
    }
  }
}
