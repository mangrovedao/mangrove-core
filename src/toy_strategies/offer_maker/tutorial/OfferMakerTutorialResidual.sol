// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Import the types we will be using below
import {Direct} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";
import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20, MgvLib} from "mgv_src/MgvLib.sol";

//----------------

/// @title This is a copy of OfferMakerTutorial.sol with a changed __posthookSuccess__
contract OfferMakerTutorialResidual is Direct, ILiquidityProvider {
  ///@notice Constructor
  ///@param mgv The core Mangrove contract
  ///@param deployer The address of the deployer
  constructor(IMangrove mgv, address deployer)
    // Pass on the reference to the core mangrove contract
    Direct(
      mgv,
      // Do not use a router - i.e., transfer tokens directly to and from the maker's reserve
      NO_ROUTER,
      // Store total gas requirement of this strategy
      100_000,
      deployer
    )
  {}

  //--------------

  ///@inheritdoc ILiquidityProvider
  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId)
    public
    payable
    override
    onlyAdmin
    returns (uint offerId)
  {
    return newOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerGasreq());
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
        pivotId: pivotId, // a best pivot estimate for cheap offer insertion in the offer list - this should be a parameter computed off-chain for cheaper insertion
        fund: msg.value, // WEIs in that are used to provision the offer.
        noRevert: false // we want to revert on error
      })
    );
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
  ) public payable override adminOrCaller(address(MGV)) {
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

  ///@inheritdoc ILiquidityProvider
  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId)
    public
    payable
    override
    adminOrCaller(address(MGV))
  {
    return updateOffer(outbound_tkn, inbound_tkn, wants, gives, pivotId, offerId, offerGasreq());
  }

  ///@inheritdoc ILiquidityProvider
  function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
    public
    adminOrCaller(address(MGV))
    returns (uint freeWei)
  {
    return _retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
  }

  //-------------

  ///@inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32 data) {
    data = super.__lastLook__(order);
    require(order.wants == order.offer.gives(), "tutorial/mustBeFullyTaken");
  }

  //----------------

  ///@notice Event emitted when the offer is taken successfully.
  ///@param someData is a dummy parameter.
  event OfferTakenSuccessfully(uint someData);

  ///@notice Post-hook that is invoked when the offer is taken successfully.
  ///@param order is a recall of the taker order that is at the origin of the current trade.
  ///@param makerData is the returned value of the `__lastLook__` hook.
  ///@inheritdoc Direct
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
