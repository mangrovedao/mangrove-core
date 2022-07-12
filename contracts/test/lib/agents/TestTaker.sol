// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;
pragma abicoder v2;

import {AbstractMangrove} from "mgv_src/AbstractMangrove.sol";
import {IERC20, ITaker} from "mgv_src/MgvLib.sol";
import {Utilities} from "mgv_test/lib/Utilities.sol";

contract TestTaker is ITaker, Utilities {
  AbstractMangrove _mgv;
  address _base;
  address _quote;

  constructor(
    AbstractMangrove mgv,
    IERC20 base,
    IERC20 quote
  ) {
    _mgv = mgv;
    _base = address(base);
    _quote = address(quote);
  }

  receive() external payable {}

  function approveMgv(IERC20 token, uint amount) external {
    token.approve(address(_mgv), amount);
  }

  function approve(
    IERC20 token,
    address spender,
    uint amount
  ) external {
    token.approve(spender, amount);
  }

  function approveSpender(address spender, uint amount) external {
    _mgv.approve(_base, _quote, spender, amount);
  }

  function take(uint offerId, uint takerWants) external returns (bool success) {
    //uint taken = TestEvents.min(makerGives, takerWants);
    (success, , , , ) = this.takeWithInfo(offerId, takerWants);
  }

  function takeWithInfo(uint offerId, uint takerWants)
    external
    returns (
      bool,
      uint,
      uint,
      uint,
      uint
    )
  {
    uint[4][] memory targets = wrap_dynamic(
      [offerId, takerWants, type(uint96).max, type(uint48).max]
    );
    (
      uint successes,
      uint got,
      uint gave,
      uint totalPenalty,
      uint feePaid
    ) = _mgv.snipes(_base, _quote, targets, true);
    return (successes == 1, got, gave, totalPenalty, feePaid);
    //return taken;
  }

  function snipe(
    AbstractMangrove __mgv,
    address __base,
    address __quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq
  ) external returns (bool) {
    uint[4][] memory targets = wrap_dynamic(
      [offerId, takerWants, takerGives, gasreq]
    );
    (uint successes, , , , ) = __mgv.snipes(__base, __quote, targets, true);
    return successes == 1;
  }

  function takerTrade(
    address,
    address,
    uint,
    uint
  ) external pure override {}

  function marketOrder(uint wants, uint gives)
    external
    returns (uint takerGot, uint takerGave)
  {
    (takerGot, takerGave, , ) = _mgv.marketOrder(
      _base,
      _quote,
      wants,
      gives,
      true
    );
  }

  function marketOrder(
    AbstractMangrove __mgv,
    address __base,
    address __quote,
    uint takerWants,
    uint takerGives
  ) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave, , ) = __mgv.marketOrder(
      __base,
      __quote,
      takerWants,
      takerGives,
      true
    );
  }

  function marketOrderWithFail(uint wants, uint gives)
    external
    returns (uint takerGot, uint takerGave)
  {
    (takerGot, takerGave, , ) = _mgv.marketOrder(
      _base,
      _quote,
      wants,
      gives,
      true
    );
  }
}
