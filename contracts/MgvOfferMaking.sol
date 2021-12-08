// SPDX-License-Identifier:	AGPL-3.0

// MgvOfferMaking.sol

// Copyright (C) 2021 Giry SAS.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.10;
pragma abicoder v2;
import {IMaker, HasMgvEvents, P} from "./MgvLib.sol";
import {MgvHasOffers} from "./MgvHasOffers.sol";

/* `MgvOfferMaking` contains market-making-related functions. */
contract MgvOfferMaking is MgvHasOffers {
  using P.Offer for P.Offer.t;
  using P.OfferDetail for P.OfferDetail.t;
  using P.Global for P.Global.t;
  using P.Local for P.Local.t;
  /* # Public Maker operations
     ## New Offer */
  //+clear+
  /* In the Mangrove, makers and takers call separate functions. Market makers call `newOffer` to fill the book, and takers call functions such as `marketOrder` to consume it.  */

  //+clear+

  /* The following structs holds offer creation/update parameters in memory. This frees up stack space for local variables. */
  struct OfferPack {
    address outbound_tkn;
    address inbound_tkn;
    uint wants;
    uint gives;
    uint id;
    uint gasreq;
    uint gasprice;
    uint pivotId;
    P.Global.t global;
    P.Local.t local;
    // used on update only
    P.Offer.t oldOffer;
  }

  /* The function `newOffer` is for market makers only; no match with the existing book is done. A maker specifies how much `inbound_tkn` it `wants` and how much `outbound_tkn` it `gives`.

     It also specify with `gasreq` how much gas should be given when executing their offer.

     `gasprice` indicates an upper bound on the gasprice at which the maker is ready to be penalised if their offer fails. Any value below the Mangrove's internal `gasprice` configuration value will be ignored.

    `gasreq`, together with `gasprice`, will contribute to determining the penalty provision set aside by the Mangrove from the market maker's `balanceOf` balance.

  Offers are always inserted at the correct place in the book. This requires walking through offers to find the correct insertion point. As in [Oasis](https://github.com/daifoundation/maker-otc/blob/f2060c5fe12fe3da71ac98e8f6acc06bca3698f5/src/matching_market.sol#L493), the maker should find the id of an offer close to its own and provide it as `pivotId`.

  An offer cannot be inserted in a closed market, nor when a reentrancy lock for `outbound_tkn`,`inbound_tkn` is on.

  No more than $2^{24}-1$ offers can ever be created for one `outbound_tkn`,`inbound_tkn` pair.

  The actual contents of the function is in `writeOffer`, which is called by both `newOffer` and `updateOffer`.
  */
  function newOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) external returns (uint) { unchecked {
    /* In preparation for calling `writeOffer`, we read the `outbound_tkn`,`inbound_tkn` pair configuration, check for reentrancy and market liveness, fill the `OfferPack` struct and increment the `outbound_tkn`,`inbound_tkn` pair's `last`. */
    OfferPack memory ofp;
    (ofp.global, ofp.local) = config(outbound_tkn, inbound_tkn);
    unlockedMarketOnly(ofp.local);
    activeMarketOnly(ofp.global, ofp.local);

    ofp.id = 1 + ofp.local.last();
    require(uint32(ofp.id) == ofp.id, "mgv/offerIdOverflow");

    ofp.local = ofp.local.last(ofp.id);

    ofp.outbound_tkn = outbound_tkn;
    ofp.inbound_tkn = inbound_tkn;
    ofp.wants = wants;
    ofp.gives = gives;
    ofp.gasreq = gasreq;
    ofp.gasprice = gasprice;
    ofp.pivotId = pivotId;

    /* The second parameter to writeOffer indicates that we are creating a new offer, not updating an existing one. */
    writeOffer(ofp, false);

    /* Since we locally modified a field of the local configuration (`last`), we save the change to storage. Note that `writeOffer` may have further modified the local configuration by updating the current `best` offer. */
    locals[ofp.outbound_tkn][ofp.inbound_tkn] = ofp.local;
    return ofp.id;
  }}

  /* ## Update Offer */
  //+clear+
  /* Very similar to `newOffer`, `updateOffer` prepares an `OfferPack` for `writeOffer`. Makers should use it for updating live offers, but also to save on gas by reusing old, already consumed offers.

     A `pivotId` should still be given to minimise reads in the offer book. It is OK to give the offers' own id as a pivot.


     Gas use is minimal when:
     1. The offer does not move in the book
     2. The offer does not change its `gasreq`
     3. The (`outbound_tkn`,`inbound_tkn`)'s `*_gasbase` has not changed since the offer was last written
     4. `gasprice` has not changed since the offer was last written
     5. `gasprice` is greater than the Mangrove's gasprice estimation
  */
  function updateOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) external { unchecked {
    OfferPack memory ofp;
    (ofp.global, ofp.local) = config(outbound_tkn, inbound_tkn);
    unlockedMarketOnly(ofp.local);
    activeMarketOnly(ofp.global, ofp.local);
    ofp.outbound_tkn = outbound_tkn;
    ofp.inbound_tkn = inbound_tkn;
    ofp.wants = wants;
    ofp.gives = gives;
    ofp.id = offerId;
    ofp.gasreq = gasreq;
    ofp.gasprice = gasprice;
    ofp.pivotId = pivotId;
    ofp.oldOffer = offers[outbound_tkn][inbound_tkn][offerId];
    // Save local config
    P.Local.t oldLocal = ofp.local;
    /* The second argument indicates that we are updating an existing offer, not creating a new one. */
    writeOffer(ofp, true);
    /* We saved the current pair's configuration before calling `writeOffer`, since that function may update the current `best` offer. We now check for any change to the configuration and update it if needed. */
    if (!oldLocal.eq(ofp.local)) {
      locals[ofp.outbound_tkn][ofp.inbound_tkn] = ofp.local;
    }
  }}

  /* ## Retract Offer */
  //+clear+
  /* `retractOffer` takes the offer `offerId` out of the book. However, `deprovision == true` also refunds the provision associated with the offer. */
  function retractOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId,
    bool deprovision
  ) external returns (uint provision) { unchecked {
    (, P.Local.t local) = config(outbound_tkn, inbound_tkn);
    unlockedMarketOnly(local);
    P.Offer.t offer = offers[outbound_tkn][inbound_tkn][offerId];
    P.OfferDetail.t offerDetail = offerDetails[outbound_tkn][inbound_tkn][offerId];
    require(
      msg.sender == offerDetail.maker(),
      "mgv/retractOffer/unauthorized"
    );

    /* Here, we are about to un-live an offer, so we start by taking it out of the book by stitching together its previous and next offers. Note that unconditionally calling `stitchOffers` would break the book since it would connect offers that may have since moved. */
    if (isLive(offer)) {
      P.Local.t oldLocal = local;
      local = stitchOffers(
        outbound_tkn,
        inbound_tkn,
        offer.prev(),
        offer.next(),
        local
      );
      /* If calling `stitchOffers` has changed the current `best` offer, we update the storage. */
      if (!oldLocal.eq(local)) {
        locals[outbound_tkn][inbound_tkn] = local;
      }
    }
    /* Set `gives` to 0. Moreover, the last argument depends on whether the user wishes to get their provision back (if true, `gasprice` will be set to 0 as well). */
    dirtyDeleteOffer(
      outbound_tkn,
      inbound_tkn,
      offerId,
      offer,
      offerDetail,
      deprovision
    );

    /* If the user wants to get their provision back, we compute its provision from the offer's `gasprice`, `*_gasbase` and `gasreq`. */
    if (deprovision) {
      provision =
        10**9 *
        offerDetail.gasprice() * //gasprice is 0 if offer was deprovisioned
        (offerDetail.gasreq() +
          offerDetail.overhead_gasbase() + offerDetail.offer_gasbase());
      // credit `balanceOf` and log transfer
      creditWei(msg.sender, provision);
    }
    emit OfferRetract(outbound_tkn, inbound_tkn, offerId);
  }}

  /* ## Provisioning
  Market makers must have enough provisions for possible penalties. These provisions are in ETH. Every time a new offer is created or an offer is updated, `balanceOf` is adjusted to provision the offer's maximum possible penalty (`gasprice * (gasreq + overhead_gasbase + offer_gasbase)`).

  For instance, if the current `balanceOf` of a maker is 1 ether and they create an offer that requires a provision of 0.01 ethers, their `balanceOf` will be reduced to 0.99 ethers. No ethers will move; this is just an internal accounting movement to make sure the maker cannot `withdraw` the provisioned amounts.

  */
  //+clear+

  /* Fund should be called with a nonzero value (hence the `payable` modifier). The provision will be given to `maker`, not `msg.sender`. */
  function fund(address maker) public payable { unchecked {
    (P.Global.t _global, ) = config(address(0), address(0));
    liveMgvOnly(_global);
    creditWei(maker, msg.value);
  }}

  function fund() external payable { unchecked {
    fund(msg.sender);
  }}

  /* A transfer with enough gas to the Mangrove will increase the caller's available `balanceOf` balance. _You should send enough gas to execute this function when sending money to the Mangrove._  */
  receive() external payable { unchecked {
    fund(msg.sender);
  }}

  /* Any provision not currently held to secure an offer's possible penalty is available for withdrawal. */
  function withdraw(uint amount) external returns (bool noRevert) { unchecked {
    /* Since we only ever send money to the caller, we do not need to provide any particular amount of gas, the caller should manage this herself. */
    debitWei(msg.sender, amount);
    (noRevert, ) = msg.sender.call{value: amount}("");
  }}

  /* # Low-level Maker functions */

  /* ## Write Offer */

  function writeOffer(OfferPack memory ofp, bool update) internal { unchecked {
    /* `gasprice`'s floor is Mangrove's own gasprice estimate, `ofp.global.gasprice`. We first check that gasprice fits in 16 bits. Otherwise it could be that `uint16(gasprice) < global_gasprice < gasprice`, and the actual value we store is `uint16(gasprice)`. */
    require(
      uint16(ofp.gasprice) == ofp.gasprice,
      "mgv/writeOffer/gasprice/16bits"
    );

    if (ofp.gasprice < ofp.global.gasprice()) {
      ofp.gasprice = ofp.global.gasprice();
    }

    /* * Check `gasreq` below limit. Implies `gasreq` at most 24 bits wide, which ensures no overflow in computation of `provision` (see below). */
    require(
      ofp.gasreq <= ofp.global.gasmax(),
      "mgv/writeOffer/gasreq/tooHigh"
    );
    /* * Make sure `gives > 0` -- division by 0 would throw in several places otherwise, and `isLive` relies on it. */
    require(ofp.gives > 0, "mgv/writeOffer/gives/tooLow");
    /* * Make sure that the maker is posting a 'dense enough' offer: the ratio of `outbound_tkn` offered per gas consumed must be high enough. The actual gas cost paid by the taker is overapproximated by adding `offer_gasbase` to `gasreq`. */
    require(
      ofp.gives >=
        (ofp.gasreq + ofp.local.offer_gasbase()) * ofp.local.density(),
      "mgv/writeOffer/density/tooLow"
    );

    /* The following checks are for the maker's convenience only. */
    require(uint96(ofp.gives) == ofp.gives, "mgv/writeOffer/gives/96bits");
    require(uint96(ofp.wants) == ofp.wants, "mgv/writeOffer/wants/96bits");

    /* The position of the new or updated offer is found using `findPosition`. If the offer is the best one, `prev == 0`, and if it's the last in the book, `next == 0`.

       `findPosition` is only ever called here, but exists as a separate function to make the code easier to read.

    **Warning**: `findPosition` will call `better`, which may read the offer's `offerDetails`. So it is important to find the offer position _before_ we update its `offerDetail` in storage. We waste 1 (hot) read in that case but we deem that the code would get too ugly if we passed the old `offerDetail` as argument to `findPosition` and to `better`, just to save 1 hot read in that specific case.  */
    (uint prev, uint next) = findPosition(ofp);

    /* Log the write offer event. */
    emit OfferWrite(
      ofp.outbound_tkn,
      ofp.inbound_tkn,
      msg.sender,
      ofp.wants,
      ofp.gives,
      ofp.gasprice,
      ofp.gasreq,
      ofp.id,
      prev
    );

    /* We now write the new `offerDetails` and remember the previous provision (0 by default, for new offers) to balance out maker's `balanceOf`. */
    uint oldProvision;
    {
      P.OfferDetail.t offerDetail = offerDetails[ofp.outbound_tkn][ofp.inbound_tkn][
        ofp.id
      ];
      if (update) {
        require(
          msg.sender == offerDetail.maker(),
          "mgv/updateOffer/unauthorized"
        );
        oldProvision =
          10**9 *
          offerDetail.gasprice() *
          (offerDetail.gasreq() +
            offerDetail.overhead_gasbase() +
            offerDetail.offer_gasbase());
      }

      /* If the offer is new, has a new `gasprice`, `gasreq`, or if the Mangrove's `*_gasbase` configuration parameter has changed, we also update `offerDetails`. */
      if (
        !update ||
        offerDetail.gasreq() != ofp.gasreq ||
        offerDetail.gasprice() != ofp.gasprice ||
        offerDetail.overhead_gasbase() !=
        ofp.local.overhead_gasbase() ||
        offerDetail.offer_gasbase() !=
        ofp.local.offer_gasbase()
      ) {
        uint overhead_gasbase = ofp.local.overhead_gasbase();
        uint offer_gasbase = ofp.local.offer_gasbase();
        offerDetails[ofp.outbound_tkn][ofp.inbound_tkn][ofp.id] = 
        P.OfferDetail.pack({
          __maker: msg.sender,
          __gasreq: ofp.gasreq,
          __overhead_gasbase: overhead_gasbase,
          __offer_gasbase: offer_gasbase,
          __gasprice: ofp.gasprice
        });
      }
    }

    /* With every change to an offer, a maker may deduct provisions from its `balanceOf` balance. It may also get provisions back if the updated offer requires fewer provisions than before. */
    {
      uint provision = (ofp.gasreq +
        ofp.local.offer_gasbase() +
        ofp.local.overhead_gasbase()) *
        ofp.gasprice *
        10**9;
      if (provision > oldProvision) {
        debitWei(msg.sender, provision - oldProvision);
      } else if (provision < oldProvision) {
        creditWei(msg.sender, oldProvision - provision);
      }
    }
    /* We now place the offer in the book at the position found by `findPosition`. */

    /* First, we test if the offer has moved in the book or is not currently in the book. If `!isLive(ofp.oldOffer)`, we must update its prev/next. If it is live but its prev has changed, we must also update them. Note that checking both `prev = oldPrev` and `next == oldNext` would be redundant. If either is true, then the updated offer has not changed position and there is nothing to update.

    As a note for future changes, there is a tricky edge case where `prev == oldPrev` yet the prev/next should be changed: a previously-used offer being brought back in the book, and ending with the same prev it had when it was in the book. In that case, the neighbor is currently pointing to _another_ offer, and thus must be updated. With the current code structure, this is taken care of as a side-effect of checking `!isLive`, but should be kept in mind. The same goes in the `next == oldNext` case. */
    if (!isLive(ofp.oldOffer) || prev != ofp.oldOffer.prev()) {
      /* * If the offer is not the best one, we update its predecessor; otherwise we update the `best` value. */
      if (prev != 0) {
        offers[ofp.outbound_tkn][ofp.inbound_tkn][prev] = offers[ofp.outbound_tkn][ofp.inbound_tkn][prev].next(ofp.id);
      } else {
        ofp.local = ofp.local.best(ofp.id);
      }

      /* * If the offer is not the last one, we update its successor. */
      if (next != 0) {
        offers[ofp.outbound_tkn][ofp.inbound_tkn][next] = offers[ofp.outbound_tkn][ofp.inbound_tkn][next].prev(ofp.id);
      }

      /* * Recall that in this branch, the offer has changed location, or is not currently in the book. If the offer is not new and already in the book, we must remove it from its previous location by stitching its previous prev/next. */
      if (update && isLive(ofp.oldOffer)) {
        ofp.local = stitchOffers(
          ofp.outbound_tkn,
          ofp.inbound_tkn,
          ofp.oldOffer.prev(),
          ofp.oldOffer.next(),
          ofp.local
        );
      }
    }

    /* With the `prev`/`next` in hand, we finally store the offer in the `offers` map. */
    P.Offer.t ofr = P.Offer.pack({
      __prev: prev,
      __next: next,
      __wants: ofp.wants,
      __gives: ofp.gives
    });
    offers[ofp.outbound_tkn][ofp.inbound_tkn][ofp.id] = ofr;
  }}

  /* ## Find Position */
  /* `findPosition` takes a price in the form of a (`ofp.wants`,`ofp.gives`) pair, an offer id (`ofp.pivotId`) and walks the book from that offer (backward or forward) until the right position for the price is found. The position is returned as a `(prev,next)` pair, with `prev` or `next` at 0 to mark the beginning/end of the book (no offer ever has id 0).

  If prices are equal, `findPosition` will put the newest offer last. */
  function findPosition(OfferPack memory ofp)
    internal
    view
    returns (uint, uint)
  { unchecked {
    uint prevId;
    uint nextId;
    uint pivotId = ofp.pivotId;
    /* Get `pivot`, optimizing for the case where pivot info is already known */
    P.Offer.t pivot = pivotId == ofp.id
      ? ofp.oldOffer
      : offers[ofp.outbound_tkn][ofp.inbound_tkn][pivotId];

    /* In case pivotId is not an active offer, it is unusable (since it is out of the book). We default to the current best offer. If the book is empty pivot will be 0. That is handled through a test in the `better` comparison function. */
    if (!isLive(pivot)) {
      pivotId = ofp.local.best();
      pivot = offers[ofp.outbound_tkn][ofp.inbound_tkn][pivotId];
    }

    /* * Pivot is better than `wants/gives`, we follow `next`. */
    if (better(ofp, pivot, pivotId)) {
      P.Offer.t pivotNext;
      while (pivot.next() != 0) {
        uint pivotNextId = pivot.next();
        pivotNext = offers[ofp.outbound_tkn][ofp.inbound_tkn][pivotNextId];
        if (better(ofp, pivotNext, pivotNextId)) {
          pivotId = pivotNextId;
          pivot = pivotNext;
        } else {
          break;
        }
      }
      // gets here on empty book
      (prevId, nextId) = (pivotId, pivot.next());

      /* * Pivot is strictly worse than `wants/gives`, we follow `prev`. */
    } else {
      P.Offer.t pivotPrev;
      while (pivot.prev() != 0) {
        uint pivotPrevId = pivot.prev();
        pivotPrev = offers[ofp.outbound_tkn][ofp.inbound_tkn][pivotPrevId];
        if (better(ofp, pivotPrev, pivotPrevId)) {
          break;
        } else {
          pivotId = pivotPrevId;
          pivot = pivotPrev;
        }
      }

      (prevId, nextId) = (pivot.prev(), pivotId);
    }

    return (
      prevId == ofp.id ? ofp.oldOffer.prev() : prevId,
      nextId == ofp.id ? ofp.oldOffer.next() : nextId
    );
  }}

  /* ## Better */
  /* The utility method `better` takes an offer represented by `ofp` and another represented by `offer1`. It returns true iff `offer1` is better or as good as `ofp`.
    "better" is defined on the lexicographic order $\textrm{price} \times_{\textrm{lex}} \textrm{density}^{-1}$. This means that for the same price, offers that deliver more volume per gas are taken first.

      In addition to `offer1`, we also provide its id, `offerId1` in order to save gas. If necessary (ie. if the prices `wants1/gives1` and `wants2/gives2` are the same), we read storage to get `gasreq1` at `offerDetails[...][offerId1]. */
  function better(
    OfferPack memory ofp,
    P.Offer.t offer1,
    uint offerId1
  ) internal view returns (bool) { unchecked {
    if (offerId1 == 0) {
      /* Happens on empty book. Returning `false` would work as well due to specifics of `findPosition` but true is more consistent. Here we just want to avoid reading `offerDetail[...][0]` for nothing. */
      return true;
    }
    uint wants1 = offer1.wants();
    uint gives1 = offer1.gives();
    uint wants2 = ofp.wants;
    uint gives2 = ofp.gives;
    uint weight1 = wants1 * gives2;
    uint weight2 = wants2 * gives1;
    if (weight1 == weight2) {
      uint gasreq1 = 
          offerDetails[ofp.outbound_tkn][ofp.inbound_tkn][offerId1].gasreq();
      uint gasreq2 = ofp.gasreq;
      return (gives1 * gasreq2 >= gives2 * gasreq1);
    } else {
      return weight1 < weight2;
    }
  }}
}
