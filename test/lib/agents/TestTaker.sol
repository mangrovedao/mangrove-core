// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import {AbstractMangrove} from "mgv_src/AbstractMangrove.sol";
// FIXME: Temporarily use TestMangrove until all tests are migrated away from snipes
import {TestMangrove} from "mgv_test/lib/MangroveTest.sol";
import {IERC20, ITaker, MgvLib} from "mgv_src/MgvLib.sol";
import {Script2} from "mgv_lib/Script2.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";
import {Tick} from "mgv_lib/TickLib.sol";

contract TestTaker is ITaker, Script2 {
  AbstractMangrove _mgv;
  TestMangrove _testMgv;
  address _base;
  address _quote;
  bool acceptNative = true;

  // constructor(AbstractMangrove mgv, IERC20 base, IERC20 quote) {
  constructor(TestMangrove mgv, IERC20 base, IERC20 quote) {
    _mgv = mgv;
    _testMgv = mgv;
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

  // FIXME: This is only by Scenarii.t.sol which is not easy to migrate nor determine if is still relevant
  function takeWithInfo(uint offerId, uint takerWants) external returns (bool, uint, uint, uint, uint) {
    Tick tick = _mgv.offers(_base, _quote, offerId).tick();
    uint[4][] memory targets = wrap_dynamic([offerId, uint(Tick.unwrap(tick)), takerWants, type(uint48).max]);
    (uint successes, uint got, uint gave, uint totalPenalty, uint feePaid) =
      _testMgv.snipesInTest(_base, _quote, targets, true);
    return (successes == 1, got, gave, totalPenalty, feePaid);
    //return taken;
  }

  function clean(uint offerId, uint takerWants) public returns (bool success) {
    return this.clean(_mgv, _base, _quote, offerId, takerWants, type(uint48).max);
  }

  function clean(uint offerId, uint takerWants, uint gasreq) public returns (bool success) {
    return this.clean(_mgv, _base, _quote, offerId, takerWants, gasreq);
  }

  function clean(AbstractMangrove __mgv, address __base, address __quote, uint offerId, uint takerWants, uint gasreq)
    public
    returns (bool success)
  {
    uint bounty = this.cleanWithInfo(__mgv, __base, __quote, offerId, takerWants, gasreq);
    return bounty > 0;
  }

  function cleanWithInfo(uint offerId, uint takerWants) public returns (uint bounty) {
    return this.cleanWithInfo(_mgv, _base, _quote, offerId, takerWants, type(uint48).max);
  }

  function cleanWithInfo(
    AbstractMangrove __mgv,
    address __base,
    address __quote,
    uint offerId,
    uint takerWants,
    uint gasreq
  ) public returns (uint bounty) {
    Tick tick = __mgv.offers(__base, __quote, offerId).tick();
    return cleanByTickWithInfo(__mgv, __base, __quote, offerId, tick, takerWants, gasreq);
  }

  function cleanByTick(uint offerId, Tick tick, uint takerWants, uint gasreq) public returns (bool success) {
    return this.cleanByTick(_mgv, _base, _quote, offerId, tick, takerWants, gasreq);
  }

  function cleanByTick(
    AbstractMangrove __mgv,
    address __base,
    address __quote,
    uint offerId,
    Tick tick,
    uint takerWants,
    uint gasreq
  ) public returns (bool success) {
    uint bounty = this.cleanByTickWithInfo(__mgv, __base, __quote, offerId, tick, takerWants, gasreq);
    return bounty > 0;
  }

  function cleanByTickWithInfo(
    AbstractMangrove __mgv,
    address __base,
    address __quote,
    uint offerId,
    Tick tick,
    uint takerWants,
    uint gasreq
  ) public returns (uint bounty) {
    (, bounty) = __mgv.cleanByImpersonation(
      __base, __quote, wrap_dynamic(MgvLib.CleanTarget(offerId, Tick.unwrap(tick), gasreq, takerWants)), address(this)
    );
    return bounty;
  }

  function takerTrade(address, address, uint, uint) external pure override {}

  function marketOrderWithSuccess(uint takerWants) external returns (bool success) {
    (uint got,,,) = _mgv.marketOrderByVolume(_base, _quote, takerWants, type(uint96).max, true);
    return got > 0;
  }

  function marketOrder(uint wants, uint gives) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = _mgv.marketOrderByVolume(_base, _quote, wants, gives, true);
  }

  function marketOrder(uint wants, uint gives, bool fillWants) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = _mgv.marketOrderByVolume(_base, _quote, wants, gives, fillWants);
  }

  function marketOrder(AbstractMangrove __mgv, address __base, address __quote, uint takerWants, uint takerGives)
    external
    returns (uint takerGot, uint takerGave)
  {
    (takerGot, takerGave,,) = __mgv.marketOrderByVolume(__base, __quote, takerWants, takerGives, true);
  }

  function marketOrderWithFail(uint wants, uint gives) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = _mgv.marketOrderByVolume(_base, _quote, wants, gives, true);
  }
}
