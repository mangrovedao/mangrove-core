// SPDX-License-Identifier:	BSD-2-Clause

// Ghost.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";
import {MgvLib } from "mgv_src/MgvLib.sol";
import { Offer } from "mgv_src/preprocessed/MgvPack.post.sol";

contract Ghost is Direct {
  IERC20 public immutable STABLE1;
  IERC20 public immutable STABLE2;

  uint offerId1; // id of the offer on stable 1
  uint offerId2; // id of the offer on stable 2

  //         MangroveOffer <-- makerExecute
  // Forwarder          Direct <-- offer management
  // Persistent         Persistent <-- automated offer reposting <-- our entry point
  // OfferForwarder     OfferMaker <-- new offer posting

  constructor(
    IMangrove mgv,
    IERC20 stable1,
    IERC20 stable2
  ) Direct (mgv, new SimpleRouter()) {
    STABLE1 = stable1;
    STABLE2 = stable2;
  }

  /**
    @param wants1 in STABLE1 decimals
    @param wants2 in STABLE2 decimals
    @notice these offer's provision must be in msg.value
    @notice admin must have approved base for MGV transfer prior to calling this function
     */
  function newGhostOffers(
    IERC20 base,
    uint gives,
    uint wants1,
    uint wants2,
    uint pivot1,
    uint pivot2
  ) external payable onlyAdmin {
    // there is a cost of being paternalistic here, we read MGV storage
    // an offer can be in 4 states:
    // - not on mangrove (never has been)
    // - on an offer list (isLive)
    // - not on an offer list (!isLive) (and can be deprovisioned or not)
    // MGV.retractOffer(..., deprovision:bool)
    // deprovisioning an offer (via MGV.retractOffer) credits maker balance on Mangrove (no native token transfer)
    // if maker wishes to retrieve native tokens it should call MGV.withdraw (and have a positive balance)
    require(
      !MGV.isLive(MGV.offers(address(base), address(STABLE1), offerId1)),
      "Ghost/offerAlreadyActive"
    );
    require(
      !MGV.isLive(MGV.offers(address(base), address(STABLE2), offerId2)),
      "Ghost/offerAlreadyActive"
    );
    offerId1 = MGV.newOffer{value: msg.value}({
      outbound_tkn: address(base),
      inbound_tkn: address(STABLE1),
      wants: wants1,
      gives: gives,
      gasreq: offerGasreq(),
      gasprice: 0,
      pivotId: pivot1
    });
    // no need to fund this second call for provision
    // since the above call should be enough
    offerId2 = MGV.newOffer({
      outbound_tkn: address(base),
      inbound_tkn: address(STABLE2),
      wants: wants2,
      gives: gives,
      gasreq: offerGasreq(),
      gasprice: 0,
      pivotId: pivot2
    });
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    // reposts residual if any
    bytes32 repost_status = super.__posthookSuccess__(order, makerData);
    // write here what you want to do if not `reposted`
    // reasons for not ok are:
    // - residual below density (dust)
    // - not enough provision
    // - offer list is closed (governance call)
    (IERC20 alt_stable, uint alt_offerId) = IERC20(order.inbound_tkn) == STABLE1
      ? (STABLE2, offerId2)
      : (STABLE1, offerId1);

    if (repost_status == "posthook/reposted") {
      uint new_alt_gives = __residualGives__(order); // in base units
      Offer.t alt_offer = MGV.offers(
        order.outbound_tkn,
        address(alt_stable),
        alt_offerId
      );
      uint old_alt_wants = alt_offer.wants();
      // old_alt_gives is also old_gives
      uint old_alt_gives = order.offer.gives();
      // we want new_alt_wants == (old_alt_wants:96 * new_alt_gives:96)/old_alt_gives:96
      // so no overflow to be expected :)
      uint new_alt_wants;
      unchecked {
        new_alt_wants = (old_alt_wants * new_alt_gives) / old_alt_gives;
      }
      // the call below might throw
      MGV.updateOffer({
        outbound_tkn: address(order.outbound_tkn),
        inbound_tkn: address(alt_stable),
        gives: new_alt_gives,
        wants: new_alt_wants,
        offerId: alt_offerId,
        gasreq: offerGasreq(),
        pivotId: alt_offer.next(),
        gasprice: 0
      });
    } else { // repost failed or offer was entirely taken
      MGV.retractOffer({
        outbound_tkn: address(order.outbound_tkn),
        inbound_tkn: address(order.inbound_tkn),
        offerId: order.offerId,
        deprovision: true
      });
      MGV.retractOffer({
        outbound_tkn: address(order.outbound_tkn),
        inbound_tkn: address(alt_stable),
        offerId: alt_offerId,
        deprovision: true
      });
    }
    return "";
  }
}
