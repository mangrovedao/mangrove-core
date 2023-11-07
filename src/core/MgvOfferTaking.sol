// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import "./MgvLib.sol";
import {MgvHasOffers} from "./MgvHasOffers.sol";
import {TickTreeLib} from "@mgv/lib/core/TickTreeLib.sol";

/* There are 2 ways to take offers in Mangrove:
- **Market order**. A market order walks the offer list from the best offer and up, can specify a limit price, as well as a buy/sell behaviour (i.e. whether to limit the order buy the amount bought or by the amount sold).
- **Clean**. Since offers can fail, bots can 'clean' specific offers and walk away with the bounty. If an offer does not fail, cleaning it reverts and leaves it in place.
*/
abstract contract MgvOfferTaking is MgvHasOffers {
  /* # MultiOrder struct */
  /* The `MultiOrder` struct is used by market orders and cleans. Some of its fields are only used by market orders. We need a common data structure for both since low-level calls are shared between market orders and cleans. The struct is helpful in decreasing stack use. */
  struct MultiOrder {
    uint totalGot; // used globally by market order, per-offer by cleans
    uint totalGave; // used globally by market order, per-offer by cleans
    uint totalPenalty; // used globally
    address taker; // used globally
    bool fillWants; // used globally
    uint fillVolume; // used globally
    uint feePaid; // used globally
    Leaf leaf; // used by market order
    Tick maxTick; // used globally
    uint maxGasreqForFailingOffers; // used by market order
    uint gasreqForFailingOffers; // used by market order
    uint maxRecursionDepth; // used by market order
  }

  /* # Market Orders */

  /* ## Market Order */
  //+clear+

  /* A market order specifies a (`outbound`, `inbound`,`tickSpacing`) offer list, a limit price it is ready to pay (in the form of `maxTick`, the log base 1.0001 of the price), and a volume `fillVolume`. If `fillWants` is true, that volume is the amount of `olKey.outbound_tkn` the taker wants to buy. If `fillWants` is false, that volume is the amount of `olKey.inbound_tkn` the taker wants to sell.
  
  It returns four `uint`s: the total amount of `olKey.outbound_tkn` received, the total amount of `olKey.inbound_tkn` spent, the penalty received by msg.sender (in wei), and the fee paid by the taker (in wei of `olKey.outbound_tkn`).


  The market order stops when the price exceeds (an approximation of) 1.0001^`maxTick`, or when the end of the book has been reached, or:
  * If `fillWants` is true, the market order stops when `fillVolume` units of `olKey.outbound_tkn` have been obtained. To buy a specific volume of `olKey.outbound_tkn` at any price, set `fillWants` to true, set `fillVolume` to volume you want to buy, and set `maxTick` to the `MAX_TICK` constant.
  * If `fillWants` is false, the market order stops when `fillVolume` units of `olKey.inbound_tkn` have been paid. To sell a specific volume of `olKey.inbound_tkn` at any price, set `fillWants` to false, set `fillVolume` to the volume you want to sell, and set `maxTick` to the `MAX_TICK` constant.
  
  For a maximum `fillVolume` and a maximum (when `fillWants=true`) or minimum (when `fillWants=false`) price, the taker can end up receiving a volume of about `2**255` tokens. */

  function marketOrderByTick(OLKey memory olKey, Tick maxTick, uint fillVolume, bool fillWants)
    public
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid)
  {
    unchecked {
      return generalMarketOrder(olKey, maxTick, fillVolume, fillWants, msg.sender, 0);
    }
  }

  /* There is a `ByVolume` variant where the taker specifies a desired total amount of `olKey.outbound_tkn` tokens (`takerWants`), and an available total amount of `olKey.inbound_tkn` (`takerGives`). Volumes should fit on 127 bits. */
  function marketOrderByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants)
    public
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid)
  {
    uint fillVolume = fillWants ? takerWants : takerGives;
    Tick maxTick = TickLib.tickFromVolumes(takerGives, takerWants);
    return generalMarketOrder(olKey, maxTick, fillVolume, fillWants, msg.sender, 0);
  }

  /* If the offer list is filled with failing offers such that the default `maxGasreqForFailingOffers` is inadequate, this version of the market order lets the taker specify an upper bound on the gas they are ready to spend on failing offers. */
  function marketOrderByTickCustom(
    OLKey memory olKey,
    Tick maxTick,
    uint fillVolume,
    bool fillWants,
    uint maxGasreqForFailingOffers
  ) public returns (uint takerGot, uint takerGave, uint bounty, uint feePaid) {
    unchecked {
      return generalMarketOrder(olKey, maxTick, fillVolume, fillWants, msg.sender, maxGasreqForFailingOffers);
    }
  }

  /* Get offer after current offer. Will also remove the current offer and return the corresponding updated `local`.

  During a market order, once an offer has been executed, the next one must be fetched. Since offers are structured in a tick tree, the next offer might be:
  - In the same bin, referred to by the `currentOffer.next` pointer.
  - In the same leaf, but in another bin.
  - In a bin that descend from the same level3 but not the same leaf.
  - In a bin that descend from the same level2 but not the same level3.
  - In a bin that descend from the same level1 but not the same level1.
  - In a bin that descend from a different level1.
  Or there might not be a next offer.

  In any case, the 'current branch' is now the branch of the next offer, so `local` must be updated.

  `getNextBest` returns the id of the next offer if there is one (and id 0 otherwise), as well as the updated `local`.

  However, this function is very unsafe taken in isolation:
  - it does not update offer pointers. Since a market order repeatedly calls it and does not inspect the .prev of an offer, the optimization is correct as long as the market order updates the prev pointer of the last offer it sees to 0. After a call, it is your responsibility to do:
      ```
      OfferData storage = offerList.offerData[offerId];
      offerData.offer = offer.prev(0);
      ```
  - it does not flush an updated leaf to storage unless the current leaf has become empty and it needs to load a new one. After a call, it is your responsibility to write the new leaf to storage, if necessary.
  */
  function getNextBest(OfferList storage offerList, MultiOrder memory mor, Offer offer, Local local, uint tickSpacing)
    internal
    returns (uint offerId, Local)
  {
    /* Get tick from current offer tick and tickSpacing */
    Bin offerBin = offer.bin(tickSpacing);
    uint nextId = offer.next();

    /* Update the bin's first offer. If nextId is 0, then the bin's last offer will be updated immediately after. */
    Leaf leaf = mor.leaf;
    leaf = leaf.setBinFirst(offerBin, nextId);

    /* If the current bin is now empty, we go up the tick tree to find the next offer. */
    if (nextId == 0) {
      /* Mark the bin as empty. */
      leaf = leaf.setBinLast(offerBin, 0);
      /* If the current leaf is now empty, we keep going up the tick tree. */
      if (leaf.isEmpty()) {
        /* Flush the current empty leaf since we will load a new one. Note that the slot cannot be empty since we just emptied the leaf (and unlike fields, leaves don't stay cached in another slot). */
        offerList.leafs[offerBin.leafIndex()] = leaf.dirty();

        /* We reuse the same `field` variable for all 3 level indices. */
        Field field = local.level3().flipBitAtLevel3(offerBin);
        /* We reuse the same `index` variable for all 3 level indices and for the leaf index. */
        int index = offerBin.level3Index();
        /* If the current level3 is now empty, we keep going up the tick tree. */
        if (field.isEmpty()) {
          /* Flush the current empty level3 since we will load a new one. We avoid the write if the slot is already cleanly empty. */
          if (!offerList.level3s[index].eq(DirtyFieldLib.CLEAN_EMPTY)) {
            offerList.level3s[index] = DirtyFieldLib.DIRTY_EMPTY;
          }
          index = offerBin.level2Index();
          field = local.level2().flipBitAtLevel2(offerBin);
          /* If the current level2 is now empty, we keep going up the tick tree. */
          if (field.isEmpty()) {
            /* Flush the current empty level2 since we will load a new one. We avoid the write if the slot is already cleanly empty. */
            if (!offerList.level2s[index].eq(DirtyFieldLib.CLEAN_EMPTY)) {
              offerList.level2s[index] = DirtyFieldLib.DIRTY_EMPTY;
            }
            index = offerBin.level1Index();
            field = local.level1().flipBitAtLevel1(offerBin);
            /* If the current level1 is now empty, we keep going up the tick tree. */
            if (field.isEmpty()) {
              /* Flush the current empty level1 since we will load a new one. Unlike with level2 and level3, level1 cannot be `CLEAN_EMPTY` (it gets dirtied in `activate`) */
              offerList.level1s[index] = DirtyFieldLib.DIRTY_EMPTY;
              field = local.root().flipBitAtRoot(offerBin);
              local = local.root(field);
              /* If the root is now empty, we mark all fields in local and the current leaf as empty and return the 0 offer id. */
              if (field.isEmpty()) {
                local = local.level1(field);
                local = local.level2(field);
                local = local.level3(field);
                mor.leaf = LeafLib.EMPTY;
                return (0, local);
              }
              /* Last level1 was empty, load the new level1 */
              index = field.firstLevel1Index();
              // Low-level optim: avoid dirty/clean cycle, dirty bit will be erased anyway.
              field = Field.wrap(DirtyField.unwrap(offerList.level1s[index]));
            }
            /* Store current level1 in `local`. */
            local = local.level1(field);
            /* Last level2 was empty, load the new level2 */
            index = field.firstLevel2Index(index);
            // Low-level optim: avoid dirty/clean cycle, dirty bit will be erased anyway.
            field = Field.wrap(DirtyField.unwrap(offerList.level2s[index]));
          }
          /* Store current level2 in `local`. */
          local = local.level2(field);
          /* Last level3 was empty, load the new level3 */
          index = field.firstLevel3Index(index);
          // Low-level optim: avoid dirty/clean cycle, dirty bit will be erased anyway.
          field = Field.wrap(DirtyField.unwrap(offerList.level3s[index]));
        }
        /* Store current level3 in `local`. */
        local = local.level3(field);
        /* Last leaf was empty, load the new leaf. */
        leaf = offerList.leafs[field.firstLeafIndex(index)].clean();
      }
      /* Find the position of the best non-empty bin in the current leaf, save it to `local`, and read the first offer id of that bin. */
      uint bestNonEmptyBinPos = leaf.bestNonEmptyBinPos();
      local = local.binPosInLeaf(bestNonEmptyBinPos);
      nextId = leaf.firstOfPos(bestNonEmptyBinPos);
    }
    mor.leaf = leaf;
    return (nextId, local);
  }
  /* # General Market Order */
  //+clear+
  /* General market orders set up the market order with a given `taker` (`msg.sender` in the most common case). Returns `(totalGot, totalGave, penaltyReceived, feePaid)`.
  Note that the `taker` can be anyone. This is safe when `taker == msg.sender`, but `generalMarketOrder` must not be called with `taker != msg.sender` unless a security check is done after (see [`MgvOfferTakingWithPermit`](#mgvoffertakingwithpermit.sol)`. */

  function generalMarketOrder(
    OLKey memory olKey,
    Tick maxTick,
    uint fillVolume,
    bool fillWants,
    address taker,
    uint maxGasreqForFailingOffers
  ) internal returns (uint takerGot, uint takerGave, uint bounty, uint feePaid) {
    unchecked {
      /* Checking that `fillVolume` fits in 127 ensures no overflow during the market order recursion. */
      require(fillVolume <= MAX_SAFE_VOLUME, "mgv/mOrder/fillVolume/tooBig");
      require(maxTick.inRange(), "mgv/mOrder/tick/outOfRange");

      /* `MultiOrder` (defined above) maintains information related to the entire market order. */
      MultiOrder memory mor;
      mor.maxTick = maxTick;
      mor.taker = taker;
      mor.fillWants = fillWants;

      /* `SingleOrder` is defined in `MgvLib.sol` and holds information related to the execution of one offer. It also contains `olKey`, which concerns the entire market order, because it will be sent to the maker, who needs that information. */
      MgvLib.SingleOrder memory sor;
      sor.olKey = olKey;
      OfferList storage offerList;
      (sor.global, sor.local, offerList) = _config(olKey);
      mor.maxRecursionDepth = sor.global.maxRecursionDepth();
      /* We have an upper limit on total gasreq for failing offers to avoid failing offers delivering nothing and exhausting gaslimit for the transaction. */
      mor.maxGasreqForFailingOffers =
        maxGasreqForFailingOffers > 0 ? maxGasreqForFailingOffers : sor.global.maxGasreqForFailingOffers();

      /* Throughout the execution of the market order, the `sor`'s offer id and other parameters will change. We start with the current best offer id (0 if the book is empty). */

      mor.leaf = offerList.leafs[sor.local.bestBin().leafIndex()].clean();
      sor.offerId = mor.leaf.bestOfferId();
      sor.offer = offerList.offerData[sor.offerId].offer;

      /* Throughout the market order, `fillVolume` represents the amount left to buy (if `fillWants`) or sell (if `!fillWants`). */
      mor.fillVolume = fillVolume;

      /* For the market order to start, the offer list needs to be both active, and not currently protected from reentrancy. */
      activeOfferListOnly(sor.global, sor.local);
      unlockedOfferListOnly(sor.local);

      /* ### Initialization */
      /* The market order will operate as follows : it will go through offers from best to worse, starting from `offerId`, and: */
      /* keep an up-to-date `fillVolume`.
       * not set `prev`/`next` pointers to their correct locations at each offer taken (this is an optimization enabled by forbidding reentrancy).
       * after consuming a segment of offers, will update the current `best` offer to be the best remaining offer on the book. */

      /* We start be enabling the reentrancy lock for this (`olKey.outbound_tkn`,`olKey.inbound_tkn`, `olKey.tickSpacing`) offer list. */
      sor.local = sor.local.lock(true);
      offerList.local = sor.local;

      emit OrderStart(sor.olKey.hash(), taker, maxTick, fillVolume, fillWants);

      /* Call recursive `internalMarketOrder` function.*/
      internalMarketOrder(offerList, mor, sor);

      /* Over the course of the market order, a penalty reserved for `msg.sender` has accumulated in `mor.totalPenalty`. No actual transfers have occurred yet -- all the ethers given by the makers as provision are owned by Mangrove. `sendPenalty` finally gives the accumulated penalty to `msg.sender`. */
      sendPenalty(mor.totalPenalty);

      emit OrderComplete(sor.olKey.hash(), taker, mor.feePaid);

      //+clear+
      return (mor.totalGot, mor.totalGave, mor.totalPenalty, mor.feePaid);
    }
  }

  /* ## Internal market order */
  //+clear+
  /* `internalMarketOrder` works recursively. Going downward, each successive offer is executed until the market order stops (due to: volume exhausted, bad price, or empty offer list). Then the [reentrancy lock is lifted](#internalMarketOrder/liftReentrancy). As the recursion unrolls, each offer's `maker` contract is called again with its remaining gas and given the chance to update its offers on the book. */
  function internalMarketOrder(OfferList storage offerList, MultiOrder memory mor, MgvLib.SingleOrder memory sor)
    internal
  {
    unchecked {
      /* The market order proceeds only if the following conditions are all met:
      - there is some volume left to buy/sell
      - the current best offer is not too expensive
      - there is a current best offer
      - we are not too deep in the recursive calls (stack overflow risk)
      - we are not at risk of consuming too much gas because of failing offers
      */
      if (
        mor.fillVolume > 0 && Tick.unwrap(sor.offer.tick()) <= Tick.unwrap(mor.maxTick) && sor.offerId > 0
          && mor.maxRecursionDepth > 0 && mor.gasreqForFailingOffers <= mor.maxGasreqForFailingOffers
      ) {
        /* ### Market order execution */
        mor.maxRecursionDepth--;

        uint gasused; // gas used by `makerExecute`
        bytes32 makerData; // data returned by maker

        /* <a id="MgvOfferTaking/statusCodes"></a> `mgvData` is a Mangrove status code. It appears in an [`OrderResult`](#MgvLib/OrderResult). Its possible values are:
      * `"mgv/tradeSuccess"`: offer execution succeeded.
      * `"mgv/makerRevert"`: execution of `makerExecute` reverted.
      * `"mgv/makerTransferFail"`: maker could not send olKey.outbound_tkn.
      * `"mgv/makerReceiveFail"`: maker could not receive olKey.inbound_tkn.

      `mgvData` should not be exploitable by the maker! */
        bytes32 mgvData;

        /* Load additional information about the offer. */
        sor.offerDetail = offerList.offerData[sor.offerId].detail;

        /* `execute` attempts to execute the offer by calling its maker. `execute` may modify `mor` and `sor`. It is crucial that an error due to `taker` triggers a revert. That way, if [`mgvData`](#MgvOfferTaking/statusCodes) is not `"mgv/tradeSuccess"`, then the maker is at fault. */
        /* Post-execution, `sor.takerWants`/`sor.takerGives` reflect how much was sent/taken by the offer. We will need it after the recursive call, so we save it in local variables. Same goes for `sor.offerId`, `sor.offer` and `sor.offerDetail`. */
        (gasused, makerData, mgvData) = execute(offerList, mor, sor);

        /* Keep cached copy of current `sor` values to restore them later to send to posthook. */
        uint takerWants = sor.takerWants;
        uint takerGives = sor.takerGives;
        uint offerId = sor.offerId;
        Offer offer = sor.offer;
        OfferDetail offerDetail = sor.offerDetail;

        /* If execution was successful, we decrease `fillVolume`. This cannot underflow, see the [`execute` function](#MgvOfferTaking/computeVolume) for details. */
        if (mgvData == "mgv/tradeSuccess") {
          mor.fillVolume -= mor.fillWants ? takerWants : takerGives;
        }

        /* We move `sor` to the next offer. Note that the current state is inconsistent, since we have not yet updated `sor.offerDetails`. */
        (sor.offerId, sor.local) = getNextBest(offerList, mor, offer, sor.local, sor.olKey.tickSpacing);

        sor.offer = offerList.offerData[sor.offerId].offer;

        /* Recursive call with the next offer. */
        internalMarketOrder(offerList, mor, sor);

        /* Restore `sor` values from before recursive call */
        sor.takerWants = takerWants;
        sor.takerGives = takerGives;
        sor.offerId = offerId;
        sor.offer = offer;
        sor.offerDetail = offerDetail;

        /* After an offer execution, we may run callbacks and increase the total penalty. As that part is common to market orders and cleaning, it lives in its own `postExecute` function. */
        postExecute(mor, sor, gasused, makerData, mgvData);
      } else {
        /* ### Market order end */
        Offer offer = sor.offer;
        Bin bin = offer.bin(sor.olKey.tickSpacing);

        /* If the offer list is not empty, the best offer may need a pointer update and the current leaf must be stored: */
        if (sor.offerId != 0) {
          /* 
          If `offer.prev` is 0, we ended the market order right at the beginning of a bin, so no write is necessary. 
          
          This also explains why the update below is safe when a market takes 0 offers: necessarily at this point offer.prev() is 0, since we are looking at the best offer of the offer list.

          **Warning**: do not locally update offer.prev() before this point, or the test wil spuriously fail and the updated offer will never be written to storage. */
          if (offer.prev() != 0) {
            offerList.offerData[sor.offerId].offer = sor.offer.prev(0);
          }

          int index = bin.leafIndex();
          /* This write may not be necessary if the mor.leaf was just loaded in the last `getNextBest`, but it will be a hot storage write anyway (so not expensive). */
          offerList.leafs[index] = mor.leaf.dirty();
        }

        /* <a id="internalMarketOrder/liftReentrancy"></a>Now that the market order is over, we can lift the lock on the book. In the same operation we

      * lift the reentrancy lock, and
      * update the storage

      so we are free from out of order storage writes.
      */
        sor.local = sor.local.lock(false);
        offerList.local = sor.local;

        /* `payTakerMinusFees` keeps the fee in Mangrove, proportional to the amount purchased, and gives the rest to the taker */
        payTakerMinusFees(mor, sor);
      }
    }
  }

  /* # Cleaning */
  /* Cleans multiple offers, i.e. executes them and remove them from the book if they fail, transferring the failure penalty as bounty to the caller. If an offer succeeds, the execution of that offer is reverted, it stays in the book, and no bounty is paid; The `cleanByImpersonation` function itself will not revert.
  
  Its second argument is a `CleanTarget[]` with each `CleanTarget` identifying an offer to clean and the execution parameters that will make it fail. The return values are the number of successfully cleaned offers and the total bounty received.

  Note that Mangrove won't attempt to execute an offer if the values in a `CleanTarget` don't match its offer. To distinguish between a non-executed clean and a fail clean (due to the offer itself not failing), you must inspect the log (see `MgvLib.sol`) or check the received bounty.

  Any `taker` can be impersonated when cleaning because:
  - The function reverts if the offer succeeds, reverting any token transfers.
  - After a `clean` where the offer has failed, all ERC20 token transfers have also been reverted -- but the sender will still have received the bounty of the failing offers. */
  function cleanByImpersonation(OLKey memory olKey, MgvLib.CleanTarget[] calldata targets, address taker)
    external
    returns (uint successes, uint bounty)
  {
    unchecked {
      emit CleanStart(olKey.hash(), taker, targets.length);

      for (uint i = 0; i < targets.length; ++i) {
        bytes memory encodedCall;
        {
          MgvLib.CleanTarget calldata target = targets[i];
          encodedCall = abi.encodeCall(
            this.internalCleanByImpersonation,
            (olKey, target.offerId, target.tick, target.gasreq, target.takerWants, taker)
          );
        }
        bytes memory retdata;
        {
          bool success;
          (success, retdata) = address(this).call(encodedCall);
          if (!success) {
            continue;
          }
        }

        successes++;

        {
          (uint offerBounty) = abi.decode(retdata, (uint));
          bounty += offerBounty;
        }
      }
      sendPenalty(bounty);

      emit CleanComplete();
    }
  }

  function internalCleanByImpersonation(
    OLKey memory olKey,
    uint offerId,
    Tick tick,
    uint gasreq,
    uint takerWants,
    address taker
  ) external returns (uint bounty) {
    unchecked {
      /* `internalClean` must be used with a call (hence the `external` modifier) so its effect can be reverted. But a call from the outside would mean the bounty would get stuck in Mangrove. */
      require(msg.sender == address(this), "mgv/clean/protected");

      MultiOrder memory mor;
      {
        require(tick.inRange(), "mgv/clean/tick/outOfRange");
        mor.maxTick = tick;
      }
      {
        require(takerWants <= MAX_SAFE_VOLUME, "mgv/clean/takerWants/tooBig");
        mor.fillVolume = takerWants;
      }
      mor.taker = taker;
      mor.fillWants = true;

      /* Initialize single order struct. */
      MgvLib.SingleOrder memory sor;
      sor.olKey = olKey;
      OfferList storage offerList;
      (sor.global, sor.local, offerList) = _config(olKey);
      sor.offerId = offerId;
      OfferData storage offerData = offerList.offerData[sor.offerId];
      sor.offer = offerData.offer;
      sor.offerDetail = offerData.detail;

      /* For the cleaning to start, the offer list needs to be both active and not currently protected from reentrancy. */
      activeOfferListOnly(sor.global, sor.local);
      unlockedOfferListOnly(sor.local);

      require(sor.offer.isLive(), "mgv/clean/offerNotLive");
      /* We also check that `gasreq` is not worse than specified. A taker who does not care about `gasreq` can specify any amount larger than the maximum gasreq. */
      require(sor.offerDetail.gasreq() <= gasreq, "mgv/clean/gasreqTooLow");
      require(sor.offer.tick().eq(tick), "mgv/clean/tickMismatch");

      /* We start be enabling the reentrancy lock for this offer list. */
      sor.local = sor.local.lock(true);
      offerList.local = sor.local;

      {
        /* `execute` attempts to execute the offer by calling its maker. `execute` may modify `mor` and `sor`. It is crucial that an error due to `taker` triggers a revert. That way, if [`mgvData`](#MgvOfferTaking/statusCodes) is not `"mgv/tradeSuccess"`, then the maker is at fault. */
        /* Post-execution, `sor.takerWants`/`sor.takerGives` reflect how much was sent/taken by the offer. */
        (uint gasused, bytes32 makerData, bytes32 mgvData) = execute(offerList, mor, sor);

        require(mgvData != "mgv/tradeSuccess", "mgv/clean/offerDidNotFail");

        /* In the market order, we were able to avoid stitching back offers after every `execute` since we knew a segment starting from the best offer would be consumed. Here, we cannot do this optimisation since the offer may be anywhere in the book. So we stitch together offers immediately after `execute`. */
        (sor.local,) = dislodgeOffer(offerList, olKey.tickSpacing, sor.offer, sor.local, sor.local.bestBin(), true);

        /* <a id="internalCleans/liftReentrancy"></a> Now that the current clean is over, we can lift the lock on the book. In the same operation we

        * lift the reentrancy lock, and
        * update the storage

        so we are free from out of order storage writes.
        */
        sor.local = sor.local.lock(false);
        offerList.local = sor.local;

        /* No fees are paid since offer execution failed. */

        /* After an offer execution, we may run callbacks and increase the total penalty. As that part is common to market orders and cleans, it lives in its own `postExecute` function. */
        postExecute(mor, sor, gasused, makerData, mgvData);
      }

      bounty = mor.totalPenalty;
    }
  }

  /* # General execution */
  /* During a market order or a clean, offers get executed. The following code takes care of executing a single offer with parameters given by a `SingleOrder` within a larger context given by a `MultiOrder`. */

  /* ## Execute */
  /* Execution of the offer will be attempted with volume limited by the offer's advertised volume.
     **Warning**: The caller must ensure that the price of the offer is low enough; This is not checked here.

     Summary of the meaning of the return values:
    * `gasused` is the gas consumed by the execution
    * `makerData` is the data returned after executing the offer
    * <a id="MgvOfferTaking/internalStatusCodes"></a>`internalMgvData` is a status code internal to `execute`. It can hold [any value that `mgvData` can hold](#MgvOfferTaking/statusCodes). Within `execute`, it can additionally hold the following values:
      * `"mgv/notEnoughGasForMakerTrade"`: cannot give maker close enough to `gasreq`. Triggers a revert of the entire order.
      * `"mgv/takerTransferFail"`: taker could not send olKey.inbound_tkn. Triggers a revert of the entire order.
  */
  function execute(OfferList storage offerList, MultiOrder memory mor, MgvLib.SingleOrder memory sor)
    internal
    returns (uint gasused, bytes32 makerData, bytes32 internalMgvData)
  {
    unchecked {
      {
        uint fillVolume = mor.fillVolume;
        uint offerGives = sor.offer.gives();
        uint offerWants = sor.offer.wants();
        /* <a id="MgvOfferTaking/computeVolume"></a> Volume requested depends on total gives (or wants) by taker. Let `volume = mor.fillWants ? sor.takerWants : sor.takerGives`. One can check that `volume <= fillVolume` in all cases. 
        
        Example with `fillWants=true`: if `offerGives < fillVolume` the first branch of the outer `if` sets `volume = offerGives` and we are done; otherwise the 1st branch of the inner if is taken and sets `volume = fillVolume` and we are done. */
        if ((mor.fillWants && offerGives <= fillVolume) || (!mor.fillWants && offerWants <= fillVolume)) {
          sor.takerWants = offerGives;
          sor.takerGives = offerWants;
        } else {
          if (mor.fillWants) {
            /* While a possible `offer.wants()=0` is the maker's responsibility, a small enough partial fill may round to 0, so we round up. It is immaterial but more fair to the maker. */
            sor.takerGives = sor.offer.tick().inboundFromOutboundUp(fillVolume);
            sor.takerWants = fillVolume;
          } else {
            sor.takerWants = sor.offer.tick().outboundFromInbound(fillVolume);
            sor.takerGives = fillVolume;
          }
        }
      }
      /* The flashloan is executed by call to `flashloan`. If the call reverts, it means the maker failed to send back `sor.takerWants` units of `olKey.outbound_tkn` to the taker. Notes :
       * `msg.sender` is Mangrove itself in those calls -- all operations related to the actual caller should be done outside of this call.
       * any spurious exception due to an error in Mangrove code will be falsely blamed on the Maker, and its provision for the offer will be unfairly taken away.
       */
      bool success;
      bytes memory retdata;
      {
        /* Clear fields that maker must not see.

        NB: It should be more efficient to do this in `makerExecute` instead as we would not have to restore the fields afterwards.
        However, for unknown reasons that solution consumes significantly more gas, so we do it here instead. */
        Offer offer = sor.offer;
        sor.offer = offer.clearFieldsForMaker();
        Local local = sor.local;
        sor.local = local.clearFieldsForMaker();

        (success, retdata) = address(this).call(abi.encodeCall(this.flashloan, (sor, mor.taker)));

        /* Restore cleared fields */
        sor.offer = offer;
        sor.local = local;
      }

      /* `success` is true: trade is complete */
      if (success) {
        /* In case of success, `retdata` encodes the gas used by the offer, and an arbitrary 256 bits word sent by the maker.  */
        (gasused, makerData) = abi.decode(retdata, (uint, bytes32));
        /* `internalMgvData` indicates trade success */
        internalMgvData = bytes32("mgv/tradeSuccess");

        /* If configured to do so, Mangrove notifies an external contract that a successful trade has taken place. */
        if (sor.global.notify()) {
          IMgvMonitor(sor.global.monitor()).notifySuccess(sor, mor.taker);
        }

        /* We update the totals in the multi order based on the adjusted `sor.takerWants`/`sor.takerGives`. */
        mor.totalGot += sor.takerWants;
        require(mor.totalGot >= sor.takerWants, "mgv/totalGot/overflow");
        mor.totalGave += sor.takerGives;
        require(mor.totalGave >= sor.takerGives, "mgv/totalGot/overflow");
      } else {
        /* In case of failure, `retdata` encodes an [internal status code](#MgvOfferTaking/internalStatusCodes), the gas used by the offer, and an arbitrary 256 bits word sent by the maker.  */
        (internalMgvData, gasused, makerData) = innerDecode(retdata);
        /* Note that in the literals returned are bytes32 (stack values), while the revert arguments are strings (memory pointers). */
        if (
          internalMgvData == "mgv/makerRevert" || internalMgvData == "mgv/makerTransferFail"
            || internalMgvData == "mgv/makerReceiveFail"
        ) {
          /* Update (an upper bound) on gasreq required for failing offers */
          mor.gasreqForFailingOffers += sor.offerDetail.gasreq();
          /* If configured to do so, Mangrove notifies an external contract that a failed trade has taken place. */
          if (sor.global.notify()) {
            IMgvMonitor(sor.global.monitor()).notifyFail(sor, mor.taker);
          }
          /* It is crucial that any error code which indicates an error caused by the taker triggers a revert, because functions that call `execute` consider that when `internalMgvData` is not `"mgv/tradeSuccess"`, then the maker should be blamed. */
        } else if (internalMgvData == "mgv/notEnoughGasForMakerTrade") {
          revert("mgv/notEnoughGasForMakerTrade");
        } else if (internalMgvData == "mgv/takerTransferFail") {
          revert("mgv/takerTransferFail");
        } else {
          /* This code must be unreachable except if the call to flashloan went OOG and there is enough gas to revert here. **Danger**: if a well-crafted offer/maker offer list can force a revert of `flashloan`, Mangrove will be stuck. */
          revert("mgv/swapError");
        }
      }

      /* Delete the offer. The last argument indicates whether the offer should be stripped of its provision (yes if execution failed, no otherwise). We cannot partially strip an offer provision (for instance, remove only the penalty from a failing offer and leave the rest) since the provision associated with an offer is always deduced from the (gasprice,gasbase,gasreq) parameters and not stored independently. We delete offers whether the amount remaining on offer is > density or not for the sake of uniformity (code is much simpler). We also expect prices to move often enough that the maker will want to update their offer anyway. To simulate leaving the remaining volume in the offer, the maker can program their `makerPosthook` to `updateOffer` and put the remaining volume back in. */
      dirtyDeleteOffer(
        offerList.offerData[sor.offerId], sor.offer, sor.offerDetail, internalMgvData != "mgv/tradeSuccess"
      );
    }
  }

  /* ## Flashloan */
  /* Externally called by `execute`, flashloan lends money to the maker then calls `makerExecute` to run the maker liquidity fetching code. If `makerExecute` is unsuccessful, `flashloan` reverts (but the larger orderbook traversal will continue). 

  In detail:
  1. Flashloans `takerGives` units of `sor.olKey.inbound_tkn` from the taker to the maker and returns false if the loan fails.
  2. Runs `offerDetail.maker`'s `execute` function.
  3. Returns the result of the operations, with optional `makerData` to help the maker debug.

  Made virtual so tests can instrument the function.
  */
  function flashloan(MgvLib.SingleOrder calldata sor, address taker)
    external
    virtual
    returns (uint gasused, bytes32 makerData)
  {
    unchecked {
      /* `flashloan` must be used with a call (hence the `external` modifier) so its effect can be reverted. But a call from the outside would be fatal. */
      require(msg.sender == address(this), "mgv/flashloan/protected");
      /* The transfer taker -> maker is in 2 steps. First, taker->mgv. Then
       mgv->maker. With a direct taker->maker transfer, if one of taker/maker
       is blacklisted, we can't tell which one. We need to know which one:
       if we incorrectly blame the taker, a blacklisted maker can block an offer list forever; if we incorrectly blame the maker, a blacklisted taker can unfairly make makers fail all the time. Of course we assume that Mangrove is not blacklisted. This 2-step transfer is incompatible with tokens that have transfer fees (more accurately, it uselessly incurs fees twice). */
      if (transferTokenFrom(sor.olKey.inbound_tkn, taker, address(this), sor.takerGives)) {
        if (transferToken(sor.olKey.inbound_tkn, sor.offerDetail.maker(), sor.takerGives)) {
          (gasused, makerData) = makerExecute(sor);
        } else {
          innerRevert([bytes32("mgv/makerReceiveFail"), bytes32(0), ""]);
        }
      } else {
        innerRevert([bytes32("mgv/takerTransferFail"), "", ""]);
      }
    }
  }

  /* ## Maker Execute */
  /* Called by `flashloan`, `makerExecute` runs the maker code and checks that it can safely send the desired assets to the taker. */

  function makerExecute(MgvLib.SingleOrder calldata sor) internal returns (uint gasused, bytes32 makerData) {
    unchecked {
      bytes memory cd = abi.encodeCall(IMaker.makerExecute, (sor));

      uint gasreq = sor.offerDetail.gasreq();
      address maker = sor.offerDetail.maker();
      uint oldGas = gasleft();
      /* We let the maker pay for the overhead of checking remaining gas and making the call, as well as handling the return data (constant gas since only the first 32 bytes of return data are read). So the `require` below is just an approximation: if the overhead of (`require` + cost of `CALL`) is $h$, the maker will receive at worst $\textrm{gasreq} - \frac{63h}{64}$ gas. */
      if (!(oldGas - oldGas / 64 >= gasreq)) {
        innerRevert([bytes32("mgv/notEnoughGasForMakerTrade"), "", ""]);
      }

      bool callSuccess;
      (callSuccess, makerData) = controlledCall(maker, gasreq, cd);

      gasused = oldGas - gasleft();

      if (!callSuccess) {
        innerRevert([bytes32("mgv/makerRevert"), bytes32(gasused), makerData]);
      }

      bool transferSuccess = transferTokenFrom(sor.olKey.outbound_tkn, maker, address(this), sor.takerWants);

      if (!transferSuccess) {
        innerRevert([bytes32("mgv/makerTransferFail"), bytes32(gasused), makerData]);
      }
    }
  }

  /* ## Post execute */
  /* At this point, we know an offer execution was attempted. After executing an offer (whether in a market order or in cleans), we
     1. Call the maker's posthook and sum the total gas used.
     2. If offer failed: sum total penalty due to msg.sender and give remainder to maker.

     Made virtual so tests can instrument it.
   */
  function postExecute(
    MultiOrder memory mor,
    MgvLib.SingleOrder memory sor,
    uint gasused,
    bytes32 makerData,
    bytes32 mgvData
  ) internal virtual {
    unchecked {
      uint gasreq = sor.offerDetail.gasreq();

      /* We are about to call back the maker, giving it its unused gas (`gasreq - gasused`). Since the gas used so far may exceed `gasreq`, we prevent underflow in the subtraction below by bounding `gasused` above with `gasreq`. We could have decided not to call back the maker at all when there is no gas left, but we do it for uniformity. */
      if (gasused > gasreq) {
        gasused = gasreq;
      }
      (uint posthookGas, bool callSuccess, bytes32 posthookData) =
        makerPosthook(sor, gasreq - gasused, makerData, mgvData);
      gasused = gasused + posthookGas;

      if (mgvData != "mgv/tradeSuccess") {
        uint penalty = applyPenalty(sor, gasused);
        mor.totalPenalty += penalty;
        if (!callSuccess) {
          emit OfferFailWithPosthookData(
            sor.olKey.hash(), mor.taker, sor.offerId, sor.takerWants, sor.takerGives, penalty, mgvData, posthookData
          );
        } else {
          emit OfferFail(sor.olKey.hash(), mor.taker, sor.offerId, sor.takerWants, sor.takerGives, penalty, mgvData);
        }
      } else {
        if (!callSuccess) {
          emit OfferSuccessWithPosthookData(
            sor.olKey.hash(), mor.taker, sor.offerId, sor.takerWants, sor.takerGives, posthookData
          );
        } else {
          emit OfferSuccess(sor.olKey.hash(), mor.taker, sor.offerId, sor.takerWants, sor.takerGives);
        }
      }
    }
  }

  /* ## Maker Posthook */
  function makerPosthook(MgvLib.SingleOrder memory sor, uint gasLeft, bytes32 makerData, bytes32 mgvData)
    internal
    virtual
    returns (uint gasused, bool callSuccess, bytes32 posthookData)
  {
    unchecked {
      bytes memory cd =
        abi.encodeCall(IMaker.makerPosthook, (sor, MgvLib.OrderResult({makerData: makerData, mgvData: mgvData})));

      address maker = sor.offerDetail.maker();

      uint oldGas = gasleft();
      /* We let the maker pay for the overhead of checking remaining gas and making the call. So the `require` below is just an approximation: if the overhead of (`require` + cost of `CALL`) is $h$, the maker will receive at worst $\textrm{gasreq} - \frac{63h}{64}$ gas. */
      if (!(oldGas - oldGas / 64 >= gasLeft)) {
        revert("mgv/notEnoughGasForMakerPosthook");
      }

      (callSuccess, posthookData) = controlledCall(maker, gasLeft, cd);

      gasused = oldGas - gasleft();
    }
  }

  /* ## `controlledCall` */
  /* Calls an external function with controlled gas expense. A direct call of the form `(,bytes memory retdata) = maker.call{gas}(selector,...args)` enables a griefing attack: the maker uses half its gas to write in its memory, then reverts with that memory segment as argument. After a low-level call, solidity automatically copies `returndatasize` bytes of `returndata` into memory. So the total gas consumed to execute a failing offer could exceed `gasreq + offer_gasbase` where `n` is the number of failing offers. In case of success, we read the first 32 bytes of returndata (the signature of `makerExecute` is `bytes32`). Otherwise, for compatibility with most errors that bubble up from contract calls and Solidity's `require`, we read 32 bytes of returndata starting from the 69th (4 bytes of method sig + 32 bytes of offset + 32 bytes of string length). */
  function controlledCall(address callee, uint gasreq, bytes memory cd) internal returns (bool success, bytes32 data) {
    unchecked {
      bytes32[4] memory retdata;

      /* if success, read returned bytes 1..32, otherwise read returned bytes 69..100. */
      assembly ("memory-safe") {
        success := call(gasreq, callee, 0, add(cd, 32), mload(cd), retdata, 100)
        data := mload(add(mul(iszero(success), 68), retdata))
      }
    }
  }

  /* # Penalties */
  /* Offers are just promises. They can fail. Penalty provisioning discourages from failing too much: we ask makers to provision more ETH than the expected gas cost of executing their offer and penalize them according to wasted gas.

     Under normal circumstances, we should expect to see bots with a profit expectation dry-running offers locally and executing `cleans` on failing offers, collecting the penalty. The result should be a mostly clean book for actual takers (i.e. a book with only successful offers).

     **Incentive issue**: if the gas price increases enough after an offer has been created, there may not be an immediately profitable way to remove the fake offers. In that case, we count on 3 factors to keep the book clean:
     1. Gas price eventually comes down.
     2. Other market makers want to keep Mangrove attractive and maintain their offer flow.
     3. Mangrove governance (who may collect a fee) wants to keep Mangrove attractive and maximize exchange volume. */

  //+clear+
  /* After an offer failed, part of its provision is given back to the maker and the rest is stored to be sent to the taker after the entire order completes. In `applyPenalty`, we _only_ credit the maker with its excess provision. So it looks like the maker is gaining something. In fact they're just getting back a fraction of what they provisioned earlier. */
  /*
     Penalty application summary:

   * If the transaction was a success, we entirely refund the maker and send nothing to the taker.
   * Otherwise, the maker loses the cost of `gasused + offer_gasbase` gas. The gas price is estimated by `gasprice`.
   * To create the offer, the maker had to provision for `gasreq + offer_gasbase` gas at a price of `offerDetail.gasprice`.
   * We do not consider the tx.gasprice.
   * `offerDetail.gasbase` and `offerDetail.gasprice` are the values of Mangrove parameters `config.offer_gasbase` and `config.gasprice` when the offer was created. Without caching those values, the provision set aside could end up insufficient to reimburse the maker (or to retribute the taker).
   */
  function applyPenalty(MgvLib.SingleOrder memory sor, uint gasused) internal returns (uint) {
    unchecked {
      uint gasreq = sor.offerDetail.gasreq();

      uint provision = 1e6 * sor.offerDetail.gasprice() * (gasreq + sor.offerDetail.offer_gasbase());

      /* We set `gasused = min(gasused,gasreq)` since `gasreq < gasused` is possible e.g. with `gasreq = 0` (all calls consume nonzero gas). */
      if (gasused > gasreq) {
        gasused = gasreq;
      }

      /* As an invariant, `applyPenalty` is only called when `mgvData` is in `["mgv/makerRevert","mgv/makerTransferFail","mgv/makerReceiveFail"]`. */
      uint penalty = 1e6 * sor.global.gasprice() * (gasused + sor.local.offer_gasbase());

      if (penalty > provision) {
        penalty = provision;
      }

      /* Here we write to storage the new maker balance. This occurs _after_ possible reentrant calls. How do we know we're not crediting twice the same amounts? Because the `offer`'s provision was set to 0 in storage (through `dirtyDeleteOffer`) before the reentrant calls. In this function, we are working with cached copies of the offer as it was before it was consumed. */
      creditWei(sor.offerDetail.maker(), provision - penalty);

      return penalty;
    }
  }

  function sendPenalty(uint amount) internal {
    unchecked {
      if (amount > 0) {
        (bool noRevert,) = msg.sender.call{value: amount}("");
        require(noRevert, "mgv/sendPenaltyReverted");
      }
    }
  }

  /* Post-trade, `payTakerMinusFees` sends what's due to the taker and keeps the rest (the fees). Routing through the Mangrove like that also deals with blacklisting issues (separates the maker-blacklisted and the taker-blacklisted cases). */
  function payTakerMinusFees(MultiOrder memory mor, MgvLib.SingleOrder memory sor) internal {
    unchecked {
      uint concreteFee = (mor.totalGot * sor.local.fee()) / 10_000;
      if (concreteFee > 0) {
        mor.totalGot -= concreteFee;
        mor.feePaid = concreteFee;
      }
      if (mor.totalGot > 0) {
        /* It should be statically provable that this transfer cannot return false under well-behaved ERC20s and a non-blacklisted, non-0 target, if governance does not call withdrawERC20 during order execution, unless the caller set a gas limit which precisely makes `transferToken` go OOG but retains enough gas to revert here. */
        require(transferToken(sor.olKey.outbound_tkn, mor.taker, mor.totalGot), "mgv/MgvFailToPayTaker");
      }
    }
  }

  /* # Misc. functions */

  /* Regular solidity reverts prepend the string argument with a [function signature](https://docs.soliditylang.org/en/v0.7.6/control-structures.html#revert). Since we wish to transfer data through a revert, the `innerRevert` function does a low-level revert with only the required data. `innerCode` decodes this data. */
  function innerDecode(bytes memory data) internal pure returns (bytes32 mgvData, uint gasused, bytes32 makerData) {
    unchecked {
      /* The `data` pointer is of the form `[mgvData,gasused,makerData]` where each array element is contiguous and has size 256 bits. */
      assembly ("memory-safe") {
        mgvData := mload(add(data, 32))
        gasused := mload(add(data, 64))
        makerData := mload(add(data, 96))
      }
    }
  }

  /* <a id="MgvOfferTaking/innerRevert"></a>`innerRevert` reverts a raw triple of values to be interpreted by `innerDecode`.    */
  function innerRevert(bytes32[3] memory data) internal pure {
    unchecked {
      assembly ("memory-safe") {
        revert(data, 96)
      }
    }
  }
}
