// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import {AbstractMangrove} from "mgv_src/AbstractMangrove.sol";
import {IERC20, ITaker} from "mgv_src/MgvLib.sol";
import {Script2} from "mgv_lib/Script2.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";

contract TestTaker is ITaker, Script2 {
  AbstractMangrove _mgv;
  address _base;
  address _quote;
  bool acceptNative = true;

  constructor(AbstractMangrove mgv, IERC20 base, IERC20 quote) {
    _mgv = mgv;
    _base = address(base);
    _quote = address(quote);
  }

  receive() external payable {}

  function approveMgv(IERC20 token, uint amount) external {
    TransferLib.approveToken(token, address(_mgv), amount);
  }

  function approve(IERC20 token, address spender, uint amount) external {
    TransferLib.approveToken(token, spender, amount);
  }

  function approveSpender(address spender, uint amount) external {
    _mgv.approve(_base, _quote, spender, amount);
  }

  function clean(
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq
  ) external returns (bool) {
    return this.clean(_mgv, _base, _quote, offerId, takerWants, takerGives, gasreq);
  }

  function clean(
    AbstractMangrove __mgv,
    address __base,
    address __quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq
  ) external returns (bool) {
    (bool success,,,,) = this.cleanWithInfo(__mgv, __base, __quote, offerId, takerWants, takerGives, gasreq);
    return success;
  }

  function cleanWithInfo(
    uint offerId,
    uint takerWants
  ) external returns (bool, uint, uint, uint, uint) {
    return this.cleanWithInfo(_mgv, _base, _quote, offerId, takerWants, type(uint96).max, type(uint48).max);
  }

  function cleanWithInfo(
    AbstractMangrove __mgv,
    address __base,
    address __quote,
    uint offerId,
    uint takerWants,
    uint takerGives,
    uint gasreq
  ) external returns (bool success, uint got, uint gave, uint totalPenalty, uint feePaid) {
    uint[4][] memory targets = wrap_dynamic([offerId, takerWants, takerGives, gasreq]);
    uint successes;
    // FIXME: Replace with call to `clean` once `snipes` has been renamed
    (successes, got, gave, totalPenalty, feePaid) = __mgv.snipes(__base, __quote, targets, true);
    success = successes == 1;
  }

  function takerTrade(address, address, uint, uint) external pure override {}

  // FIXME: Can we find a better name here? The return value differs from the other marketOrder functions, so would be good to signal this somehow
  function marketOrderAtAnyPrice(uint takerWants) external returns (bool success) {
    (uint got,,,) = _mgv.marketOrder(_base, _quote, takerWants, type(uint96).max, true);
    // FIXME: 4 tests fail if this
    return got > 0;
  }

  function marketOrder(uint wants, uint gives) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = _mgv.marketOrder(_base, _quote, wants, gives, true);
  }

  function marketOrder(AbstractMangrove __mgv, address __base, address __quote, uint takerWants, uint takerGives)
    external
    returns (uint takerGot, uint takerGave)
  {
    (takerGot, takerGave,,) = __mgv.marketOrder(__base, __quote, takerWants, takerGives, true);
  }

  function marketOrderWithFail(uint wants, uint gives) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = _mgv.marketOrder(_base, _quote, wants, gives, true);
  }
}
