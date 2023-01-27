// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Import the types we will be using below
import {Direct} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20, MgvLib} from "mgv_src/MgvLib.sol";

/* Note this is a copy of OfferMakerTutorial.sol with a changed __posthookSuccess__ */

//----------------

contract OfferMakerTutorialResidual is Direct, ILiquidityProvider {
  constructor(IMangrove mgv, address deployer)
    // Pass on the reference to the core mangrove contract
    Direct(
      mgv,
      // Do not use a router - i.e., transfer tokens directly to and from the maker's reserve
      NO_ROUTER,
      // Store total gas requirement of this strategy
      100_000
    )
  {}

  //--------------

  ///@inheritdoc ILiquidityProvider
  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId)
    public
    payable
    onlyAdmin
    returns (uint offerId)
  {
    offerId = _newOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: offerGasreq(),
        gasprice: 0,
        pivotId: pivotId, // a best pivot estimate for cheap offer insertion in the offer list - this should be a parameter computed off-chain for cheaper insertion
        fund: msg.value, // WEIs in that are used to provision the offer.
        noRevert: false // we want to revert on error
      })
    );
  }

  ///@inheritdoc ILiquidityProvider
  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId)
    public
    payable
    override
    mgvOrAdmin
  {
    _updateOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: offerGasreq(),
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false
      }),
      offerId
    );
  }

  //-------------

  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32 data) {
    data = super.__lastLook__(order);
    require(order.wants == order.offer.gives(), "tutorial/mustBeFullyTaken");
    return "mgvOffer/proceed";
  }

  //----------------

  event OfferTakenSuccessfully(uint);

  ///@notice Post-hook that is invoked when the offer is taken successfully.
  ///@param order is a recall of the taker order that is at the origin of the current trade.
  ///@param makerData is the returned value of the `__lastLook__` hook.
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    virtual
    override
    returns (bytes32)
  {
    emit OfferTakenSuccessfully(42);
    // repost offer residual if any
    return super.__posthookSuccess__(order, makerData);
  }
}

//---------------------
