// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
pragma abicoder v2;
import "./Passthrough.sol";
import "../../AbstractMangrove.sol";
import "../../MgvLib.sol";
import {MgvPack as MP} from "../../MgvPack.sol";

contract TestMoriartyMaker is IMaker, Passthrough {
  AbstractMangrove mgv;
  address base;
  address quote;
  bool succeed;
  uint dummy;

  constructor(
    AbstractMangrove _mgv,
    address _base,
    address _quote
  ) {
    mgv = _mgv;
    base = _base;
    quote = _quote;
    succeed = true;
  }

  function makerExecute(ML.SingleOrder calldata order)
    public
    override
    returns (bytes32 ret)
  {
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

  function makerPosthook(
    ML.SingleOrder calldata order,
    ML.OrderResult calldata result
  ) external override {}

  function newOffer(
    uint wants,
    uint gives,
    uint gasreq,
    uint pivotId
  ) public {
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    mgv.newOffer(base, quote, wants, gives, gasreq, 0, pivotId);
    (, bytes32 cfg) = mgv.config(base, quote);
    uint density = MP.local_unpack_density(cfg);
    uint offer_gasbase = MP.local_unpack_offer_gasbase(cfg);
    dummy = mgv.newOffer({
      outbound_tkn: base,
      inbound_tkn: quote,
      wants: 1,
      gives: density * (offer_gasbase + 100000),
      gasreq: 100000,
      gasprice: 0,
      pivotId: 0
    }); //dummy offer
  }

  function provisionMgv(uint amount) public {
    (bool success, ) = address(mgv).call{value: amount}("");
    require(success);
  }

  function approveMgv(IERC20 token, uint amount) public {
    token.approve(address(mgv), amount);
  }

  receive() external payable {}
}
