// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {Forwarder, IMangrove, IERC20} from "mgv_src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {SimpleRouter, AbstractRouter} from "mgv_src/strategies/routers/SimpleRouter.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";

contract OfferForwarder is ILiquidityProvider, Forwarder {
  constructor(IMangrove mgv, address deployer) Forwarder(mgv, new SimpleRouter(), 30_000) {
    AbstractRouter router_ = router();
    router_.bind(address(this));
    if (deployer != msg.sender) {
      setAdmin(deployer);
      router_.setAdmin(deployer);
    }
  }

  /// @inheritdoc ILiquidityProvider
  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint gasreq)
    public
    payable
    override
    returns (uint offerId)
  {
    (offerId,) = _newOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: gasreq,
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false // propagates Mangrove's revert data in case of newOffer failure
      }),
      msg.sender
    );
  }

  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId)
    public
    payable
    returns (uint offerId)
  {
    return newOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerGasreq());
  }

  ///@inheritdoc ILiquidityProvider
  ///@dev the `gasprice` argument is always ignored in `Forwarder` logic, since it has to be derived from `msg.value` of the call (see `_newOffer`).
  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint pivotId,
    uint offerId,
    uint gasreq
  ) public payable override onlyOwner(outbound_tkn, inbound_tkn, offerId) {
    OfferArgs memory args;

    // funds to compute new gasprice is msg.value. Will use old gasprice if no funds are given
    // it might be tempting to include `od.weiBalance` here but this will trigger a recomputation of the `gasprice`
    // each time a offer is updated.
    args.fund = msg.value; // if inside a hook (Mangrove is `msg.sender`) this will be 0
    args.outbound_tkn = outbound_tkn;
    args.inbound_tkn = inbound_tkn;
    args.wants = wants;
    args.gives = gives;
    args.gasreq = gasreq;
    args.pivotId = pivotId;
    args.noRevert = false; // will throw if Mangrove reverts
    // weiBalance is used to provision offer
    _updateOffer(args, offerId);
  }

  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId)
    public
    payable
    onlyOwner(outbound_tkn, inbound_tkn, offerId)
  {
    updateOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerId, offerGasreq());
  }

  ///@inheritdoc ILiquidityProvider
  function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
    public
    mgvOrOwner(outbound_tkn, inbound_tkn, offerId)
    returns (uint freeWei)
  {
    return _retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 maker_data)
    internal
    override
    returns (bytes32 data)
  {
    data = super.__posthookSuccess__(order, maker_data);
    require(
      data == "posthook/reposted" || data == "posthook/filled",
      data == "mgv/insufficientProvision"
        ? "mgv/insufficientProvision"
        : (data == "mgv/writeOffer/density/tooLow" ? "mgv/writeOffer/density/tooLow" : "posthook/failed")
    );
  }
}
