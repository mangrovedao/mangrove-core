// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib, HasMgvEvents, IMgvMonitor, MgvStructs} from "./MgvLib.sol";
import {MgvRoot} from "./MgvRoot.sol";

/* `MgvHasOffers` contains the state variables and functions common to both market-maker operations and market-taker operations. Mostly: storing offers, removing them, updating market makers' provisions. */
contract MgvHasOffers is MgvRoot {
  /* # State variables */
  /* Makers provision their possible penalties in the `balanceOf` mapping.

       Offers specify the amount of gas they require for successful execution ([`gasreq`](#structs.js/gasreq)). To minimize book spamming, market makers must provision a *penalty*, which depends on their `gasreq` and on the pair's [`offer_gasbase`](#structs.js/gasbase). This provision is deducted from their `balanceOf`. If an offer fails, part of that provision is given to the taker, as retribution. The exact amount depends on the gas used by the offer before failing.

       The Mangrove keeps track of their available balance in the `balanceOf` map, which is decremented every time a maker creates a new offer, and may be modified on offer updates/cancellations/takings.
     */
  mapping(address => uint) public balanceOf;

  /* # Read functions */
  /* Convenience function to get best offer of the given pair */
  function best(address outbound_tkn, address inbound_tkn) external view returns (uint) {
    unchecked {
      return pairs[outbound_tkn][inbound_tkn].local.best();
    }
  }

  /* Convenience function to get an offer in packed format */
  function offers(address outbound_tkn, address inbound_tkn, uint offerId)
    external
    view
    returns (MgvStructs.OfferPacked)
  {
    return pairs[outbound_tkn][inbound_tkn].offerData[offerId].offer;
  }

  /* Convenience function to get an offer detail in packed format */
  function offerDetails(address outbound_tkn, address inbound_tkn, uint offerId)
    external
    view
    returns (MgvStructs.OfferDetailPacked)
  {
    return pairs[outbound_tkn][inbound_tkn].offerData[offerId].detail;
  }

  /* Returns information about an offer in ABI-compatible structs. Do not use internally, would be a huge memory-copying waste. Use `pairs[outbound_tkn][inbound_tkn].offers` and `pairs[outbound_tkn][inbound_tkn].offerDetails` instead. */
  function offerInfo(address outbound_tkn, address inbound_tkn, uint offerId)
    external
    view
    returns (MgvStructs.OfferUnpacked memory offer, MgvStructs.OfferDetailUnpacked memory offerDetail)
  {
    unchecked {
      OfferData storage offerData = pairs[outbound_tkn][inbound_tkn].offerData[offerId];
      offer = offerData.offer.to_struct();
      offerDetail = offerData.detail.to_struct();
    }
  }

  /* # Provision debit/credit utility functions */
  /* `balanceOf` is in wei of ETH. */

  function debitWei(address maker, uint amount) internal {
    unchecked {
      uint makerBalance = balanceOf[maker];
      require(makerBalance >= amount, "mgv/insufficientProvision");
      balanceOf[maker] = makerBalance - amount;
      emit Debit(maker, amount);
    }
  }

  function creditWei(address maker, uint amount) internal {
    unchecked {
      balanceOf[maker] += amount;
      emit Credit(maker, amount);
    }
  }

  /* # Misc. low-level functions */
  /* ## Offer deletion */

  /* When an offer is deleted, it is marked as such by setting `gives` to 0. Note that provision accounting in Mangrove aims to minimize writes. Each maker `fund`s Mangrove to increase its balance. When an offer is created/updated, we compute how much should be reserved to pay for possible penalties. That amount can always be recomputed with `offerDetail.gasprice * (offerDetail.gasreq + offerDetail.offer_gasbase)`. The balance is updated to reflect the remaining available ethers.

     Now, when an offer is deleted, the offer can stay provisioned, or be `deprovision`ed. In the latter case, we set `gasprice` to 0, which induces a provision of 0. All code calling `dirtyDeleteOffer` with `deprovision` set to `true` must be careful to correctly account for where that provision is going (back to the maker's `balanceOf`, or sent to a taker as compensation). */
  function dirtyDeleteOffer(
    OfferData storage offerData,
    MgvStructs.OfferPacked offer,
    MgvStructs.OfferDetailPacked offerDetail,
    bool deprovision
  ) internal {
    unchecked {
      offer = offer.gives(0);
      if (deprovision) {
        offerDetail = offerDetail.gasprice(0);
      }
      offerData.offer = offer;
      offerData.detail = offerDetail;
    }
  }

  /* ## Stitching the orderbook */

  /* Connect the offers `betterId` and `worseId` through their `next`/`prev` pointers. For more on the book structure, see [`structs.js`](#structs.js). Used after executing an offer (or a segment of offers), after removing an offer, or moving an offer.

  **Warning**: calling with `betterId = 0` will set `worseId` as the best. So with `betterId = 0` and `worseId = 0`, it sets the book to empty and loses track of existing offers.

  **Warning**: may make memory copy of `local.best` stale. Returns new `local`. */
  function stitchOffers(Pair storage pair, uint betterId, uint worseId, MgvStructs.LocalPacked local)
    internal
    returns (MgvStructs.LocalPacked)
  {
    unchecked {
      if (betterId != 0) {
        OfferData storage offerData = pair.offerData[betterId];
        offerData.offer = offerData.offer.next(worseId);
      } else {
        local = local.best(worseId);
      }

      if (worseId != 0) {
        OfferData storage offerData = pair.offerData[worseId];
        offerData.offer = offerData.offer.prev(betterId);
      }

      return local;
    }
  }

  /* ## Check offer is live */
  /* Check whether an offer is 'live', that is: inserted in the order book. The Mangrove holds a `outbound_tkn => inbound_tkn => id => MgvStructs.OfferPacked` mapping in storage. Offer ids that are not yet assigned or that point to since-deleted offer will point to an offer with `gives` field at 0. */
  function isLive(MgvStructs.OfferPacked offer) public pure returns (bool) {
    unchecked {
      return offer.gives() > 0;
    }
  }
}
