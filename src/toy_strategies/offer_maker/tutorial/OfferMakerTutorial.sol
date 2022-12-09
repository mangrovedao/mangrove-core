// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Import the types we will be using below
import {Direct} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20, MgvLib} from "mgv_src/MgvLib.sol";

//----------------

contract OfferMakerTutorial is Direct, ILiquidityProvider {
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
    // the function is payable to allow us to provision an offer
    payable
    // only the admin of this contract is allowed to post offers using this contract
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

  //----------------

  event OfferTakenSuccessfully(uint);

  ///@notice Post-hook that is invoked when the offer is taken successfully.
  function __posthookSuccess__(MgvLib.SingleOrder calldata, bytes32) internal virtual override returns (bytes32) {
    emit OfferTakenSuccessfully(42);
    return 0;
  }
}

//---------------------
