// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {OfferDetail,OfferDetailUnpacked} from "@mgv/src/preprocessed/OfferDetail.post.sol";


/* Extra functions for the offer details */
library OfferDetailExtra {
  function offer_gasbase(OfferDetail offerDetail) internal pure returns (uint) { unchecked {
    return offerDetail.kilo_offer_gasbase() * 1e3;
  }}
  function offer_gasbase(OfferDetail offerDetail,uint val) internal pure returns (OfferDetail) { unchecked {
    return offerDetail.kilo_offer_gasbase(val/1e3);
  }}
}

/* Extra functions for the struct version of the offer details */
library OfferDetailUnpackedExtra {
  function offer_gasbase(OfferDetailUnpacked memory offerDetail) internal pure returns (uint) { unchecked {
    return offerDetail.kilo_offer_gasbase * 1e3;
  }}
  function offer_gasbase(OfferDetailUnpacked memory offerDetail,uint val) internal pure { unchecked {
    offerDetail.kilo_offer_gasbase = val/1e3;
  }}
}