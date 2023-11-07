// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import "@mgv/src/core/MgvLib.sol";
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

  /* When an offer is deleted, it is marked as such by setting `gives` to 0 and leaving other fields intact. Note that provision accounting in Mangrove aims to minimize writes. Each maker `fund`s Mangrove to increase its balance. When an offer is created/updated, we compute how much should be reserved to pay for possible penalties. That amount can always be recomputed with

  
  ```
  offerDetail.gasprice * 1e6 * (offerDetail.gasreq + offerDetail.offer_gasbase)
  ``` 
  
  The balance is updated to reflect the remaining available ethers.

     Now, when an offer is deleted, the offer can stay provisioned, or be `deprovision`ed. In the latter case, we set `gasprice` to 0, which induces a provision of 0. All code calling `dirtyDeleteOffer` with `deprovision` set to `true` must be careful to correctly account for where that provision is going (back to the maker's `balanceOf`, or sent to a taker as compensation). */
  function dirtyDeleteOffer(OfferData storage offerData, Offer offer, OfferDetail offerDetail, bool deprovision)
    internal
  {
    unchecked {
      offer = offer.gives(0);
      if (deprovision) {
        offerDetail = offerDetail.gasprice(0);
      }
      offerData.offer = offer;
      offerData.detail = offerDetail;
    }
  }

  /* ## Removing an offer from the tick tree */

  /* To remove an offer from the tick tree, we do the following:
  - Remove the offer from the bin
  - If the bin is now empty, mark it as empty in its leaf
    - If the leaf is now empty, mark it as empty in its level3
      - If the level3 is now empty, mark it as empty in its level2
        - If the level2 is now empty, mark it as empty in its level1
          - If the level1 is now empty, mark it as empty in the root
            - If the root is now empty, return
  - Once we are done marking leaves/fields as empty, if the removed offer was the best there is at least one remaining offer, and if the caller requested it by setting `shouldUpdateBranch=true`, go down the tree and find the new best offer.

  Each step must take into account the fact that the branch of the best offer is cached in `local`, and that loading a new best offer requires caching a different branch in `local`.

  The reason why the caller might set `shouldUpdateBranch=false` is that it is itself about to insert an offer better than the current best offer. In that case, it will take care of caching the branch of the new best offer after calling `dislodgeOffer`.

  The new updated local is returned, along with whether the branch in local ended up being updated.
  */
  function dislodgeOffer(
    OfferList storage offerList,
    uint tickSpacing,
    Offer offer,
    Local local,
    Bin bestBin,
    bool shouldUpdateBranch
  ) internal returns (Local, bool) {
    unchecked {
      Leaf leaf;
      Bin offerBin = offer.bin(tickSpacing);
      {
        // save stack space
        uint prevId = offer.prev();
        uint nextId = offer.next();
        /* Only load `offer`'s leaf if the offer leaf must be updated. If `offer` is in the middle of a bin's linked list, the bin's first&last offers will not change, so the leaf does not have to be loaded. */
        if (prevId == 0 || nextId == 0) {
          leaf = offerList.leafs[offerBin.leafIndex()].clean();
        }

        /* Update the forward pointer to `offer` (either in a leaf or in an offer's next pointer) */
        if (prevId == 0) {
          /* If `offer` was its bin's first offer, the new first offer is `nextId` (may be 0). */
          leaf = leaf.setBinFirst(offerBin, nextId);
        } else {
          /* Otherwise, the next pointer of `offer`'s prev becomes `nextId`. */
          OfferData storage prevOfferData = offerList.offerData[prevId];
          prevOfferData.offer = prevOfferData.offer.next(nextId);
        }

        /* Update the backward pointer to `offer` (either in a leaf or in an offer's prev pointer) */
        if (nextId == 0) {
          /* If `offer` was its bin's last offer, the new last offer is `prevId` (may be 0). */
          leaf = leaf.setBinLast(offerBin, prevId);
        } else {
          /* Otherwise, the prev pointer of `offer`'s next becomes `prevId`. */
          OfferData storage nextOfferData = offerList.offerData[nextId];
          nextOfferData.offer = nextOfferData.offer.prev(prevId);
        }

        /* If previous pointer updates only updated offer pointers, `offer`'s leaf has not changed and we can return early */
        if (prevId != 0 && nextId != 0) {
          return (local, false);
        }

        /* Only plan on updating the branch if the caller requested it and if `offer` is the best. */
        shouldUpdateBranch = shouldUpdateBranch && prevId == 0 && !bestBin.strictlyBetter(offerBin);
      }

      /* Since `offer` was the first or last of its bin, its leaf must be updated */
      offerList.leafs[offerBin.leafIndex()] = leaf.dirty();
      /* If the leaf is now empty, flip off its bit in `offer`'s level3 */
      if (leaf.isEmpty()) {
        /* We reuse the same `index` variable for all 3 level indices and for the leaf index. */
        int index = offerBin.level3Index();
        /* We reuse the same `field` variable for all 3 level indices. */
        Field field;
        /* _Local cache management conditional_ */
        if (index == bestBin.level3Index()) {
          /* If `offer`'s level3 is cached, update it in `local`. */
          field = local.level3().flipBitAtLevel3(offerBin);
          local = local.level3(field);
          /* If `shouldUpdateBranch=true` and the level3 is now empty, another level3 may take its place. We immediately evict the empty value of level3 to storage. (If the level3 is not empty, then the new best offer will use that level3, so no eviction necessary). */
          if (shouldUpdateBranch && field.isEmpty()) {
            /* Clean/dirty management. `if`s are nested to avoid a useless SLOAD. */
            if (!offerList.level3s[index].eq(DirtyFieldLib.CLEAN_EMPTY)) {
              offerList.level3s[index] = DirtyFieldLib.DIRTY_EMPTY;
            }
          }
        } else {
          /* If `offer`'s level3 is not cached, update it in storage. */
          field = offerList.level3s[index].clean().flipBitAtLevel3(offerBin);
          offerList.level3s[index] = field.dirty();
        }
        /* If `offer`'s level3 is now empty, flip off its bit in the removed offer's level2 */
        if (field.isEmpty()) {
          index = offerBin.level2Index();
          /* _Local cache management conditional_ */
          if (index == bestBin.level2Index()) {
            /* If `offer`'s level2 is cached, update it in `local`. */
            field = local.level2().flipBitAtLevel2(offerBin);
            local = local.level2(field);
            /* If `shouldUpdateBranch=true` and the level2 is now empty, another level2 may take its place. We immediately evict the empty value of level2 to storage. (If the level2 is not empty, then the new best offer will use that level2, so no eviction necessary). */
            if (shouldUpdateBranch && field.isEmpty()) {
              /* Clean/dirty management. Ifs are nested to avoid a useless SLOAD. */
              if (!offerList.level2s[index].eq(DirtyFieldLib.CLEAN_EMPTY)) {
                offerList.level2s[index] = DirtyFieldLib.DIRTY_EMPTY;
              }
            }
          } else {
            /* If `offer`'s level2 is not cached, update it in storage. */
            field = offerList.level2s[index].clean().flipBitAtLevel2(offerBin);
            offerList.level2s[index] = field.dirty();
          }
          /* If `offer`'s level2 is now empty, flip off its bit in `offer`'s level1 */
          if (field.isEmpty()) {
            index = offerBin.level1Index();
            /* _Local cache management conditional_ */
            if (index == bestBin.level1Index()) {
              /* If `offer`'s level1 is cached, update it in `local`. */
              field = local.level1().flipBitAtLevel1(offerBin);
              local = local.level1(field);
              /* If `shouldUpdateBranch=true` and the level1 is now empty, another level1 may take its place. We immediately evict the empty value of level1 to storage. (If the level1 is not empty, then the new best offer will use that level1, so no eviction necessary). */
              if (shouldUpdateBranch && field.isEmpty()) {
                /* Unlike with level3 and level2, level1 cannot be `CLEAN_EMPTY` (it gets dirtied in `activate`) */
                offerList.level1s[index] = field.dirty();
              }
            } else {
              /* If `offer`'s level1 is not cached, update it in storage. */
              field = offerList.level1s[index].clean().flipBitAtLevel1(offerBin);
              offerList.level1s[index] = field.dirty();
            }
            /* If `offer`'s level1 is now empty, flip off its bit in the root field. */
            if (field.isEmpty()) {
              /* root is always in `local` */
              field = local.root().flipBitAtRoot(offerBin);
              local = local.root(field);

              /* If the root is now empty, return the updated `local` */
              if (field.isEmpty()) {
                return (local, shouldUpdateBranch);
              }
              /* Since `offer`'s level1 became empty, if we have to update the branch, load the level1 containing the new best offer in `local`. */
              if (shouldUpdateBranch) {
                index = field.firstLevel1Index();
                field = offerList.level1s[index].clean();
                local = local.level1(field);
              }
            }
            /* Since `offer`'s level2 became empty, if we have to update the branch, load the level2 containing the new best offer in `local`. */
            if (shouldUpdateBranch) {
              index = field.firstLevel2Index(index);
              field = offerList.level2s[index].clean();
              local = local.level2(field);
            }
          }
          /* Since `offer`'s level3 became empty, if we have to update the branch, load the level3 containing the new best offer in `local`. */
          if (shouldUpdateBranch) {
            index = field.firstLevel3Index(index);
            field = offerList.level3s[index].clean();
            local = local.level3(field);
          }
        }
        /* Since `offer`'s leaf became empty, if we have to update the branch, load the leaf containing the new best offer in `leaf` (so that we can find the position of the first non-empty bin in the leaf). */
        if (shouldUpdateBranch) {
          leaf = offerList.leafs[field.firstLeafIndex(index)].clean();
        }
      }
      /* Since `offer`'s bin became empty if we have to update the branch, load the position of the first non-empty bin in the current leaf in `local`. */
      if (shouldUpdateBranch) {
        local = local.binPosInLeaf(leaf.bestNonEmptyBinPos());
      }
    }
    return (local, shouldUpdateBranch);
  }
}
