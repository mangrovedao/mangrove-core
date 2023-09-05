// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20, ITaker, MgvLib, OLKey} from "mgv_src/MgvLib.sol";
import {Script2} from "mgv_lib/Script2.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";

contract TestTaker is ITaker, Script2 {
  IMangrove mgv;
  OLKey olKey;
  bool acceptNative = true;

  constructor(IMangrove _mgv, OLKey memory _ol) {
    mgv = _mgv;
    olKey = _ol;
  }

  receive() external payable {}

  function approveMgv(IERC20 token, uint amount) external {
    TransferLib.approveToken(token, address(mgv), amount);
  }

  function approve(IERC20 token, address spender, uint amount) external {
    TransferLib.approveToken(token, spender, amount);
  }

  function approveSpender(address spender, uint amount) external {
    mgv.approve(olKey.outbound, olKey.inbound, spender, amount);
  }

  function clean(uint offerId, uint takerWants) public returns (bool success) {
    return this.clean(mgv, olKey, offerId, takerWants, type(uint48).max);
  }

  function clean(uint offerId, uint takerWants, uint gasreq) public returns (bool success) {
    return this.clean(mgv, olKey, offerId, takerWants, gasreq);
  }

  function clean(IMangrove _mgv, OLKey memory _olKey, uint offerId, uint takerWants, uint gasreq)
    public
    returns (bool success)
  {
    uint bounty = this.cleanWithInfo(_mgv, _olKey, offerId, takerWants, gasreq);
    return bounty > 0;
  }

  function cleanWithInfo(uint offerId, uint takerWants) public returns (uint bounty) {
    return this.cleanWithInfo(mgv, olKey, offerId, takerWants, type(uint48).max);
  }

  function cleanWithInfo(IMangrove _mgv, OLKey memory _olKey, uint offerId, uint takerWants, uint gasreq)
    public
    returns (uint bounty)
  {
    int logPrice = _mgv.offers(_olKey, offerId).logPrice();
    return cleanByLogPriceWithInfo(_mgv, _olKey, offerId, logPrice, takerWants, gasreq);
  }

  function cleanByLogPrice(uint offerId, int logPrice, uint takerWants, uint gasreq) public returns (bool success) {
    return this.cleanByLogPrice(mgv, olKey, offerId, logPrice, takerWants, gasreq);
  }

  function cleanByLogPrice(
    IMangrove _mgv,
    OLKey memory _olKey,
    uint offerId,
    int logPrice,
    uint takerWants,
    uint gasreq
  ) public returns (bool success) {
    uint bounty = this.cleanByLogPriceWithInfo(_mgv, _olKey, offerId, logPrice, takerWants, gasreq);
    return bounty > 0;
  }

  function cleanByLogPriceWithInfo(
    IMangrove _mgv,
    OLKey memory _olKey,
    uint offerId,
    int logPrice,
    uint takerWants,
    uint gasreq
  ) public returns (uint bounty) {
    (, bounty) = _mgv.cleanByImpersonation(
      _olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, logPrice, gasreq, takerWants)), address(this)
    );
    return bounty;
  }

  function takerTrade(OLKey calldata, uint, uint) external pure override {}

  function marketOrderWithSuccess(uint takerWants) external returns (bool success) {
    (uint got,,,) = mgv.marketOrderByVolume(olKey, takerWants, type(uint96).max, true);
    return got > 0;
  }

  function marketOrder(uint wants, uint gives) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = mgv.marketOrderByVolume(olKey, wants, gives, true);
  }

  function marketOrder(uint wants, uint gives, bool fillWants) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = mgv.marketOrderByVolume(olKey, wants, gives, fillWants);
  }

  function marketOrder(IMangrove _mgv, OLKey memory _ol, uint takerWants, uint takerGives)
    external
    returns (uint takerGot, uint takerGave)
  {
    (takerGot, takerGave,,) = _mgv.marketOrderByVolume(_ol, takerWants, takerGives, true);
  }

  function marketOrderWithFail(uint wants, uint gives) external returns (uint takerGot, uint takerGave) {
    (takerGot, takerGave,,) = mgv.marketOrderByVolume(olKey, wants, gives, true);
  }
}
