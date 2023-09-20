// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {
  MgvLib,
  HasMgvEvents,
  IMgvMonitor,
  MgvStructs,
  Field,
  Leaf,
  TickTreeIndex,
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
    TickTreeIndex bestTickTreeIndex,
    bool shouldUpdateBranch
  ) internal returns (MgvStructs.LocalPacked, bool) {
    unchecked {
      Leaf leaf;
      TickTreeIndex offerTickTreeIndex = offer.tickTreeIndex(tickSpacing);
      // save stack space
      {
        uint prevId = offer.prev();
        uint nextId = offer.next();
        if (prevId == 0 || nextId == 0) {
          leaf = offerList.leafs[offerTickTreeIndex.leafIndex()].clean();
        }

        // if current tickTreeIndex is not strictly better,
        // time to look for a new current tick
        // NOTE: I used to name this var "shouldUpdateTickTreeIndex" and add "&& (prevId == 0 && nextId == 0)" because tickTreeIndex has not changed if you are not removing the last offer of a tickTreeIndex. But for now i want to return the NEW BEST (for compatibility reasons). Will edit later.
        // note: adding offerId as an arg would let us replace
        // prevId == 0 && !local.tickTreeIndex.strictlyBetter(offerTickTreeIndex)
        // with
        // offerId == local.best() (but best will maybe go away in the future)

        // If shouldUpdateBranch is false is means we are about to insert anyway, so no need to load the best branch right now
        // if local.tickTreeIndex < offerTickTreeIndex then a better branch is already cached. note that local.tickTreeIndex >= offerTickTreeIndex implies local.tickTreeIndex = offerTick
        // no need to check for prevId/nextId == 0: if offer is last of leaf, it will be checked by leaf.isEmpty()
        shouldUpdateBranch = shouldUpdateBranch && prevId == 0 && !bestTickTreeIndex.strictlyBetter(offerTickTreeIndex);

        if (prevId == 0) {
          // offer was tick's first. new first offer is offer.next (may be 0)
          leaf = leaf.setTickTreeIndexFirst(offerTickTreeIndex, nextId);
        } else {
          // offer.prev's next becomes offer.next
          OfferData storage prevOfferData = offerList.offerData[prevId];
          prevOfferData.offer = prevOfferData.offer.next(nextId);
        }

        if (nextId == 0) {
          // offer was tick's last. new last offer is offer.prev (may be 0)
          leaf = leaf.setTickTreeIndexLast(offerTickTreeIndex, prevId);
        } else {
          // offer.next's prev becomes offer.prev
          OfferData storage nextOfferData = offerList.offerData[nextId];
          nextOfferData.offer = nextOfferData.offer.prev(prevId);
        }
        if (prevId != 0 && nextId != 0) {
          return (local, shouldUpdateBranch);
        }
      }

      // offer.tickTreeIndex's first or last offer changed, must update leaf
      offerList.leafs[offerTickTreeIndex.leafIndex()] = leaf.dirty();
      // if leaf now empty, flip ticks OFF up the tree
      if (leaf.isEmpty()) {
        int index = offerTickTreeIndex.level0Index(); // level0Index or level1Index
        Field field;
        if (index == bestTickTreeIndex.level0Index()) {
          field = local.level0().flipBitAtLevel0(offerTickTreeIndex);
          local = local.level0(field);
          if (shouldUpdateBranch && field.isEmpty()) {
            if (!offerList.level0[index].eq(DirtyFieldLib.CLEAN_EMPTY)) {
              offerList.level0[index] = DirtyFieldLib.DIRTY_EMPTY;
            }
          }
        } else {
          // note: useless dirty/clean cycle here
          field = offerList.level0[index].clean().flipBitAtLevel0(offerTickTreeIndex);
          offerList.level0[index] = field.dirty();
        }
        if (field.isEmpty()) {
          index = offerTickTreeIndex.level1Index(); // level0Index or level1Index
          if (index == bestTickTreeIndex.level1Index()) {
            field = local.level1().flipBitAtLevel1(offerTickTreeIndex);
            local = local.level1(field);
            if (shouldUpdateBranch && field.isEmpty()) {
              if (!offerList.level1[index].eq(DirtyFieldLib.CLEAN_EMPTY)) {
                offerList.level1[index] = DirtyFieldLib.DIRTY_EMPTY;
              }
            }
          } else {
            // note: useless dirty/clean cycle here
            field = offerList.level1[index].clean().flipBitAtLevel1(offerTickTreeIndex);
            offerList.level1[index] = field.dirty();
          }
          if (field.isEmpty()) {
            index = offerTickTreeIndex.level2Index(); // level0Index or level1Index
            if (index == bestTickTreeIndex.level2Index()) {
              field = local.level2().flipBitAtLevel2(offerTickTreeIndex);
              local = local.level2(field);
              if (shouldUpdateBranch && field.isEmpty()) {
                // unlike level0&1, level2 cannot be CLEAN_EMPTY (dirtied in active())
                offerList.level2[index] = field.dirty();
              }
            } else {
              // note: useless dirty/clean cycle here
              field = offerList.level2[index].clean().flipBitAtLevel2(offerTickTreeIndex);
              offerList.level2[index] = field.dirty();
            }
            if (field.isEmpty()) {
              field = local.root().flipBitAtRoot(offerTickTreeIndex);
              local = local.root(field);

              if (field.isEmpty()) {
                return (local, shouldUpdateBranch);
              }
              if (shouldUpdateBranch) {
                index = field.firstLevel2Index();
                field = offerList.level2[index].clean();
                local = local.level2(field);
              }
            }
            if (shouldUpdateBranch) {
              index = field.firstLevel1Index(index);
              field = offerList.level1[index].clean();
              local = local.level1(field);
            }
          }
          if (shouldUpdateBranch) {
            index = field.firstLevel0Index(index);
            field = offerList.level0[index].clean();
            local = local.level0(field);
          }
        }
        if (shouldUpdateBranch) {
          leaf = offerList.leafs[field.firstLeafIndex(index)].clean();
        }
      }
      if (shouldUpdateBranch) {
        local = local.tickTreeIndexPosInLeaf(leaf.firstOfferPosition());
      }
    }
    return (local, shouldUpdateBranch);
  }
}
