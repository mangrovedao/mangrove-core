// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import "@mgv/src/core/MgvLib.sol";
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
    OLKey olKey;
    uint gives;
    uint id;
    uint gasreq;
    uint gasprice;
    Global global;
    Local local;
    // used on update only
    Offer oldOffer;
  }

  /* The function `newOffer` is for market makers only; no match with the existing offer list is done. The maker specifies how much `olKey.outbound_tkn` token it `gives`, and at which `tick` (which is a power of 1.0001 and induces a price). The actual tick of the offer will be the smallest tick offerTick > tick that satisfies offerTick % tickSpacing == 0.

     It also specify with `gasreq` how much gas should be given when executing their offer.

     `gasprice` indicates an upper bound on the gasprice (in Mwei) at which the maker is ready to be penalised if their offer fails. Any value below Mangrove's internal `gasprice` configuration value will be ignored.

    `gasreq`, together with `gasprice`, will contribute to determining the penalty provision set aside by Mangrove from the market maker's `balanceOf` balance.

  An offer cannot be inserted in a closed market, nor when a reentrancy lock for `outbound_tkn`,`inbound_tkn` is on.

  No more than $2^{32}-1$ offers can ever be created for one (`outbound`,`inbound`, `tickSpacing`) offer list.

  The actual contents of the function is in `writeOffer`, which is called by both `newOffer` and `updateOffer`. */

  function newOfferByTick(OLKey memory olKey, Tick tick, uint gives, uint gasreq, uint gasprice)
    public
    payable
    returns (uint offerId)
  {
    unchecked {
      /* In preparation for calling `writeOffer`, we read the `outbound_tkn`,`inbound_tkn`, `tickSpacing` offer list configuration, check for reentrancy and offer list liveness, fill the `OfferPack` struct and increment the offer list's `last`. */
      OfferPack memory ofp;
      OfferList storage offerList;
      (ofp.global, ofp.local, offerList) = _config(olKey);
      unlockedOfferListOnly(ofp.local);
      activeOfferListOnly(ofp.global, ofp.local);
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

      /* The last parameter to writeOffer indicates that we are creating a new offer, not updating an existing one. */
      writeOffer(offerList, ofp, tick, false);

      /* Since we locally modified a field of the local configuration (`last`), we save the change to storage. Note that `writeOffer` may have further modified the local configuration by updating the currently cached tick tree branch. */
      offerList.local = ofp.local;
      return ofp.id;
    }
  }

  /* There is a `ByVolume` variant where the maker specifies how much `inbound_tkn` it `wants` and how much `outbound_tkn` it `gives`. Volumes should fit on 127 bits.

  */
  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint offerId)
  {
    unchecked {
      return newOfferByTick(olKey, TickLib.tickFromVolumes(wants, gives), gives, gasreq, gasprice);
    }
  }

  /* ## Update Offer */
  //+clear+
  /* Very similar to `newOffer`, `updateOffer` prepares an `OfferPack` for `writeOffer`. Makers should use it for updating live offers, but also to save on gas by reusing old, already consumed offers.

     Gas use is minimal when:
     1. The offer does not move in the offer list
     2. The offer does not change its `gasreq`
     3. The (`outbound_tkn`,`inbound_tkn`)'s `offer_gasbase` has not changed since the offer was last written
     4. `gasprice` has not changed since the offer was last written
     5. `gasprice` is greater than Mangrove's gasprice estimation
  */
  function updateOfferByTick(OLKey memory olKey, Tick tick, uint gives, uint gasreq, uint gasprice, uint offerId)
    public
    payable
  {
    unchecked {
      OfferPack memory ofp;
      OfferList storage offerList;
      (ofp.global, ofp.local, offerList) = _config(olKey);
      unlockedOfferListOnly(ofp.local);
      activeOfferListOnly(ofp.global, ofp.local);
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
      Local oldLocal = ofp.local;
      /* The second argument indicates that we are updating an existing offer, not creating a new one. */
      writeOffer(offerList, ofp, tick, true);
      /* We saved the current offer list's local configuration before calling `writeOffer`, since that function may update it. We now check for any change to the configuration and update it if needed. */
      if (!oldLocal.eq(ofp.local)) {
        offerList.local = ofp.local;
      }
    }
  }

  function updateOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice, uint offerId)
    external
    payable
  {
    unchecked {
      updateOfferByTick(olKey, TickLib.tickFromVolumes(wants, gives), gives, gasreq, gasprice, offerId);
    }
  }

  /* ## Retract Offer */
  //+clear+
  /* `retractOffer` takes the offer `offerId` out of the book. However, `deprovision == true` also refunds the provision associated with the offer. */
  function retractOffer(OLKey memory olKey, uint offerId, bool deprovision) external returns (uint provision) {
    unchecked {
      (, Local local, OfferList storage offerList) = _config(olKey);
      unlockedOfferListOnly(local);
      OfferData storage offerData = offerList.offerData[offerId];
      Offer offer = offerData.offer;
      OfferDetail offerDetail = offerData.detail;
      require(msg.sender == offerDetail.maker(), "mgv/retractOffer/unauthorized");

      /* Here, we are about to un-live an offer, so we start by taking it out of the tick tree. Note that unconditionally calling `dislodgeOffer` even if the offer is not `live` would break the offer list since it would connect offers that may have since moved. */
      if (offer.isLive()) {
        Local oldLocal = local;
        (local,) = dislodgeOffer(offerList, olKey.tickSpacing, offer, local, local.bestBin(), true);
        /* If calling `dislodgeOffer` has changed the current best offer, we update `local`. */
        if (!oldLocal.eq(local)) {
          offerList.local = local;
        }
      }
      /* Set `offer.gives` to 0 (which is encodes the fact that the offer is dead). The `deprovision` argument indicates whether the maker wishes to get their provision back (if true, `offer.gasprice` will be set to 0 as well). */
      dirtyDeleteOffer(offerData, offer, offerDetail, deprovision);

      /* If the user wants to get their provision back, we compute it from the offer's `gasprice`, `offer_gasbase` and `gasreq`. */
      if (deprovision) {
        provision = 1e6 * offerDetail.gasprice() //gasprice is 0 if offer was deprovisioned
          * (offerDetail.gasreq() + offerDetail.offer_gasbase());
        // credit `balanceOf` and log transfer
        creditWei(msg.sender, provision);
      }

      emit OfferRetract(olKey.hash(), offerDetail.maker(), offerId, deprovision);
    }
  }

  /* ## Provisioning
  Market makers must have enough provisions for possible penalties. These provisions are in native tokens. Every time a new offer is created or an offer is updated, `balanceOf` is adjusted to provision the offer's maximum possible penalty (`gasprice * (gasreq + offer_gasbase)`).

  For instance, if the current `balanceOf` of a maker is 1 ether and they create an offer that requires a provision of 0.01 ethers, their `balanceOf` will be reduced to 0.99 ethers. No ethers will move; this is just an internal accounting movement to make sure the maker cannot `withdraw` the provisioned amounts.

  */
  //+clear+

  /* Fund should be called with a nonzero value (hence the `payable` modifier). The provision will be given to `maker`, not `msg.sender`. */
  function fund(address maker) public payable {
    unchecked {
      (Global _global,,) = _config(OLKey(address(0), address(0), 0));
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

  /* Used by `updateOfferBy*` and `newOfferBy*`, this function optionally removes an offer then (re)inserts it in the tick tree. The `update` argument indicates whether the call comes from `updateOfferBy*` or `newOfferBy*`. */
  function writeOffer(OfferList storage offerList, OfferPack memory ofp, Tick insertionTick, bool update) internal {
    unchecked {
      /* `gasprice`'s floor is Mangrove's own gasprice estimate, `ofp.global.gasprice`. We first check that gasprice fits in 26 bits. Otherwise it could be that `uint26(gasprice) < global_gasprice < gasprice`, and the actual value we store is `uint26(gasprice)` (using pseudocode here since the type uint26 does not exist). */
      require(GlobalLib.gasprice_check(ofp.gasprice), "mgv/writeOffer/gasprice/tooBig");

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
      require(OfferLib.gives_check(ofp.gives), "mgv/writeOffer/gives/tooBig");

      uint tickSpacing = ofp.olKey.tickSpacing;
      /* Derive bin from given tick, then normalize the tick: available ticks in an offer list are those who are equal to 0 modulo tickSpacing. */
      Bin insertionBin = insertionTick.nearestBin(tickSpacing);
      insertionTick = insertionBin.tick(tickSpacing);
      require(insertionTick.inRange(), "mgv/writeOffer/tick/outOfRange");

      /* Log the write offer event. */
      uint ofrId = ofp.id;
      emit OfferWrite(
        ofp.olKey.hash(), msg.sender, Tick.unwrap(insertionTick), ofp.gives, ofp.gasprice, ofp.gasreq, ofrId
      );

      /* We now write the new `offerDetails` and remember the previous provision (0 by default, for new offers) to balance out maker's `balanceOf`. */
      {
        uint oldProvision;
        OfferData storage offerData = offerList.offerData[ofrId];
        OfferDetail offerDetail = offerData.detail;
        if (update) {
          require(msg.sender == offerDetail.maker(), "mgv/updateOffer/unauthorized");
          oldProvision = 1e6 * offerDetail.gasprice() * (offerDetail.gasreq() + offerDetail.offer_gasbase());
        }

        /* If the offer is new, has a new `gasprice`, `gasreq`, or if Mangrove's `offer_gasbase` configuration parameter has changed, we also update `offerDetails`. */
        if (
          !update || offerDetail.gasreq() != ofp.gasreq || offerDetail.gasprice() != ofp.gasprice
            || offerDetail.offer_gasbase() != ofp.local.offer_gasbase()
        ) {
          uint offer_gasbase = ofp.local.offer_gasbase();
          offerData.detail = OfferDetailLib.pack({
            __maker: msg.sender,
            __gasreq: ofp.gasreq,
            __kilo_offer_gasbase: offer_gasbase / 1e3,
            __gasprice: ofp.gasprice
          });
        }

        /* With every change to an offer, a maker may deduct provisions from its `balanceOf` balance. It may also get provisions back if the updated offer requires fewer provisions than before. */
        uint provision = (ofp.gasreq + ofp.local.offer_gasbase()) * ofp.gasprice * 1e6;
        if (provision > oldProvision) {
          debitWei(msg.sender, provision - oldProvision);
        } else if (provision < oldProvision) {
          creditWei(msg.sender, oldProvision - provision);
        }
      }

      /* We now cache the current best bin in a stack variable. Since the current best bin is derived from `ofp.local`, and since `ofp.local` may change as a new branch is cached in `local`, not caching that value means potentially losing access to it. */
      Bin cachedBestBin;
      // Check if tick tree is currently empty. As an invariant, `local.level3` if empty, iff `local.level2` is empty, iff `local.level1` is empty, iff `local.root` is empty.
      if (ofp.local.level3().isEmpty()) {
        /* If the tick tree is empty, we consider the current best bin to be the bin of the written offer. This makes later comparisons between them pick the right conditional branch every time. */
        cachedBestBin = insertionBin;
      } else {
        /* If the tick tree is currently not empty, we cache the current best bin. */
        cachedBestBin = ofp.local.bestBin();
        /* If the written offer is currently stored in the tick tree, it must be removed. */
        if (ofp.oldOffer.isLive()) {
          /* If the insertion bin of the offer is better than the current best bin, the later call to `dislodgeOffer` does not need to update the cached branch in `local` since we (`writeOffer`) will take care of updating the branch as part of insertion the offer in its new bin. Otherwise, we may need `dislodgeOffer` to take care of updating the cached branch in `local`. However, that is only th the case if the written offer is currently the best offer of the tick tree. `dislodgeOffer` will make that determination. */
          bool shouldUpdateBranch = !insertionBin.strictlyBetter(cachedBestBin);

          /* `local` is updated, and `shouldUpdateBranch` now means "did update branch". */
          (ofp.local, shouldUpdateBranch) =
            dislodgeOffer(offerList, tickSpacing, ofp.oldOffer, ofp.local, cachedBestBin, shouldUpdateBranch);
          /* If `dislodgeOffer` did update the information in `local`, it means the cached best bin may be stale -- the best offer may now be in a different bin. So we update it. */
          if (shouldUpdateBranch) {
            if (ofp.local.level3().isEmpty()) {
              /* A call to `bestBin()` is invalid when the branch cached in `local` is for an empty tick tree. In that case, as we did earlier if the tick tree was already empty, we set the current best bin to the bin of the written offer. */
              cachedBestBin = insertionBin;
            } else {
              cachedBestBin = ofp.local.bestBin();
            }
          }
        }
      }

      /* We will now insert the offer to its new position in the tick tree. If the offer is now the best offer, we update the cached "bin position in leaf" information in `local`. */
      if (!cachedBestBin.strictlyBetter(insertionBin)) {
        ofp.local = ofp.local.binPosInLeaf(insertionBin.posInLeaf());
      }

      /* Next, we load the leaf of the offer to check whether it needs updating. */
      Leaf leaf = offerList.leafs[insertionBin.leafIndex()].clean();

      /* If the written offer's leaf was empty, the level3 above it needs updating. */
      if (leaf.isEmpty()) {
        /* We reuse the same `field` variable for all 3 level indices. */
        Field field;
        /* We reuse the same `insertionIndex` and `currentIndex` variables for all 3 level indices and for the leaf index. */
        int insertionIndex = insertionBin.level3Index();
        int currentIndex = cachedBestBin.level3Index();
        if (insertionIndex == currentIndex) {
          /* If the written offer's level3 is the cached level3, we load the written offer's level3 from `local`. */
          field = ofp.local.level3();
        } else {
          /* Otherwise we load the written offer's level3 from storage. */
          field = offerList.level3s[insertionIndex].clean();
          /* If the written offer's level3 is strictly better than the cached level3, we evict the cached level3. */
          if (insertionIndex < currentIndex) {
            Field localLevel3 = ofp.local.level3();
            bool shouldSaveLevel3 = !localLevel3.isEmpty();
            /* Clean/dirty management. `if`s are sequenced to avoid a useless SLOAD. */
            if (!shouldSaveLevel3) {
              shouldSaveLevel3 = !offerList.level3s[currentIndex].eq(DirtyFieldLib.CLEAN_EMPTY);
            }
            if (shouldSaveLevel3) {
              offerList.level3s[currentIndex] = localLevel3.dirty();
            }
          }
        }

        if (insertionIndex <= currentIndex) {
          /* If the written offer's level3 is as good as or better than the cached level3, we cache the written offer's level3 in `local`. */
          ofp.local = ofp.local.level3(field.flipBitAtLevel3(insertionBin));
        } else {
          /* Otherwise, we put it in storage */
          offerList.level3s[insertionIndex] = field.flipBitAtLevel3(insertionBin).dirty();
        }

        /* If the written offer's level3 was empty, the level2 above it needs updating. */
        if (field.isEmpty()) {
          insertionIndex = insertionBin.level2Index();
          currentIndex = cachedBestBin.level2Index();

          if (insertionIndex == currentIndex) {
            /* If the written offer's level2 is the cached level2, we load the written offer's level2 from `local`. */
            field = ofp.local.level2();
          } else {
            /* Otherwise we load the written offer's level2 from storage. */
            field = offerList.level2s[insertionIndex].clean();

            /* If the written offer's level2 is strictly better than the cached level2, we evict the cached level2. */
            if (insertionIndex < currentIndex) {
              Field localLevel2 = ofp.local.level2();
              bool shouldSaveLevel2 = !localLevel2.isEmpty();

              /* Clean/dirty management. `if`s are sequenced to avoid a useless SLOAD. */
              if (!shouldSaveLevel2) {
                shouldSaveLevel2 = !offerList.level2s[currentIndex].eq(DirtyFieldLib.CLEAN_EMPTY);
              }
              if (shouldSaveLevel2) {
                offerList.level2s[currentIndex] = localLevel2.dirty();
              }
            }
          }

          if (insertionIndex <= currentIndex) {
            /* If the written offer's level3 is as good as or better than the cached level3, we cache the written offer's level3 in `local`. */
            ofp.local = ofp.local.level2(field.flipBitAtLevel2(insertionBin));
          } else {
            /* Otherwise, we put it in storage */
            offerList.level2s[insertionIndex] = field.flipBitAtLevel2(insertionBin).dirty();
          }
          /* If the written offer's level2 was empty, the level1 above it needs updating. */
          if (field.isEmpty()) {
            insertionIndex = insertionBin.level1Index();
            currentIndex = cachedBestBin.level1Index();

            if (insertionIndex == currentIndex) {
              /* If the written offer's level1 is the cached level1, we load the written offer's level1 from `local`. */
              field = ofp.local.level1();
            } else {
              /* Otherwise we load the written offer's level1 from storage. */
              field = offerList.level1s[insertionIndex].clean();
              /* If the written offer's level1 is strictly better than the cached level1, we evict the cached level1. */
              if (insertionIndex < currentIndex) {
                /* Unlike with level2 and level3, level1 cannot be `CLEAN_EMPTY` (it gets dirtied in `activate`) */
                offerList.level1s[currentIndex] = ofp.local.level1().dirty();
              }
            }

            if (insertionIndex <= currentIndex) {
              /* If the written offer's level1 is as good as or better than the cached level1, we cache the written offer's level1 in `local`. */
              ofp.local = ofp.local.level1(field.flipBitAtLevel1(insertionBin));
            } else {
              /* Otherwise, we put it in storage */
              offerList.level1s[insertionIndex] = field.flipBitAtLevel1(insertionBin).dirty();
            }
            /* If the written offer's level1 was empty, the root needs updating. */
            if (field.isEmpty()) {
              ofp.local = ofp.local.root(ofp.local.root().flipBitAtRoot(insertionBin));
            }
          }
        }
      }

      /* Now that we are done checking the current state of the leaf, we can update it. By reading the last id of the written offer's bin in the offer's leaf, we can check if the bin is currently empty or not (as an invariant, an empty bin has both `firstId` and `lastId` equal to 0, and a nonempty bin has both ids different from 0. 

      Note that offers are always inserted at the end of their bin, so that earlier offer are taken first during market orders.
      */

      uint lastId = leaf.lastOfBin(insertionBin);
      if (lastId == 0) {
        /* If the bin was empty, we update the bin's first id (a bin with a single offer has that offer id as `firstId` and as `lastId`).*/
        leaf = leaf.setBinFirst(insertionBin, ofrId);
      } else {
        /* Otherwise, the written offer will become the new last offer of the bin, and the current last offer will have the written offer as next offer. */
        OfferData storage offerData = offerList.offerData[lastId];
        offerData.offer = offerData.offer.next(ofrId);
      }

      /* We now store the written offer id as the last offer of the bin. */
      leaf = leaf.setBinLast(insertionBin, ofrId);
      offerList.leafs[insertionBin.leafIndex()] = leaf.dirty();

      /* Finally, we store the offer information, including a pointer to the previous last offer of the bin (it may be 0). */
      Offer ofr = OfferLib.pack({__prev: lastId, __next: 0, __tick: insertionTick, __gives: ofp.gives});
      offerList.offerData[ofrId].offer = ofr;
    }
  }
}
