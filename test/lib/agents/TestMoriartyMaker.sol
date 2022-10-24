// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "src/AbstractMangrove.sol";
import {IERC20, MgvLib, IMaker} from "src/MgvLib.sol";
import {MgvStructs} from "src/MgvLib.sol";

contract TestMoriartyMaker is IMaker {
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

  function newOffer(uint wants, uint gives, uint gasreq, uint pivotId) public {
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    (, MgvStructs.LocalPacked cfg) = mgv.config(base, quote);
    uint density = cfg.density();
    uint offer_gasbase = cfg.offer_gasbase();
    dummy = mgv.newOffer({
      outbound_tkn: base,
      inbound_tkn: quote,
      wants: 1,
      gives: (density > 0 ? density : 1) * (offer_gasbase + 100000),
      gasreq: 100000,
      gasprice: 0,
      pivotId: 0
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
