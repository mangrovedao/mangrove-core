// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_src/AbstractMangrove.sol";
import {IERC20, MgvLib, IMaker} from "mgv_src/MgvLib.sol";
import {MgvStructs,OL} from "mgv_src/MgvLib.sol";

contract TestMoriartyMaker is IMaker {
  uint constant DEFAULT_TICKSCALE = 1;
  AbstractMangrove mgv;
  address base;
  address quote;
  bool succeed;
  uint dummy;

  constructor(AbstractMangrove _mgv, address _base, address _quote) {
    mgv = _mgv;
    base = _base;
    quote = _quote;
    succeed = true;
  }

  function makerExecute(MgvLib.SingleOrder calldata order, OL calldata ol) public override returns (bytes32 ret) {
    bool _succeed = succeed;
    if (order.offerId == dummy) {
      succeed = false;
    }
    if (_succeed) {
      ret = "";
    } else {
      assert(false);
    }
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result, OL calldata ol) external override {}

  function newOfferByVolume(uint wants, uint gives, uint gasreq) public {
    mgv.newOfferByVolume(OL(base,quote,DEFAULT_TICKSCALE), wants, gives, gasreq, 0);
    mgv.newOfferByVolume(OL(base,quote,DEFAULT_TICKSCALE), wants, gives, gasreq, 0);
    mgv.newOfferByVolume(OL(base,quote,DEFAULT_TICKSCALE), wants, gives, gasreq, 0);
    mgv.newOfferByVolume(OL(base,quote,DEFAULT_TICKSCALE), wants, gives, gasreq, 0);
    (,MgvStructs.LocalPacked cfg) = mgv.config(OL(base, quote,DEFAULT_TICKSCALE));
    uint offer_gasbase = cfg.offer_gasbase();
    dummy = mgv.newOfferByVolume({
      ol: OL(base, quote, DEFAULT_TICKSCALE),
      wants: 1,
      gives: cfg.density().multiplyUp(offer_gasbase + 100_000),
      gasreq: 100000,
      gasprice: 0
    }); //dummy offer
  }

  function provisionMgv(uint amount) public {
    (bool success,) = address(mgv).call{value: amount}("");
    require(success);
  }

  function approveMgv(IERC20 token, uint amount) public {
    token.approve(address(mgv), amount);
  }

  receive() external payable {}
}
