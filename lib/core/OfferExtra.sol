// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "@mgv/lib/core/TickTreeLib.sol";
import "@mgv/lib/core/TickLib.sol";
import {Offer,OfferUnpacked,OfferLib} from "@mgv/src/preprocessed/Offer.post.sol";


/* cleanup-mask: 0s at location of fields to hide from maker, 1s elsewhere */
uint constant HIDE_FIELDS_FROM_MAKER_MASK = ~(OfferLib.prev_mask_inv | OfferLib.next_mask_inv);

/* Extra functions for the offer */
library OfferExtra {
  /* Compute wants from tick and gives */
  function wants(Offer offer) internal pure returns (uint) {
    return offer.tick().inboundFromOutboundUp(offer.gives());
  }

  /* Sugar to test offer liveness */
  function isLive(Offer offer) internal pure returns (bool resp) {
    uint gives = offer.gives();
    assembly ("memory-safe") {
      resp := iszero(iszero(gives))
    }
  }

  /* Get the bin where the offer is stored given an offer list that has `tickSpacing` */
  function bin(Offer offer, uint tickSpacing) internal pure returns (Bin) {
    return offer.tick().nearestBin(tickSpacing);
  }

  /* Removes prev/next pointers from an offer before sending it to the maker.  Ensures that the maker has no information about the state of the book when it gets called. */
  function clearFieldsForMaker(Offer offer) internal pure returns (Offer) {
    unchecked {
      return Offer.wrap(
        Offer.unwrap(offer)
        & HIDE_FIELDS_FROM_MAKER_MASK);
    }
  }
}

/* Extra functions for the struct version of the offer */
library OfferUnpackedExtra {
  /* Compute wants from tick and gives */
  function wants(OfferUnpacked memory offer) internal pure returns (uint) {
    return offer.tick.inboundFromOutboundUp(offer.gives);
  }

  /* Sugar to test offer liveness */
  function isLive(OfferUnpacked memory offer) internal pure returns (bool resp) {
    uint gives = offer.gives;
    assembly ("memory-safe") {
      resp := iszero(iszero(gives))
    }
  }

  /* Removes prev/next pointers from an offer before sending it to the maker; Ensures that the maker has no information about the state of the book when it gets called. */
  function bin(OfferUnpacked memory offer, uint tickSpacing) internal pure returns (Bin) {
    return offer.tick.nearestBin(tickSpacing);
  }

}