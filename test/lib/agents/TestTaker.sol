// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import {AbstractMangrove} from "mgv_src/AbstractMangrove.sol";
import {IERC20, ITaker, OL} from "mgv_src/MgvLib.sol";
import {Script2} from "mgv_lib/Script2.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";
import {Tick} from "mgv_lib/TickLib.sol";

contract TestTaker is ITaker, Script2 {
  AbstractMangrove mgv;
  OL ol;
  bool acceptNative = true;

  constructor(AbstractMangrove _mgv, OL memory _ol) {
    mgv = _mgv;
    ol = _ol;
  }

  receive() external payable {}

  function approveMgv(IERC20 token, uint amount) external {
    TransferLib.approveToken(token, address(mgv), amount);
  }

  function approve(IERC20 token, address spender, uint amount) external {
    TransferLib.approveToken(token, spender, amount);
  }

  function approveSpender(address spender, uint amount) external {
    mgv.approve(ol.outbound, ol.inbound, spender, amount);
  }

  function take(uint offerId, uint takerWants) external returns (bool success) {
    //uint taken = TestEvents.min(makerGives, takerWants);
    (success,,,,) = this.takeWithInfo(offerId, takerWants);
  }

  function takeWithInfo(uint offerId, uint takerWants) external returns (bool, uint, uint, uint, uint) {
    int logPrice = mgv.offers(ol, offerId).logPrice();
    uint[4][] memory targets = wrap_dynamic([offerId, uint(logPrice), takerWants, type(uint48).max]);
    (uint successes, uint got, uint gave, uint totalPenalty, uint feePaid) = mgv.snipes(ol, targets, true);
    return (successes == 1, got, gave, totalPenalty, feePaid);
    //return taken;
  }

  function snipeByVolume(AbstractMangrove _mgv, OL memory _ol, uint offerId, uint takerWants, uint gasreq)
    external
    returns (bool)
  {
    int logPrice = _mgv.offers(_ol, offerId).logPrice();
    uint[4][] memory targets = wrap_dynamic([offerId, uint(logPrice), takerWants, gasreq]);
    (uint successes,,,,) = _mgv.snipes(_ol, targets, true);
    return successes == 1;
  }

  function snipeByLogPrice(
    AbstractMangrove _mgv,
    OL memory _ol,
    uint offerId,
    int logPrice,
    uint takerWants,
    uint gasreq
  ) external returns (bool) {
    uint[4][] memory targets = wrap_dynamic([offerId, uint(logPrice), takerWants, gasreq]);
    (uint successes,,,,) = _mgv.snipes(_ol, targets, true);
    return successes == 1;
  }

  function takerTrade(OL calldata, uint, uint) external pure override {}

  function marketOrder(uint wants, uint gives) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = mgv.marketOrderByVolume(ol, wants, gives, true);
  }

  function marketOrder(uint wants, uint gives, bool fillWants) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = mgv.marketOrderByVolume(ol, wants, gives, fillWants);
  }

  function marketOrder(AbstractMangrove _mgv, OL memory _ol, uint takerWants, uint takerGives)
    external
    returns (uint takerGot, uint takerGave)
  {
    (takerGot, takerGave,,) = _mgv.marketOrderByVolume(_ol, takerWants, takerGives, true);
  }

  function marketOrderWithFail(uint wants, uint gives) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = mgv.marketOrderByVolume(ol, wants, gives, true);
  }
}
