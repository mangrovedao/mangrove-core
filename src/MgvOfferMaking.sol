// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {IMaker, HasMgvEvents, MgvStructs, Tick, TickLib, Leaf, Field} from "./MgvLib.sol";
import {MgvHasOffers} from "./MgvHasOffers.sol";

/* `MgvOfferMaking` contains market-making-related functions. */
contract MgvOfferMaking is MgvHasOffers {
  /* # Public Maker operations
     ## New Offer */
  //+clear+
  /* In Mangrove, makers and takers call separate functions. Market makers call `newOffer` to fill the book, and takers call functions such as `marketOrder` to consume it.  */

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
    MgvStructs.GlobalPacked global;
    MgvStructs.LocalPacked local;
    // used on update only
    MgvStructs.OfferPacked oldOffer;
  }

  /* The function `newOffer` is for market makers only; no match with the existing book is done. A maker specifies how much `inbound_tkn` it `wants` and how much `outbound_tkn` it `gives`.

     It also specify with `gasreq` how much gas should be given when executing their offer.

     `gasprice` indicates an upper bound on the gasprice at which the maker is ready to be penalised if their offer fails. Any value below Mangrove's internal `gasprice` configuration value will be ignored.

    `gasreq`, together with `gasprice`, will contribute to determining the penalty provision set aside by Mangrove from the market maker's `balanceOf` balance.

  An offer cannot be inserted in a closed market, nor when a reentrancy lock for `outbound_tkn`,`inbound_tkn` is on.

  No more than $2^{32}-1$ offers can ever be created for one `outbound_tkn`,`inbound_tkn` pair.

  The actual contents of the function is in `writeOffer`, which is called by both `newOffer` and `updateOffer`.
  */
  function newOffer(address outbound_tkn, address inbound_tkn, uint wants, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint)
  {
    unchecked {
      /* In preparation for calling `writeOffer`, we read the `outbound_tkn`,`inbound_tkn` pair configuration, check for reentrancy and market liveness, fill the `OfferPack` struct and increment the `outbound_tkn`,`inbound_tkn` pair's `last`. */
      OfferPack memory ofp;
      Pair storage pair;
      (ofp.global, ofp.local, pair) = _config(outbound_tkn, inbound_tkn);
      unlockedMarketOnly(ofp.local);
      activeMarketOnly(ofp.global, ofp.local);
      if (msg.value > 0) {
        creditWei(msg.sender, msg.value);
      }
      // TODO this resolve to memory instead of a stackvalue
      // Need a parametric function to get the nth tickleaf
      // ofp.tickleaf = pair.leafs[tick. ..] tickleaf;

      ofp.id = 1 + ofp.local.last();
      require(uint32(ofp.id) == ofp.id, "mgv/offerIdOverflow");

      ofp.local = ofp.local.last(ofp.id);

      ofp.outbound_tkn = outbound_tkn;
      ofp.inbound_tkn = inbound_tkn;
      ofp.wants = wants;
      ofp.gives = gives;
      ofp.gasreq = gasreq;
      ofp.gasprice = gasprice;

      /* The second parameter to writeOffer indicates that we are creating a new offer, not updating an existing one. */
      writeOffer(pair, ofp, false);

      /* Since we locally modified a field of the local configuration (`last`), we save the change to storage. Note that `writeOffer` may have further modified the local configuration by updating the current `best` offer. */
      pair.local = ofp.local;
      // TODO only update tickleaf if it has changed?
      // pair.level2 = ofp.level2;
      return ofp.id;
    }
  }

  /* ## Update Offer */
  //+clear+
  /* Very similar to `newOffer`, `updateOffer` prepares an `OfferPack` for `writeOffer`. Makers should use it for updating live offers, but also to save on gas by reusing old, already consumed offers.



     Gas use is minimal when:
     1. The offer does not move in the book
     2. The offer does not change its `gasreq`
     3. The (`outbound_tkn`,`inbound_tkn`)'s `offer_gasbase` has not changed since the offer was last written
     4. `gasprice` has not changed since the offer was last written
     5. `gasprice` is greater than Mangrove's gasprice estimation
  */
  function updateOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint offerId
  ) external payable {
    unchecked {
      OfferPack memory ofp;
      Pair storage pair;
      (ofp.global, ofp.local, pair) = _config(outbound_tkn, inbound_tkn);
      unlockedMarketOnly(ofp.local);
      activeMarketOnly(ofp.global, ofp.local);
      if (msg.value > 0) {
        creditWei(msg.sender, msg.value);
      }
      ofp.outbound_tkn = outbound_tkn;
      ofp.inbound_tkn = inbound_tkn;
      ofp.wants = wants;
      ofp.gives = gives;
      ofp.id = offerId;
      ofp.gasreq = gasreq;
      ofp.gasprice = gasprice;
      ofp.oldOffer = pair.offerData[offerId].offer;
      // Save local config
      MgvStructs.LocalPacked oldLocal = ofp.local;
      // ofp.tick = Ticks.tickFromVolumes(wants,gives);
      // ofp.tickleaf = tickleafs[outbound_tkn][inbound_tkn][ofp.tick];
      /* The second argument indicates that we are updating an existing offer, not creating a new one. */
      writeOffer(pair, ofp, true);
      /* We saved the current pair's configuration before calling `writeOffer`, since that function may update the current `best` offer. We now check for any change to the configuration and update it if needed. */
      if (!oldLocal.eq(ofp.local)) {
        pair.local = ofp.local;
      }
      // TODO only update tickleaf if it has changed
      // tickleaf = ofp.tickleaf;
    }
  }

  /* ## Retract Offer */
  //+clear+
  /* `retractOffer` takes the offer `offerId` out of the book. However, `deprovision == true` also refunds the provision associated with the offer. */
  function retractOffer(address outbound_tkn, address inbound_tkn, uint offerId, bool deprovision)
    external
    returns (uint provision)
  {
    unchecked {
      (, MgvStructs.LocalPacked local, Pair storage pair) = _config(outbound_tkn, inbound_tkn);
      unlockedMarketOnly(local);
      OfferData storage offerData = pair.offerData[offerId];
      MgvStructs.OfferPacked offer = offerData.offer;
      MgvStructs.OfferDetailPacked offerDetail = offerData.detail;
      require(msg.sender == offerDetail.maker(), "mgv/retractOffer/unauthorized");

      /* Here, we are about to un-live an offer, so we start by taking it out of the book by stitching together its previous and next offers. Note that unconditionally calling `stitchOffers` would break the book since it would connect offers that may have since moved. */
      if (offer.isLive()) {
        MgvStructs.LocalPacked oldLocal = local;
        local = dislodgeOffer(pair, offer, local, true);
        /* If calling `stitchOffers` has changed the current `best` offer, we update the storage. */
        if (!oldLocal.eq(local)) {
          pair.local = local;
        }
      }
      /* Set `gives` to 0. Moreover, the last argument depends on whether the user wishes to get their provision back (if true, `gasprice` will be set to 0 as well). */
      dirtyDeleteOffer(offerData, offer, offerDetail, deprovision);

      /* If the user wants to get their provision back, we compute its provision from the offer's `gasprice`, `offer_gasbase` and `gasreq`. */
      if (deprovision) {
        provision = 10 ** 9 * offerDetail.gasprice() //gasprice is 0 if offer was deprovisioned
          * (offerDetail.gasreq() + offerDetail.offer_gasbase());
        // credit `balanceOf` and log transfer
        creditWei(msg.sender, provision);
      }
      emit OfferRetract(outbound_tkn, inbound_tkn, offerId, deprovision);
    }
  }

  /* ## Provisioning
  Market makers must have enough provisions for possible penalties. These provisions are in ETH. Every time a new offer is created or an offer is updated, `balanceOf` is adjusted to provision the offer's maximum possible penalty (`gasprice * (gasreq + offer_gasbase)`).

  For instance, if the current `balanceOf` of a maker is 1 ether and they create an offer that requires a provision of 0.01 ethers, their `balanceOf` will be reduced to 0.99 ethers. No ethers will move; this is just an internal accounting movement to make sure the maker cannot `withdraw` the provisioned amounts.

  */
  //+clear+

  /* Fund should be called with a nonzero value (hence the `payable` modifier). The provision will be given to `maker`, not `msg.sender`. */
  function fund(address maker) public payable {
    unchecked {
      (MgvStructs.GlobalPacked _global,) = config(address(0), address(0));
      liveMgvOnly(_global);
      creditWei(maker, msg.value);
    }
  }

  function fund() external payable {
    unchecked {
      fund(msg.sender);
    }
  }

  /* A transfer with enough gas to Mangrove will increase the caller's available `balanceOf` balance. _You should send enough gas to execute this function when sending money to Mangrove._  */
  receive() external payable {
    unchecked {
      fund(msg.sender);
    }
  }

  /* Any provision not currently held to secure an offer's possible penalty is available for withdrawal. */
  function withdraw(uint amount) external returns (bool noRevert) {
    unchecked {
      /* Since we only ever send money to the caller, we do not need to provide any particular amount of gas, the caller should manage this herself. */
      debitWei(msg.sender, amount);
      (noRevert,) = msg.sender.call{value: amount}("");
    }
  }

  /* # Low-level Maker functions */

  /* ## Write Offer */

  function writeOffer(Pair storage pair, OfferPack memory ofp, bool update) internal {
    unchecked {
      /* `gasprice`'s floor is Mangrove's own gasprice estimate, `ofp.global.gasprice`. We first check that gasprice fits in 16 bits. Otherwise it could be that `uint16(gasprice) < global_gasprice < gasprice`, and the actual value we store is `uint16(gasprice)`. */
      require(checkGasprice(ofp.gasprice), "mgv/writeOffer/gasprice/16bits");

      if (ofp.gasprice < ofp.global.gasprice()) {
        ofp.gasprice = ofp.global.gasprice();
      }

      /* * Check `gasreq` below limit. Implies `gasreq` at most 24 bits wide, which ensures no overflow in computation of `provision` (see below). */
      require(ofp.gasreq <= ofp.global.gasmax(), "mgv/writeOffer/gasreq/tooHigh");
      /* * Make sure `gives > 0` -- division by 0 would throw in several places otherwise, and `isLive` relies on it. */
      require(ofp.gives > 0, "mgv/writeOffer/gives/tooLow");
      /* * Make sure `wants > 0` -- price is stored as log_1BP(wants/gives). */
      require(ofp.wants > 0, "mgv/writeOffer/wants/tooLow");
      /* * Make sure that the maker is posting a 'dense enough' offer: the ratio of `outbound_tkn` offered per gas consumed must be high enough. The actual gas cost paid by the taker is overapproximated by adding `offer_gasbase` to `gasreq`. */
      require(
        ofp.gives >= ofp.local.density().multiply(ofp.gasreq + ofp.local.offer_gasbase()),
        "mgv/writeOffer/density/tooLow"
      );

      /* The following checks are for the maker's convenience only. */
      require(uint96(ofp.gives) == ofp.gives, "mgv/writeOffer/gives/96bits");
      require(uint96(ofp.wants) == ofp.wants, "mgv/writeOffer/wants/96bits");

      Tick insertionTick = TickLib.tickFromVolumes(ofp.wants, ofp.gives);

      /* Log the write offer event. */
      uint ofrId = ofp.id;
      emit OfferWrite(
        ofp.outbound_tkn,
        ofp.inbound_tkn,
        msg.sender,
        ofp.wants,
        ofp.gives,
        ofp.gasprice,
        ofp.gasreq,
        ofrId,
        Tick.unwrap(insertionTick)
      );

      /* We now write the new `offerDetails` and remember the previous provision (0 by default, for new offers) to balance out maker's `balanceOf`. */
      uint oldProvision;
      {
        OfferData storage offerData = pair.offerData[ofrId];
        MgvStructs.OfferDetailPacked offerDetail = offerData.detail;
        if (update) {
          require(msg.sender == offerDetail.maker(), "mgv/updateOffer/unauthorized");
          oldProvision = 10 ** 9 * offerDetail.gasprice() * (offerDetail.gasreq() + offerDetail.offer_gasbase());
        }

        /* If the offer is new, has a new `gasprice`, `gasreq`, or if Mangrove's `offer_gasbase` configuration parameter has changed, we also update `offerDetails`. */
        // TODO Can this be optimized to a single packed comparison? eg offerDetail != ofp.detail ?
        if (
          !update || offerDetail.gasreq() != ofp.gasreq || offerDetail.gasprice() != ofp.gasprice
            || offerDetail.offer_gasbase() != ofp.local.offer_gasbase()
        ) {
          uint offer_gasbase = ofp.local.offer_gasbase();
          offerData.detail = MgvStructs.OfferDetail.pack({
            __maker: msg.sender,
            __gasreq: ofp.gasreq,
            __offer_gasbase: offer_gasbase,
            __gasprice: ofp.gasprice
          });
        }
      }

      /* With every change to an offer, a maker may deduct provisions from its `balanceOf` balance. It may also get provisions back if the updated offer requires fewer provisions than before. */
      {
        uint provision = (ofp.gasreq + ofp.local.offer_gasbase()) * ofp.gasprice * 10 ** 9;
        if (provision > oldProvision) {
          debitWei(msg.sender, provision - oldProvision);
        } else if (provision < oldProvision) {
          creditWei(msg.sender, oldProvision - provision);
        }
      }

      // Tick insertionTick = ofp.tick;
      bool bestWillChange = ofp.local.level2().isEmpty() || insertionTick.strictlyBetter(ofp.local.tick());
      // mapping (uint => MgvStructs.OfferPacked) _offers = offers[ofp.outbound_tkn][ofp.inbound_tkn];
      // remove offer from previous position
      if (ofp.oldOffer.isLive()) {
        // may modify ofp.local
        // At this point only the in-memory local has the new best?
        /* When to update local.best/tick:
           - If removing this offer does not move tick: no
           - Otherwise, if new tick < insertion tick, yes
           - Otherwise, if new tick = insertion tick, yes because the inserted offer will be inserted at the end
           - Otherwise, if new tick > insertion tick, no 
           I cannot know new tick before checking it out. But it is >= current tick.
           So:
           - If current tick > insertion tick: no
           - Otherwise yes because maybe current tick = insertion tick
        */
        // bool updateLocal = tick.strictlyBetter(ofp.local.tick().strictlyBetter(tick)
        ofp.local = dislodgeOffer(pair, ofp.oldOffer, ofp.local, !bestWillChange);
        bestWillChange = ofp.local.level2().isEmpty() || insertionTick.strictlyBetter(ofp.local.tick());
      }

      // insertion
      Leaf leaf = pair.leafs[insertionTick.leafIndex()];
      // if leaf was empty flip tick on at level0
      if (leaf.isEmpty()) {
        Field field;
        int insertionIndex = insertionTick.level0Index();

        int currentIndex = ofp.local.tick().level0Index();
        bool indexDiff = insertionIndex != currentIndex;
        if (indexDiff) {
          field = pair.level0[insertionIndex];
        } else {
          field = ofp.local.level0();
        }

        if (indexDiff && bestWillChange) {
          pair.level0[currentIndex] = ofp.local.level0();
        }

        {
          Field field2 = field.flipBitAtLevel0(insertionTick);

          if (indexDiff && !bestWillChange) {
            pair.level0[insertionIndex] = field2;
          } else {
            ofp.local = ofp.local.level0(field2);
          }
        }

        if (field.isEmpty()) {
          insertionIndex = insertionTick.level1Index();
          field = pair.level1[insertionIndex];
          pair.level1[insertionIndex] = field.flipBitAtLevel1(insertionTick);
          // if level1 was empty, flip tick on at level2
          if (field.isEmpty()) {
            ofp.local = ofp.local.level2(ofp.local.level2().flipBitAtLevel2(insertionTick));
          }
        }
      }
      // invariant
      // tick empty -> firstId=lastId=0
      // tick has 1 offer -> firstId=lastId!=0
      // otherwise 0 != firstId != lastId != 0
      uint lastId = leaf.lastOfTick(insertionTick);
      if (lastId == 0) {
        leaf = leaf.setTickFirst(insertionTick, ofrId);
      } else {
        OfferData storage offerData = pair.offerData[lastId];
        offerData.offer = offerData.offer.next(ofrId);
      }

      // store offer at the end of the tick
      leaf = leaf.setTickLast(insertionTick, ofrId);
      pair.leafs[insertionTick.leafIndex()] = leaf;

      if (bestWillChange) {
        // FIXME: remove best update, only here for compatibility
        ofp.local = ofp.local.tick(insertionTick);
      }

      /* With the `prev`/`next` in hand, we finally store the offer in the `offers` map. */
      MgvStructs.OfferPacked ofr =
        MgvStructs.Offer.pack({__prev: lastId, __next: 0, __tick: insertionTick, __gives: ofp.gives});
      pair.offerData[ofrId].offer = ofr;
    }
  }

  /* ## Better */
  /* The utility method `better` takes an offer represented by `wants2`,`gives2`, `gasreq2`, and another represented by `offer1`. It returns true iff `offer1` is the better or equal offer`.
    "better" is defined on the lexicographic order $\textrm{price} \times_{\textrm{lex}} \textrm{density}^{-1}$. This means that for the same price, offers that deliver more volume per gas are taken first.

      In addition to `offer1`, we also provide offerData1 in order to save gas. If necessary (ie. if the prices `wants1/gives1` and `wants2/gives2` are the same), we read storage to get `gasreq1` at `offerData.detail`. */
  function better(uint wants2, uint gives2, uint gasreq2, MgvStructs.OfferPacked offer1, OfferData storage offerData1)
    internal
    view
    returns (bool)
  {
    unchecked {
      uint wants1 = offer1.wants();
      uint gives1 = offer1.gives();
      uint weight1 = wants1 * gives2;
      uint weight2 = wants2 * gives1;
      if (weight1 == weight2) {
        uint gasreq1 = offerData1.detail.gasreq();
        return (gives1 * gasreq2 >= gives2 * gasreq1);
      } else {
        return weight1 < weight2;
      }
    }
  }
}
