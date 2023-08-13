// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_src/AbstractMangrove.sol";
import {IERC20, MgvLib, IMaker} from "mgv_src/MgvLib.sol";
import {MgvStructs, OL} from "mgv_src/MgvLib.sol";

contract TestMoriartyMaker is IMaker {
  AbstractMangrove mgv;
  OL ol;
  bool succeed;
  uint dummy;

  constructor(AbstractMangrove _mgv, OL memory _ol) {
    mgv = _mgv;
    ol = _ol;
    succeed = true;
  }

  function makerExecute(MgvLib.SingleOrder calldata order) public override returns (bytes32 ret) {
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

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) external override {}

  function newOfferByVolume(uint wants, uint gives, uint gasreq) public {
    mgv.newOfferByVolume(ol, wants, gives, gasreq, 0);
    mgv.newOfferByVolume(ol, wants, gives, gasreq, 0);
    mgv.newOfferByVolume(ol, wants, gives, gasreq, 0);
    mgv.newOfferByVolume(ol, wants, gives, gasreq, 0);
    (, MgvStructs.LocalPacked cfg) = mgv.config(ol);
    uint offer_gasbase = cfg.offer_gasbase();
    dummy = mgv.newOfferByVolume({
      ol: ol,
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
