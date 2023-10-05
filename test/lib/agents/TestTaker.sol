// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import {IMangrove} from "@mgv/src/IMangrove.sol";
import "@mgv/src/core/MgvLib.sol";
import {Script2} from "@mgv/lib/Script2.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";

contract TestTaker is Script2 {
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
    mgv.approve(olKey.outbound_tkn, olKey.inbound_tkn, spender, amount);
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
    Tick tick = _mgv.offers(_olKey, offerId).tick();
    return cleanByTickWithInfo(_mgv, _olKey, offerId, tick, takerWants, gasreq);
  }

  function cleanByTick(uint offerId, Tick tick, uint takerWants, uint gasreq) public returns (bool success) {
    return this.cleanByTick(mgv, olKey, offerId, tick, takerWants, gasreq);
  }

  function cleanByTick(IMangrove _mgv, OLKey memory _olKey, uint offerId, Tick tick, uint takerWants, uint gasreq)
    public
    returns (bool success)
  {
    uint bounty = this.cleanByTickWithInfo(_mgv, _olKey, offerId, tick, takerWants, gasreq);
    return bounty > 0;
  }

  function cleanByTickWithInfo(
    IMangrove _mgv,
    OLKey memory _olKey,
    uint offerId,
    Tick tick,
    uint takerWants,
    uint gasreq
  ) public returns (uint bounty) {
    (, bounty) = _mgv.cleanByImpersonation(
      _olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, tick, gasreq, takerWants)), address(this)
    );
    return bounty;
  }

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
