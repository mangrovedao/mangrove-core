// SPDX-License-Identifier:	BSD-2-Clause

// Amplifier.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import "mgv_src/strategies/offer_forwarder/abstract/Forwarder.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";
import {MgvLib, MgvStructs} from "mgv_src/MgvLib.sol";

contract AmplifierForwarder is Forwarder {
  IERC20 public immutable BASE;
  IERC20 public immutable STABLE1;
  IERC20 public immutable STABLE2;

  struct OfferPair {
    uint id1;
    uint id2;
  }

  mapping(address => OfferPair) offers; // mapping from maker address to id of the offers

  constructor(IMangrove mgv, IERC20 base, IERC20 stable1, IERC20 stable2, address deployer, uint gasreq)
    Forwarder(mgv, new SimpleRouter(), gasreq)
  {
    // SimpleRouter takes promised liquidity from admin's address (wallet)
    STABLE1 = stable1;
    STABLE2 = stable2;
    BASE = base;

    AbstractRouter router_ = router();
    router_.bind(address(this));
    if (deployer != msg.sender) {
      setAdmin(deployer);
      router_.setAdmin(deployer);
    }
  }

  /**
   * @param gives in BASE decimals
   * @param wants1 in STABLE1 decimals
   * @param wants2 in STABLE2 decimals
   * @param pivot1 pivot for STABLE1
   * @param pivot2 pivot for STABLE2
   * @return (offerid for STABLE1, offerid for STABLE2)
   * @dev these offer's provision must be in msg.value
   * @dev `reserve()` must have approved base for `this` contract transfer prior to calling this function
   */
  function newAmplifiedOffers(
    // this function posts two asks
    uint gives,
    uint wants1,
    uint wants2,
    uint pivot1,
    uint pivot2,
    uint fund1,
    uint fund2
  ) external payable returns (uint, uint) {
    // there is a cost of being paternalistic here, we read MGV storage
    // an offer can be in 4 states:
    // - not on mangrove (never has been)
    // - on an offer list (isLive)
    // - not on an offer list (!isLive) (and can be deprovisioned or not)
    // MGV.retractOffer(..., deprovision:bool)
    // deprovisioning an offer (via MGV.retractOffer) credits maker balance on Mangrove (no native token transfer)
    // if maker wishes to retrieve native tokens it should call MGV.withdraw (and have a positive balance)
    OfferPair memory offerPair = offers[msg.sender];

    require(
      !MGV.isLive(MGV.offers(address(BASE), address(STABLE1), offerPair.id1)), "AmplifierForwarder/offer1AlreadyActive"
    );
    require(
      !MGV.isLive(MGV.offers(address(BASE), address(STABLE2), offerPair.id2)), "AmplifierForwarder/offer2AlreadyActive"
    );
    // FIXME the above requirements are not enough because offerId might be live on another base, stable market

    uint _offerId1 = _newOffer(
      OfferArgs({
        outbound_tkn: BASE,
        inbound_tkn: STABLE1,
        wants: wants1,
        gives: gives,
        gasreq: offerGasreq(),
        gasprice: 0, // ignored
        pivotId: pivot1,
        fund: fund1,
        noRevert: false,
        owner: msg.sender
      })
    );

    offers[msg.sender].id1 = _offerId1;
    // no need to fund this second call for provision
    // since the above call should be enough
    uint _offerId2 = _newOffer(
      OfferArgs({
        outbound_tkn: BASE,
        inbound_tkn: STABLE2,
        wants: wants2,
        gives: gives,
        gasreq: offerGasreq(),
        gasprice: 0, // ignored
        pivotId: pivot2,
        fund: fund2,
        noRevert: false,
        owner: msg.sender
      })
    );
    offers[msg.sender].id2 = _offerId2;

    require(_offerId1 != 0, "AmplifierForwarder/newOffer1Failed");
    require(_offerId2 != 0, "AmplifierForwarder/newOffer2Failed");

    return (_offerId1, _offerId2);
  }

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
    // Get the owner of the order. That is the same owner as the alt offer
    address owner = ownerOf(IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId);
    OfferPair memory offerPair = offers[owner];
    (IERC20 alt_stable, uint alt_offerId) =
      IERC20(order.inbound_tkn) == STABLE1 ? (STABLE2, offerPair.id2) : (STABLE1, offerPair.id1);

    if (repost_status == "posthook/reposted") {
      uint new_alt_gives = __residualGives__(order); // in base units
      MgvStructs.OfferPacked alt_offer = MGV.offers(order.outbound_tkn, address(alt_stable), alt_offerId);

      uint new_alt_wants;
      unchecked {
        new_alt_wants = (alt_offer.wants() * new_alt_gives) / order.offer.gives();
      }

      //uint prov = getMissingProvision(IERC20(order.outbound_tkn), IERC20(alt_stable), type(uint).max, 0, 0);

      uint id = _updateOffer(
        OfferArgs({
          outbound_tkn: IERC20(order.outbound_tkn),
          inbound_tkn: IERC20(alt_stable),
          wants: new_alt_wants,
          gives: new_alt_gives,
          gasreq: type(uint).max, // to use alt_offer's old gasreq
          gasprice: 0, // ignored
          pivotId: alt_offer.next(),
          noRevert: true,
          fund: 0,
          owner: owner
        }),
        alt_offerId
      );
      if (id == 0) {
        // might want to Log an incident here because this should not be reachable
        return "posthook/altRepostFail";
      } else {
        return "posthook/bothOfferReposted";
      }
    } else {
      // repost failed or offer was entirely taken
      if (repost_status != "posthook/filled") {
        retractOffer({
          outbound_tkn: IERC20(order.outbound_tkn),
          inbound_tkn: IERC20(order.inbound_tkn),
          offerId: order.offerId,
          deprovision: false
        });
      }
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
    OfferPair memory offerPair = offers[msg.sender];
    retractOffer({outbound_tkn: BASE, inbound_tkn: STABLE1, offerId: offerPair.id1, deprovision: deprovision});
    retractOffer({outbound_tkn: BASE, inbound_tkn: STABLE2, offerId: offerPair.id2, deprovision: deprovision});
  }

  function __posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata)
    internal
    override
    returns (bytes32)
  {
    // Get the owner of the order. That is the same owner as the alt offer
    address owner = ownerOf(IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId);
    // if we reach this code, trade has failed for lack of base token
    OfferPair memory offerPair = offers[owner];
    (IERC20 alt_stable, uint alt_offerId) =
      IERC20(order.inbound_tkn) == STABLE1 ? (STABLE2, offerPair.id2) : (STABLE1, offerPair.id1);
    retractOffer({
      outbound_tkn: IERC20(order.outbound_tkn),
      inbound_tkn: IERC20(alt_stable),
      offerId: alt_offerId,
      deprovision: false
    });
    return "posthook/bothFailing";
  }
}
