// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {Direct, AbstractRouter, IMangrove, IERC20} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";

contract OfferMaker is ILiquidityProvider, Direct {
  // router_ needs to bind to this contract
  // since one cannot assume `this` is admin of router, one cannot do this here in general
  constructor(IMangrove mgv, AbstractRouter router_, address deployer, uint gasreq, address owner)
    Direct(mgv, router_, gasreq, owner)
  {
    // stores total gas requirement of this strat (depends on router gas requirements)
    // if contract is deployed with static address, then one must set admin to something else than msg.sender
    if (deployer != msg.sender) {
      setAdmin(deployer);
    }
  }

  ///@inheritdoc ILiquidityProvider
  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint gasreq)
    public
    payable
    override
    onlyAdmin
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
        noRevert: false
      })
    );
  }

  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId)
    external
    payable
    onlyAdmin
    returns (uint offerId)
  {
    return newOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerGasreq());
  }

  ///@inheritdoc ILiquidityProvider
  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint pivotId,
    uint offerId,
    uint gasreq
  ) public payable override onlyAdmin {
    _updateOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: gasreq,
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false
      }),
      offerId
    );
  }

  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId)
    external
    payable
    onlyAdmin
  {
    updateOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerId, offerGasreq());
  }

  ///@inheritdoc ILiquidityProvider
  function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
    public
    adminOrCaller(address(MGV))
    returns (uint freeWei)
  {
    freeWei = _retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
    if (freeWei > 0) {
      require(MGV.withdraw(freeWei), "Direct/withdrawFail");
      // sending native tokens to `msg.sender` prevents reentrancy issues
      // (the context call of `retractOffer` could be coming from `makerExecute` and a different recipient of transfer than `msg.sender` could use this call to make offer fail)
      (bool noRevert,) = admin().call{value: freeWei}("");
      require(noRevert, "mgvOffer/weiTransferFail");
    }
  }
}
