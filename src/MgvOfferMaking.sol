// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {IMaker, HasMgvEvents, MgvStructs, Bin, BinLib, Leaf, Field, TickLib, OLKey} from "./MgvLib.sol";
import {MgvHasOffers} from "./MgvHasOffers.sol";
import {TickConversionLib} from "mgv_lib/TickConversionLib.sol";
import "mgv_lib/Debug.sol";

/* `MgvOfferMaking` contains market-making-related functions. */
contract MgvOfferMaking is MgvHasOffers {
  /* # Public Maker operations
     ## New Offer */
  //+clear+
  /* In Mangrove, makers and takers call separate functions. Market makers call `newOffer` to fill the book, and takers call functions such as `marketOrder` to consume it.  */

  //+clear+

  /* The following structs holds offer creation/update parameters in memory. This frees up stack space for local variables. */
  struct OfferPack {
    OLKey olKey;
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

  No more than $2^{32}-1$ offers can ever be created for one `outbound_tkn`,`inbound_tkn`, `tickSpacing` offerList.

  The actual contents of the function is in `writeOffer`, which is called by both `newOffer` and `updateOffer`.
  */
  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint offerId)
  {
    unchecked {
      return newOfferByTick(olKey, TickConversionLib.tickFromVolumes(wants, gives), gives, gasreq, gasprice);
    }
  }

  function newOfferByTick(OLKey memory olKey, int tick, uint gives, uint gasreq, uint gasprice)
    public
    payable
    returns (uint offerId)
  {
    unchecked {
      /* In preparation for calling `writeOffer`, we read the `outbound_tkn`,`inbound_tkn`, `tickSpacing` offerList configuration, check for reentrancy and market liveness, fill the `OfferPack` struct and increment the offerList's `last`. */
      OfferPack memory ofp;
      OfferList storage offerList;
      (ofp.global, ofp.local, offerList) = _config(olKey);
      unlockedMarketOnly(ofp.local);
      activeMarketOnly(ofp.global, ofp.local);
      if (msg.value > 0) {
        creditWei(msg.sender, msg.value);
      }
      ofp.id = 1 + ofp.local.last();
      require(uint32(ofp.id) == ofp.id, "mgv/offerIdOverflow");

      ofp.local = ofp.local.last(ofp.id);

      ofp.olKey = olKey;
      ofp.gives = gives;
      ofp.gasreq = gasreq;
      ofp.gasprice = gasprice;

      /* The second parameter to writeOffer indicates that we are creating a new offer, not updating an existing one. */
      writeOffer(offerList, ofp, tick, false);

      /* Since we locally modified a field of the local configuration (`last`), we save the change to storage. Note that `writeOffer` may have further modified the local configuration by updating the current `best` offer. */
      offerList.local = ofp.local;
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
  function updateOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice, uint offerId)
    external
    payable
  {
    unchecked {
      updateOfferByTick(olKey, TickConversionLib.tickFromVolumes(wants, gives), gives, gasreq, gasprice, offerId);
    }
  }

  function updateOfferByTick(OLKey memory olKey, int tick, uint gives, uint gasreq, uint gasprice, uint offerId)
    public
    payable
  {
    unchecked {
      OfferPack memory ofp;
      OfferList storage offerList;
      (ofp.global, ofp.local, offerList) = _config(olKey);
      unlockedMarketOnly(ofp.local);
      activeMarketOnly(ofp.global, ofp.local);
      if (msg.value > 0) {
        creditWei(msg.sender, msg.value);
      }
      ofp.olKey = olKey;
      ofp.gives = gives;
      ofp.id = offerId;
      ofp.gasreq = gasreq;
      ofp.gasprice = gasprice;
      ofp.oldOffer = offerList.offerData[offerId].offer;
      // Save local config
      MgvStructs.LocalPacked oldLocal = ofp.local;
      // ofp.tickleaf = tickleafs[outbound_tkn][inbound_tkn][ofp.tick];
      /* The second argument indicates that we are updating an existing offer, not creating a new one. */
      writeOffer(offerList, ofp, tick, true);
      /* We saved the current offerList's configuration before calling `writeOffer`, since that function may update the current `best` offer. We now check for any change to the configuration and update it if needed. */
      if (!oldLocal.eq(ofp.local)) {
        offerList.local = ofp.local;
      }
    }
  }

  /* ## Retract Offer */
  //+clear+
  /* `retractOffer` takes the offer `offerId` out of the book. However, `deprovision == true` also refunds the provision associated with the offer. */
  function retractOffer(OLKey memory olKey, uint offerId, bool deprovision) external returns (uint provision) {
    unchecked {
      (, MgvStructs.LocalPacked local, OfferList storage offerList) = _config(olKey);
      unlockedMarketOnly(local);
      OfferData storage offerData = offerList.offerData[offerId];
      MgvStructs.OfferPacked offer = offerData.offer;
      MgvStructs.OfferDetailPacked offerDetail = offerData.detail;
      require(msg.sender == offerDetail.maker(), "mgv/retractOffer/unauthorized");

      /* Here, we are about to un-live an offer, so we start by taking it out of the book by stitching together its previous and next offers. Note that unconditionally calling `stitchOffers` would break the book since it would connect offers that may have since moved. */
      if (offer.isLive()) {
        MgvStructs.LocalPacked oldLocal = local;
        (local,) = dislodgeOffer(offerList, olKey.tickSpacing, offer, local, local.bestBin(), true);
        /* If calling `stitchOffers` has changed the current `best` offer, we update the storage. */
        if (!oldLocal.eq(local)) {
          offerList.local = local;
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

      emit OfferRetract(olKey.hash(), offerDetail.maker(), offerId, deprovision);
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
      (MgvStructs.GlobalPacked _global,,) = _config(OLKey(address(0), address(0), 0));
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

  function writeOffer(OfferList storage offerList, OfferPack memory ofp, int insertionTick, bool update) internal {
    unchecked {
      /* `gasprice`'s floor is Mangrove's own gasprice estimate, `ofp.global.gasprice`. We first check that gasprice fits in 16 bits. Otherwise it could be that `uint16(gasprice) < global_gasprice < gasprice`, and the actual value we store is `uint16(gasprice)`. */
      require(MgvStructs.Global.gasprice_check(ofp.gasprice), "mgv/writeOffer/gasprice/16bits");

      if (ofp.gasprice < ofp.global.gasprice()) {
        ofp.gasprice = ofp.global.gasprice();
      }

      /* * Check `gasreq` below limit. Implies `gasreq` at most 24 bits wide, which ensures no overflow in computation of `provision` (see below). */
      require(ofp.gasreq <= ofp.global.gasmax(), "mgv/writeOffer/gasreq/tooHigh");
      /* * Make sure `gives > 0` -- division by 0 would throw in several places otherwise, and `isLive` relies on it. */
      require(ofp.gives > 0, "mgv/writeOffer/gives/tooLow");
      /* * Make sure that the maker is posting a 'dense enough' offer: the ratio of `outbound_tkn` offered per gas consumed must be high enough. The actual gas cost paid by the taker is overapproximated by adding `offer_gasbase` to `gasreq`. */
      require(
        ofp.gives >= ofp.local.density().multiply(ofp.gasreq + ofp.local.offer_gasbase()),
        "mgv/writeOffer/density/tooLow"
      );

      /* The following checks are for the maker's convenience only. */
      require(uint96(ofp.gives) == ofp.gives, "mgv/writeOffer/gives/96bits");

      uint tickSpacing = ofp.olKey.tickSpacing;
      // normalize tick to tickSpacing
      Bin insertionBin = BinLib.nearestHigherTickToTick(insertionTick, tickSpacing);
      insertionTick = TickLib.fromBin(insertionBin, tickSpacing);
      require(TickLib.inRange(insertionTick), "mgv/writeOffer/tick/outOfRange");

      /* Log the write offer event. */
      uint ofrId = ofp.id;
      emit OfferWrite(ofp.olKey.hash(), msg.sender, insertionTick, ofp.gives, ofp.gasprice, ofp.gasreq, ofrId);

      /* We now write the new `offerDetails` and remember the previous provision (0 by default, for new offers) to balance out maker's `balanceOf`. */
      {
        uint oldProvision;
        OfferData storage offerData = offerList.offerData[ofrId];
        MgvStructs.OfferDetailPacked offerDetail = offerData.detail;
        if (update) {
          require(msg.sender == offerDetail.maker(), "mgv/updateOffer/unauthorized");
          oldProvision = 10 ** 9 * offerDetail.gasprice() * (offerDetail.gasreq() + offerDetail.offer_gasbase());
        }

        /* If the offer is new, has a new `gasprice`, `gasreq`, or if Mangrove's `offer_gasbase` configuration parameter has changed, we also update `offerDetails`. */
        if (
          !update || offerDetail.gasreq() != ofp.gasreq || offerDetail.gasprice() != ofp.gasprice
            || offerDetail.offer_gasbase() != ofp.local.offer_gasbase()
        ) {
          uint offer_gasbase = ofp.local.offer_gasbase();
          offerData.detail = MgvStructs.OfferDetail.pack({
            __maker: msg.sender,
            __gasreq: ofp.gasreq,
            __kilo_offer_gasbase: offer_gasbase / 1e3,
            __gasprice: ofp.gasprice
          });
        }

        /* With every change to an offer, a maker may deduct provisions from its `balanceOf` balance. It may also get provisions back if the updated offer requires fewer provisions than before. */
        uint provision = (ofp.gasreq + ofp.local.offer_gasbase()) * ofp.gasprice * 10 ** 9;
        if (provision > oldProvision) {
          debitWei(msg.sender, provision - oldProvision);
        } else if (provision < oldProvision) {
          creditWei(msg.sender, oldProvision - provision);
        }
      }

      // must cache bin because branch will be modified and bin information will be lost (in case an offer will be removed)
      Bin cachedLocalBin;
      // force control flow through gas saving path if offer list is empty
      if (ofp.local.level3().isEmpty()) {
        cachedLocalBin = insertionBin;
      } else {
        cachedLocalBin = ofp.local.bestBin();
        // remove offer from previous position
        if (ofp.oldOffer.isLive()) {
          // may modify ofp.local
          // At this point only the in-memory local has the new best?
          /* When to update local.best/bin:
            - If removing this offer does not move bin: no
            - Otherwise, if new bin < insertion bin, yes
            - Otherwise, if new bin = insertion bin, yes because the inserted offer will be inserted at the end
            - Otherwise, if new bin > insertion bin, no 
            I cannot know new bin before checking it out. But it is >= current bin.
            So:
            - If current bin > insertion bin: no
            - Otherwise yes because maybe current bin = insertion tick
          */
          // bool updateLocal = bin.strictlyBetter(ofp.local.bestBin().strictlyBetter(bin)
          bool shouldUpdateBranch = !insertionBin.strictlyBetter(cachedLocalBin);

          (ofp.local, shouldUpdateBranch) =
            dislodgeOffer(offerList, tickSpacing, ofp.oldOffer, ofp.local, cachedLocalBin, shouldUpdateBranch);
          // If !shouldUpdateBranch, then ofp.local.level3 and ofp.local.level2 reflect the removed tick's branch post-removal, so one cannot infer the bin by reading those fields. If shouldUpdateBranch, then the new bin must be inferred from the new info in local.
          if (shouldUpdateBranch) {
            // force control flow through gas-saving path if retraction emptied the offer list
            if (ofp.local.level3().isEmpty()) {
              cachedLocalBin = insertionBin;
            } else {
              cachedLocalBin = ofp.local.bestBin();
            }
          }
        }
      }
      if (!cachedLocalBin.strictlyBetter(insertionBin)) {
        ofp.local = ofp.local.binPosInLeaf(insertionBin.posInLeaf());
      }

      // insertion
      Leaf leaf = offerList.leafs[insertionBin.leafIndex()].clean();
      // if leaf was empty flip bin on at level3
      if (leaf.isEmpty()) {
        Field field;
        int insertionIndex = insertionBin.level3Index();
        int currentIndex = cachedLocalBin.level3Index();
        // Get insertion level3
        if (insertionIndex != currentIndex) {
          field = offerList.level3[insertionIndex].clean();
          // Save current level3
          if (insertionIndex < currentIndex) {
            Field localLevel3 = ofp.local.level3();
            bool shouldSaveLevel3 = !localLevel3.isEmpty();
            if (!shouldSaveLevel3) {
              shouldSaveLevel3 = !offerList.level3[currentIndex].eq(DirtyFieldLib.CLEAN_EMPTY);
            }
            if (shouldSaveLevel3) {
              offerList.level3[currentIndex] = localLevel3.dirty();
            }
          }
        } else {
          field = ofp.local.level3();
        }

        // Write insertion level3
        if (insertionIndex <= currentIndex) {
          ofp.local = ofp.local.level3(field.flipBitAtLevel3(insertionBin));
        } else {
          offerList.level3[insertionIndex] = field.flipBitAtLevel3(insertionBin).dirty();
        }

        if (field.isEmpty()) {
          insertionIndex = insertionBin.level2Index();
          currentIndex = cachedLocalBin.level2Index();

          if (insertionIndex != currentIndex) {
            field = offerList.level2[insertionIndex].clean();
            if (insertionIndex < currentIndex) {
              Field localLevel2 = ofp.local.level2();
              bool shouldSaveLevel2 = !localLevel2.isEmpty();
              if (!shouldSaveLevel2) {
                shouldSaveLevel2 = !offerList.level2[currentIndex].eq(DirtyFieldLib.CLEAN_EMPTY);
              }
              if (shouldSaveLevel2) {
                offerList.level2[currentIndex] = localLevel2.dirty();
              }
            }
          } else {
            field = ofp.local.level2();
          }

          if (insertionIndex <= currentIndex) {
            ofp.local = ofp.local.level2(field.flipBitAtLevel2(insertionBin));
          } else {
            offerList.level2[insertionIndex] = field.flipBitAtLevel2(insertionBin).dirty();
          }
          // if level2 was empty, flip bin on at level1
          if (field.isEmpty()) {
            insertionIndex = insertionBin.level1Index();
            currentIndex = cachedLocalBin.level1Index();

            if (insertionIndex != currentIndex) {
              field = offerList.level1[insertionIndex].clean();
              if (insertionIndex < currentIndex) {
                // unlike level3&1, level1 cannot be CLEAN_EMPTY (dirtied in active())
                offerList.level1[currentIndex] = ofp.local.level1().dirty();
              }
            } else {
              field = ofp.local.level1();
            }

            if (insertionIndex <= currentIndex) {
              ofp.local = ofp.local.level1(field.flipBitAtLevel1(insertionBin));
            } else {
              offerList.level1[insertionIndex] = field.flipBitAtLevel1(insertionBin).dirty();
            }
            // if level1 was empty, flip bin on at root
            if (field.isEmpty()) {
              ofp.local = ofp.local.root(ofp.local.root().flipBitAtRoot(insertionBin));
            }
          }
        }
      }
      // invariant
      // bin empty -> firstId=lastId=0
      // bin has 1 offer -> firstId=lastId!=0
      // otherwise 0 != firstId != lastId != 0
      uint lastId = leaf.lastOfBin(insertionBin);
      if (lastId == 0) {
        leaf = leaf.setBinFirst(insertionBin, ofrId);
      } else {
        OfferData storage offerData = offerList.offerData[lastId];
        offerData.offer = offerData.offer.next(ofrId);
      }

      // store offer at the end of the tick
      leaf = leaf.setBinLast(insertionBin, ofrId);
      offerList.leafs[insertionBin.leafIndex()] = leaf.dirty();

      /* With the `prev`/`next` in hand, we finally store the offer in the `offers` map. */
      MgvStructs.OfferPacked ofr =
        MgvStructs.Offer.pack({__prev: lastId, __next: 0, __tick: insertionTick, __gives: ofp.gives});
      offerList.offerData[ofrId].offer = ofr;
    }
  }
}
