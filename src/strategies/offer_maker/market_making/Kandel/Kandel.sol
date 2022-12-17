// SPDX-License-Identifier:	BSD-2-Clause

// Kandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {Direct, IMangrove, AbstractRouter, IERC20} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {MgvLib, MgvStructs} from "mgv_src/MgvLib.sol";

contract Kandel is Direct {
  ///@notice number of price offers managed by this strat
  uint16 immutable NSLOTS;
  IERC20 immutable BASE;
  IERC20 immutable QUOTE;

  uint[] quoteOfIndex;
  uint[] baseOfIndex;

  ///@notice a bid or an ask
  enum OrderType {
    Bid,
    Ask
  }

  ///@notice maps index to offer id on Mangrove
  mapping(OrderType => mapping(uint => uint)) offerIdOfIndex;

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint16 nslots) Direct(mgv, NO_ROUTER, gasreq) {
    NSLOTS = nslots;
    BASE = base;
    QUOTE = quote;
  }

  function givesOfIndex(OrderType ba, uint index) internal view returns (uint) {
    return ba == OrderType.Ask ? quoteOfIndex[index] : baseOfIndex[index];
  }

  function wantsOfIndex(OrderType ba, uint index) internal view returns (uint) {
    return ba == OrderType.Ask ? baseOfIndex[index] : quoteOfIndex[index];
  }

  function tokenPairOfOrderType(OrderType ba) internal view returns (IERC20, IERC20) {
    return ba == OrderType.Bid ? (QUOTE, BASE) : (BASE, QUOTE);
  }

  function orderTypeOfOutbound(IERC20 outbound_tkn) internal view returns (OrderType) {
    return outbound_tkn == BASE ? OrderType.Ask : OrderType.Bid;
  }

  function getOffer(OrderType ba, uint index)
    internal
    view
    returns (MgvStructs.OfferPacked, MgvStructs.OfferDetailPacked)
  {
    (IERC20 outbound_tkn, IERC20 inbound_tkn) = tokenPairOfOrderType(ba);
    return (
      MGV.offers(address(outbound_tkn), address(inbound_tkn), offerIdOfIndex[ba][index]),
      MGV.offerDetails(address(outbound_tkn), address(inbound_tkn), offerIdOfIndex[ba][index])
    );
  }

  function postOrder(OrderType ba, uint index, OfferArgs memory args) internal returns (bytes32) {
    uint offerId = offerIdOfIndex[ba][index];
    if (offerId == 0) {
      offerId = _newOffer(args);
      if (offerId == 0) {
        return "newOffer/Failed";
      } else {
        offerIdOfIndex[ba][index] = offerId;
        return REPOST_SUCCESS;
      }
    } else {
      return _updateOffer(args, offerId);
    }
  }

  function getDualOrderArgs(OrderType ba, MgvLib.SingleOrder calldata order)
    internal
    view
    returns (OrderType dualBa, uint dualIndex, OfferArgs memory args)
  {
    uint index = offerIdOfIndex[ba][order.offerId];
    (MgvStructs.OfferPacked dualOffer, MgvStructs.OfferDetailPacked dualOfferDetails) = getOffer(dualBa, dualIndex);

    (dualIndex, dualBa) = ba == OrderType.Ask ? (index - 1, OrderType.Bid) : (index + 1, OrderType.Ask);

    uint maxDualGives = dualOffer.gives() + order.gives;
    uint shouldGive = givesOfIndex(dualBa, dualIndex);
    uint shouldWant = wantsOfIndex(dualBa, dualIndex);

    args.outbound_tkn = IERC20(order.inbound_tkn);
    args.inbound_tkn = IERC20(order.outbound_tkn);
    args.gives = shouldGive > maxDualGives ? maxDualGives : shouldGive;
    args.wants = args.gives == shouldGive ? shouldWant : (maxDualGives * shouldWant) / shouldGive;
    args.fund = 0;
    args.noRevert = true;
    args.gasreq = dualOfferDetails.gasreq();
    args.gasprice = dualOfferDetails.gasprice();
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    bytes32 repostStatus = super.__posthookSuccess__(order, makerData);
    // Offer failed to repost for bad reason, loggin incident
    if (
      repostStatus != "posthook/filled" || repostStatus != REPOST_SUCCESS
        || repostStatus != "mgv/writeOffer/density/tooLow"
    ) {
      emit LogIncident(
        MGV, IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId, makerData, repostStatus
        );
    }
    OrderType ba = orderTypeOfOutbound(IERC20(order.outbound_tkn));
    // preparing arguments for the dual maker order
    (OrderType ba_, uint index_, OfferArgs memory args) = getDualOrderArgs(ba, order);
    return postOrder(ba_, index_, args);
  }
}
