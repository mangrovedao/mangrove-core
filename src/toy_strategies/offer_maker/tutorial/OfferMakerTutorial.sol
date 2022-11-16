// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Import the types we will be using below
import {Direct} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {IMakerLogic} from "mgv_src/strategies/interfaces/IMakerLogic.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20, MgvLib} from "mgv_src/MgvLib.sol";

//----------------

contract OfferMakerTutorial is Direct {
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

  ///@notice Post a new offer on Mangrove owned by this contract
  ///@param outbound_tkn the maker's outbound token of the offer list - the token you give
  ///@param inbound_tkn the maker's inbound token of the offer list - the token you want
  ///@param gives the amount of outbound tokens you give
  ///@param wants the amount of inbound tokens you want
  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint gives, uint wants)
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
        gasreq: type(uint24).max, //  the new amount of gas units that are required to execute the trade (use type(uint).max for using `this.offerGasReq()`)
        gasprice: 0, // the gasprice used to compute offer's provision (we use 0 to use Mangrove's gasprice)
        pivotId: 0, // a best pivot estimate for cheap offer insertion in the offer list - this should be a parameter computed off-chain for cheaper insertion
        fund: msg.value, // WEIs in that are used to provision the offer.
        noRevert: false, // we want to revert on error
        owner: msg.sender // The sender is the owner
      })
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
