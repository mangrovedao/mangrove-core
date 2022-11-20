// SPDX-License-Identifier:	BSD-2-Clause

// Amplifier.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

pragma abicoder v2;

import "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";
import {MgvLib, MgvStructs} from "mgv_src/MgvLib.sol";

contract Amplifier is Direct {
  IERC20 public immutable BASE;
  IERC20 public immutable STABLE1;
  IERC20 public immutable STABLE2;

  ///mapping(IERC20 => mapping(IERC20 => uint)) // base -> stable -> offerid

  uint offerId1; // id of the offer on stable 1
  uint offerId2; // id of the offer on stable 2

  //           MangroveOffer <-- makerExecute
  //                  /\
  //                 / \
  //        Forwarder  Direct <-- offer management (our entry point)
  //    OfferForwarder  OfferMaker <-- new offer posting

  constructor(IMangrove mgv, IERC20 base, IERC20 stable1, IERC20 stable2, address admin)
    Direct(mgv, NO_ROUTER, 100_000)
  {
    // SimpleRouter takes promised liquidity from admin's address (wallet)
    STABLE1 = stable1;
    STABLE2 = stable2;
    BASE = base;
    AbstractRouter router_ = new SimpleRouter();
    setRouter(router_);
    // adding `this` to the allowed makers of `router_` to pull/push liquidity
    // Note: `reserve(admin)` needs to approve `this.router()` for base token transfer
    router_.bind(address(this));
    router_.setAdmin(admin);
    setAdmin(admin);
  }

  /**
   * @param gives in BASE decimals
   * @param wants1 in STABLE1 decimals
   * @param wants2 in STABLE2 decimals
   * @param pivot1 pivot for STABLE1
   * @param pivot2 pivot for STABLE2
   * @return (offerid for STABLE1, offerid for STABLE2)
   * @dev these offer's provision must be in msg.value
   * @dev `reserve(admin())` must have approved base for `this` contract transfer prior to calling this function
   */
  function newAmplifiedOffers(
    // this function posts two asks
    uint gives,
    uint wants1,
    uint wants2,
    uint pivot1,
    uint pivot2
  ) external payable onlyAdmin returns (uint, uint) {
    // there is a cost of being paternalistic here, we read MGV storage
    // an offer can be in 4 states:
    // - not on mangrove (never has been)
    // - on an offer list (isLive)
    // - not on an offer list (!isLive) (and can be deprovisioned or not)
    // MGV.retractOffer(..., deprovision:bool)
    // deprovisioning an offer (via MGV.retractOffer) credits maker balance on Mangrove (no native token transfer)
    // if maker wishes to retrieve native tokens it should call MGV.withdraw (and have a positive balance)
    require(!MGV.isLive(MGV.offers(address(BASE), address(STABLE1), offerId1)), "Amplifier/offer1AlreadyActive");
    require(!MGV.isLive(MGV.offers(address(BASE), address(STABLE2), offerId2)), "Amplifier/offer2AlreadyActive");
    // FIXME the above requirements are not enough because offerId might be live on another base, stable market

    offerId1 = _newOffer(
      OfferArgs({
        outbound_tkn: BASE,
        inbound_tkn: STABLE1,
        wants: wants1,
        gives: gives,
        gasreq: offerGasreq(),
        gasprice: 0,
        pivotId: pivot1,
        fund: msg.value,
        noRevert: false,
        owner: msg.sender
      })
    );
    // no need to fund this second call for provision
    // since the above call should be enough
    offerId2 = _newOffer(
      OfferArgs({
        outbound_tkn: BASE,
        inbound_tkn: STABLE2,
        wants: wants2,
        gives: gives,
        gasreq: offerGasreq(),
        gasprice: 0,
        pivotId: pivot2,
        fund: 0,
        noRevert: false,
        owner: msg.sender
      })
    );

    return (offerId1, offerId2);
  }

  ///FIXME a possibility is to update the alt offer during makerExecute
  /// to do this we can override `__lastLook__` which is a hook called at the beginning of `makerExecute`

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    // reposts residual if any (conservative hook)
    bytes32 repost_status = super.__posthookSuccess__(order, makerData);
    // write here what you want to do if not `reposted`
    // reasons for not ok are:
    // - residual below density (dust)
    // - not enough provision
    // - offer list is closed (governance call)
    (IERC20 alt_stable, uint alt_offerId) =
      IERC20(order.inbound_tkn) == STABLE1 ? (STABLE2, offerId2) : (STABLE1, offerId1);

    if (repost_status == "posthook/reposted") {
      uint new_alt_gives = __residualGives__(order); // in base units
      MgvStructs.OfferPacked alt_offer = MGV.offers(order.outbound_tkn, address(alt_stable), alt_offerId);
      MgvStructs.OfferDetailPacked alt_detail = MGV.offerDetails(order.outbound_tkn, address(alt_stable), alt_offerId);

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
      updateOffer({
        outbound_tkn: IERC20(order.outbound_tkn),
        inbound_tkn: IERC20(alt_stable),
        gives: new_alt_gives,
        wants: new_alt_wants,
        offerId: alt_offerId,
        gasreq: alt_detail.gasreq(),
        pivotId: alt_offer.next(),
        gasprice: 0
      });
      return "posthook/bothOfferReposted";
    } else {
      // repost failed or offer was entirely taken
      retractOffer({
        outbound_tkn: IERC20(order.outbound_tkn),
        inbound_tkn: IERC20(alt_stable),
        offerId: alt_offerId,
        deprovision: false
      });
      return "posthook/bothRetracted";
    }
  }

  function retractOffers(bool deprovision) public {
    retractOffer({outbound_tkn: BASE, inbound_tkn: STABLE1, offerId: offerId1, deprovision: deprovision});
    retractOffer({outbound_tkn: BASE, inbound_tkn: STABLE2, offerId: offerId2, deprovision: deprovision});
  }

  function __posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata)
    internal
    override
    returns (bytes32)
  {
    // if we reach this code, trade has failed for lack of base token
    (IERC20 alt_stable, uint alt_offerId) =
      IERC20(order.inbound_tkn) == STABLE1 ? (STABLE2, offerId2) : (STABLE1, offerId1);
    retractOffer({
      outbound_tkn: IERC20(order.outbound_tkn),
      inbound_tkn: IERC20(alt_stable),
      offerId: alt_offerId,
      deprovision: false
    });
    return "posthook/bothFailing";
  }
}
