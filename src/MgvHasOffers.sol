// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {
  MgvLib,
  HasMgvEvents,
  IMgvMonitor,
  MgvStructs,
  Field,
  Leaf,
  Tick,
  LEVEL2_SIZE,
  LEVEL1_SIZE,
  LEVEL0_SIZE,
  OLKey
} from "./MgvLib.sol";
import {MgvCommon} from "./MgvCommon.sol";

/* `MgvHasOffers` contains the state variables and functions common to both market-maker operations and market-taker operations. Mostly: storing offers, removing them, updating market makers' provisions. */
contract MgvHasOffers is MgvCommon {
  /*
  # Gatekeeping

  Gatekeeping functions are safety checks called in various places.
  */

  /* `unlockedMarketOnly` protects modifying the market while an order is in progress. Since external contracts are called during orders, allowing reentrancy would, for instance, let a market maker replace offers currently on the book with worse ones. Note that the external contracts _will_ be called again after the order is complete, this time without any lock on the market.  */
  function unlockedMarketOnly(MgvStructs.LocalPacked local) internal pure {
    require(!local.lock(), "mgv/reentrancyLocked");
  }

  /* <a id="Mangrove/definition/liveMgvOnly"></a>
     In case of emergency, Mangrove can be `kill`ed. It cannot be resurrected. When a Mangrove is dead, the following operations are disabled :
       * Executing an offer
       * Sending ETH to Mangrove the normal way. Usual [shenanigans](https://medium.com/@alexsherbuck/two-ways-to-force-ether-into-a-contract-1543c1311c56) are possible.
       * Creating a new offer
   */
  function liveMgvOnly(MgvStructs.GlobalPacked _global) internal pure {
    require(!_global.dead(), "mgv/dead");
  }

  /* When Mangrove is deployed, all offerLists are inactive by default (since `locals[outbound_tkn][inbound_tkn]` is 0 by default). Offers on inactive offerLists cannot be taken or created. They can be updated and retracted. */
  function activeMarketOnly(MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local) internal pure {
    liveMgvOnly(_global);
    require(_local.active(), "mgv/inactive");
  }

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
    uint tickScale,
    MgvStructs.OfferPacked offer,
    MgvStructs.LocalPacked local,
    bool shouldUpdateBranch
  ) internal returns (MgvStructs.LocalPacked) {
    unchecked {
      Leaf leaf;
      uint prevId = offer.prev();
      uint nextId = offer.next();
      Tick offerTick = offer.tick(tickScale);
      if (prevId == 0 || nextId == 0) {
        leaf = offerList.leafs[offerTick.leafIndex()];
      }

      // if current tick is not strictly better,
      // time to look for a new current tick
      // NOTE: I used to name this var "shouldUpdateTick" and add "&& (prevId == 0 && nextId == 0)" because tick has not changed if you are not removing the last offer of a tick. But for now i want to return the NEW BEST (for compatibility reasons). Will edit later.
      // note: adding offerId as an arg would let us replace
      // prevId == 0 && !local.tick.strictlyBetter(offerTick)
      // with
      // offerId == local.best() (but best will maybe go away in the future)

      // If shouldUpdateBranch is false is means we are about to insert anyway, so no need to load the best branch right now
      // if local.tick < offerTick then a better branch is already cached. note that local.tick >= offerTick implies local.tick = offerTick
      // no need to check for prevId/nextId == 0: if offer is last of leaf, it will be checked by leaf.isEmpty()
      shouldUpdateBranch = shouldUpdateBranch && prevId == 0 && !local.bestTick().strictlyBetter(offerTick);

      if (prevId == 0) {
        // offer was tick's first. new first offer is offer.next (may be 0)
        leaf = leaf.setTickFirst(offerTick, nextId);
      } else {
        // offer.prev's next becomes offer.next
        OfferData storage prevOfferData = offerList.offerData[prevId];
        prevOfferData.offer = prevOfferData.offer.next(nextId);
      }

      if (nextId == 0) {
        // offer was tick's last. new last offer is offer.prev (may be 0)
        leaf = leaf.setTickLast(offerTick, prevId);
      } else {
        // offer.next's prev becomes offer.prev
        OfferData storage nextOfferData = offerList.offerData[nextId];
        nextOfferData.offer = nextOfferData.offer.prev(prevId);
      }

      if (prevId == 0 || nextId == 0) {
        // offer.tick's first or last offer changed, must update leaf
        offerList.leafs[offerTick.leafIndex()] = leaf;
        // if leaf now empty, flip ticks OFF up the tree
        if (leaf.isEmpty()) {
          int index = offerTick.level0Index(); // level0Index or level1Index
          Field field;
          if (index == local.bestTick().level0Index()) {
            field = local.level0().flipBitAtLevel0(offerTick);
            local = local.level0(field);
            if (shouldUpdateBranch && field.isEmpty()) {
              offerList.level0[index] = field;
            }
          } else {
            field = offerList.level0[index].flipBitAtLevel0(offerTick);
            offerList.level0[index] = field;
          }
          if (field.isEmpty()) {
            index = offerTick.level1Index(); // level0Index or level1Index
            if (index == local.bestTick().level1Index()) {
              field = local.level1().flipBitAtLevel1(offerTick);
              local = local.level1(field);
              if (shouldUpdateBranch && field.isEmpty()) {
                offerList.level1[index] = field;
              }
            } else {
              field = offerList.level1[index].flipBitAtLevel1(offerTick);
              offerList.level1[index] = field;
            }
            if (field.isEmpty()) {
              local = local.level2(local.level2().flipBitAtLevel2(offerTick));

              // FIXME: should I let log2 not revert, but just return 0 if x is 0?
              // Why am I setting tick to 0 before I return?
              if (local.level2().isEmpty()) {
                return local;
              }
              // no need to check for level2.isEmpty(), if it's the case then shouldUpdateBranch is false, because the
              if (shouldUpdateBranch) {
                index = local.level2().firstLevel1Index();
                field = offerList.level1[index];
                local = local.level1(field);
              }
            }
            if (shouldUpdateBranch) {
              index = field.firstLevel0Index(index);
              field = offerList.level0[index];
              local = local.level0(field);
            }
          }
          if (shouldUpdateBranch) {
            leaf = offerList.leafs[field.firstLeafIndex(index)];
          }
        }
        if (shouldUpdateBranch) {
          local = local.tickPosInLeaf(leaf.firstOfferPosition());
        }
      }
      return local;
    }
  }
}
