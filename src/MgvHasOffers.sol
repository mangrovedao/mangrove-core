// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {
  MgvLib,
  HasMgvEvents,
  IMgvMonitor,
  MgvStructs,
  Field,
  Leaf,
  Bin,
  LEVEL_SIZE,
  OLKey,
  DirtyFieldLib
} from "./MgvLib.sol";
import {MgvCommon} from "./MgvCommon.sol";

/* `MgvHasOffers` contains the state variables and functions common to both market-maker operations and market-taker operations. Mostly: storing offers, removing them, updating market makers' provisions. */
contract MgvHasOffers is MgvCommon {
  /* # Provision debit/credit utility functions */
  /* `balanceOf` is in wei of ETH. */

  function debitWei(address maker, uint amount) internal {
    unchecked {
      uint makerBalance = _balanceOf[maker];
      require(makerBalance >= amount, "mgv/insufficientProvision");
      _balanceOf[maker] = makerBalance - amount;
      emit Debit(maker, amount);
    }
  }

  function creditWei(address maker, uint amount) internal {
    unchecked {
      _balanceOf[maker] += amount;
      emit Credit(maker, amount);
    }
  }

  /* # Misc. low-level functions */
  /* ## Offer deletion */

  /* When an offer is deleted, it is marked as such by setting `gives` to 0. Note that provision accounting in Mangrove aims to minimize writes. Each maker `fund`s Mangrove to increase its balance. When an offer is created/updated, we compute how much should be reserved to pay for possible penalties. That amount can always be recomputed with `offerDetail.gasprice * (offerDetail.gasreq + offerDetail.offer_gasbase)`. The balance is updated to reflect the remaining available ethers.

     Now, when an offer is deleted, the offer can stay provisioned, or be `deprovision`ed. In the latter case, we set `gasprice` to 0, which induces a provision of 0. All code calling `dirtyDeleteOffer` with `deprovision` set to `true` must be careful to correctly account for where that provision is going (back to the maker's `balanceOf`, or sent to a taker as compensation). */
  function dirtyDeleteOffer(
    OfferData storage offerData,
    MgvStructs.OfferPacked offer,
    MgvStructs.OfferDetailPacked offerDetail,
    bool deprovision
  ) internal {
    unchecked {
      offer = offer.gives(0);
      if (deprovision) {
        offerDetail = offerDetail.gasprice(0);
      }
      offerData.offer = offer;
      offerData.detail = offerDetail;
    }
  }

  /* ## Stitching the orderbook */

  // shouldUpdateBest is true if we may want to update best, false if there is no way we want to update it (eg if we know we are about to reinsert the offer anyway and will update best then?)
  function dislodgeOffer(
    OfferList storage offerList,
    uint tickSpacing,
    MgvStructs.OfferPacked offer,
    MgvStructs.LocalPacked local,
    Bin bestBin,
    bool shouldUpdateBranch
  ) internal returns (MgvStructs.LocalPacked, bool) {
    unchecked {
      Leaf leaf;
      Bin offerBin = offer.bin(tickSpacing);
      // save stack space
      {
        uint prevId = offer.prev();
        uint nextId = offer.next();
        if (prevId == 0 || nextId == 0) {
          leaf = offerList.leafs[offerBin.leafIndex()].clean();
        }

        // if current bin is not strictly better,
        // time to look for a new current tick
        // NOTE: I used to name this var "shouldUpdateBin" and add "&& (prevId == 0 && nextId == 0)" because bin has not changed if you are not removing the last offer of a bin. But for now i want to return the NEW BEST (for compatibility reasons). Will edit later.
        // note: adding offerId as an arg would let us replace
        // prevId == 0 && !local.bin.strictlyBetter(offerBin)
        // with
        // offerId == local.best() (but best will maybe go away in the future)

        // If shouldUpdateBranch is false is means we are about to insert anyway, so no need to load the best branch right now
        // if local.bin < offerBin then a better branch is already cached. note that local.bin >= offerBin implies local.bin = offerTick
        // no need to check for prevId/nextId == 0: if offer is last of leaf, it will be checked by leaf.isEmpty()
        shouldUpdateBranch = shouldUpdateBranch && prevId == 0 && !bestBin.strictlyBetter(offerBin);

        if (prevId == 0) {
          // offer was tick's first. new first offer is offer.next (may be 0)
          leaf = leaf.setBinFirst(offerBin, nextId);
        } else {
          // offer.prev's next becomes offer.next
          OfferData storage prevOfferData = offerList.offerData[prevId];
          prevOfferData.offer = prevOfferData.offer.next(nextId);
        }

        if (nextId == 0) {
          // offer was tick's last. new last offer is offer.prev (may be 0)
          leaf = leaf.setBinLast(offerBin, prevId);
        } else {
          // offer.next's prev becomes offer.prev
          OfferData storage nextOfferData = offerList.offerData[nextId];
          nextOfferData.offer = nextOfferData.offer.prev(prevId);
        }
        if (prevId != 0 && nextId != 0) {
          return (local, shouldUpdateBranch);
        }
      }

      // offer.bin's first or last offer changed, must update leaf
      offerList.leafs[offerBin.leafIndex()] = leaf.dirty();
      // if leaf now empty, flip ticks OFF up the tree
      if (leaf.isEmpty()) {
        int index = offerBin.level3Index(); // level3Index or level2Index
        Field field;
        if (index == bestBin.level3Index()) {
          field = local.level3().flipBitAtLevel3(offerBin);
          local = local.level3(field);
          if (shouldUpdateBranch && field.isEmpty()) {
            if (!offerList.level3[index].eq(DirtyFieldLib.CLEAN_EMPTY)) {
              offerList.level3[index] = DirtyFieldLib.DIRTY_EMPTY;
            }
          }
        } else {
          // note: useless dirty/clean cycle here
          field = offerList.level3[index].clean().flipBitAtLevel3(offerBin);
          offerList.level3[index] = field.dirty();
        }
        if (field.isEmpty()) {
          index = offerBin.level2Index(); // level3Index or level2Index
          if (index == bestBin.level2Index()) {
            field = local.level2().flipBitAtLevel2(offerBin);
            local = local.level2(field);
            if (shouldUpdateBranch && field.isEmpty()) {
              if (!offerList.level2[index].eq(DirtyFieldLib.CLEAN_EMPTY)) {
                offerList.level2[index] = DirtyFieldLib.DIRTY_EMPTY;
              }
            }
          } else {
            // note: useless dirty/clean cycle here
            field = offerList.level2[index].clean().flipBitAtLevel2(offerBin);
            offerList.level2[index] = field.dirty();
          }
          if (field.isEmpty()) {
            index = offerBin.level1Index(); // level3Index or level2Index
            if (index == bestBin.level1Index()) {
              field = local.level1().flipBitAtLevel1(offerBin);
              local = local.level1(field);
              if (shouldUpdateBranch && field.isEmpty()) {
                // unlike level3&1, level1 cannot be CLEAN_EMPTY (dirtied in active())
                offerList.level1[index] = field.dirty();
              }
            } else {
              // note: useless dirty/clean cycle here
              field = offerList.level1[index].clean().flipBitAtLevel1(offerBin);
              offerList.level1[index] = field.dirty();
            }
            if (field.isEmpty()) {
              field = local.root().flipBitAtRoot(offerBin);
              local = local.root(field);

              if (field.isEmpty()) {
                return (local, shouldUpdateBranch);
              }
              if (shouldUpdateBranch) {
                index = field.firstLevel1Index();
                field = offerList.level1[index].clean();
                local = local.level1(field);
              }
            }
            if (shouldUpdateBranch) {
              index = field.firstLevel2Index(index);
              field = offerList.level2[index].clean();
              local = local.level2(field);
            }
          }
          if (shouldUpdateBranch) {
            index = field.firstLevel3Index(index);
            field = offerList.level3[index].clean();
            local = local.level3(field);
          }
        }
        if (shouldUpdateBranch) {
          leaf = offerList.leafs[field.firstLeafIndex(index)].clean();
        }
      }
      if (shouldUpdateBranch) {
        local = local.binPosInLeaf(leaf.firstOfferPosition());
      }
    }
    return (local, shouldUpdateBranch);
  }
}
