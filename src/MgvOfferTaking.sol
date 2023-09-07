// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {
  HasMgvEvents,
  IMaker,
  IMgvMonitor,
  MgvLib,
  MgvStructs,
  Leaf,
  Field,
  Tick,
  LeafLib,
  FieldLib,
  LogPriceLib,
  OLKey
} from "./MgvLib.sol";
import {MgvHasOffers} from "./MgvHasOffers.sol";
import {TickLib} from "./../lib/TickLib.sol";
import "mgv_lib/LogPriceConversionLib.sol";

abstract contract MgvOfferTaking is MgvHasOffers {
  /* # MultiOrder struct */
  /* The `MultiOrder` struct is used by market orders and snipes. Some of its fields are only used by market orders (`initialWants, initialGives`). We need a common data structure for both since low-level calls are shared between market orders and snipes. The struct is helpful in decreasing stack use. */
  struct MultiOrder {
    uint totalGot; // used globally by market order, per-offer by snipes
    uint totalGave; // used globally by market order, per-offer by snipes
    uint totalPenalty; // used globally
    address taker; // used globally
    bool fillWants; // used globally
    uint fillVolume; // used globally
    uint feePaid; // used globally
    Leaf leaf;
    int maxLogPrice; // maxLogPrice is the log of the max price that can be reached by the market order as a limit price.
    uint maxGasreqForFailingOffers;
    uint gasreqForFailingOffers;
    uint maxRecursionDepth;
  }

  /* # Market Orders */

  /* ## Market Order */
  //+clear+

  /* A market order specifies a (`outbound_tkn`,`inbound_tkn`,`tickScale`) offer list, a desired total amount of `outbound_tkn` (`takerWants`), and an available total amount of `inbound_tkn` (`takerGives`). It returns four `uint`s: the total amount of `outbound_tkn` received, the total amount of `inbound_tkn` spent, the penalty received by msg.sender (in wei), and the fee paid by the taker (in wei).

     The `takerGives/takerWants` ratio induces a maximum average price that the taker is ready to pay across all offers that will be executed during the market order. It is thus possible to execute an offer with a price worse than the initial (`takerGives`/`takerWants`) ratio given as argument to `marketOrder` if some cheaper offers were executed earlier in the market order.

  The market order stops when the price has become too high, or when the end of the book has been reached, or:
  * If `fillWants` is true, the market order stops when `takerWants` units of `outbound_tkn` have been obtained. With `fillWants` set to true, to buy a specific volume of `outbound_tkn` at any price, set `takerWants` to the amount desired and `takerGives` to $2^{104}-1$.
  * If `fillWants` is false, the taker is filling `gives` instead: the market order stops when `takerGives` units of `inbound_tkn` have been sold. With `fillWants` set to false, to sell a specific volume of `inbound_tkn` at any price, set `takerGives` to the amount desired and `takerWants` to $0$. */
  function marketOrderByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants)
    public
    returns (uint takerGot, uint takerGave, uint bounty, uint fee)
  {
    uint fillVolume = fillWants ? takerWants : takerGives;
    int maxLogPrice = LogPriceConversionLib.logPriceFromVolumes(takerGives, takerWants);
    return marketOrderByLogPrice(olKey, maxLogPrice, fillVolume, fillWants);
  }

  function marketOrderByLogPrice(OLKey memory olKey, int maxLogPrice, uint fillVolume, bool fillWants)
    public
    returns (uint takerGot, uint takerGave, uint bounty, uint fee)
  {
    unchecked {
      return marketOrderByLogPrice(olKey, maxLogPrice, fillVolume, fillWants, 0);
    }
  }

  function marketOrderByLogPrice(
    OLKey memory olKey,
    int maxLogPrice,
    uint fillVolume,
    bool fillWants,
    uint maxGasreqForFailingOffers
  ) public returns (uint takerGot, uint takerGave, uint bounty, uint fee) {
    unchecked {
      return generalMarketOrder(olKey, maxLogPrice, fillVolume, fillWants, msg.sender, maxGasreqForFailingOffers);
    }
  }

  // get offer after current offer, will also remove the current offer and return the corresponding updated `local`
  function getNextBest(
    OfferList storage offerList,
    MultiOrder memory mor,
    MgvStructs.OfferPacked offer,
    MgvStructs.LocalPacked local,
    uint tickScale
  ) internal returns (uint offerId, MgvStructs.LocalPacked) {
    Tick offerTick = offer.tick(tickScale);
    uint nextId = offer.next();

    if (nextId == 0) {
      Leaf leaf = mor.leaf;
      leaf = leaf.setTickFirst(offerTick, 0).setTickLast(offerTick, 0);
      if (leaf.isEmpty()) {
        offerList.leafs[offerTick.leafIndex()] = leaf;
        int index = offerTick.level0Index();
        Field field = local.level0().flipBitAtLevel0(offerTick);
        if (field.isEmpty()) {
          offerList.level0[index] = field;
          index = offerTick.level1Index();
          field = local.level1().flipBitAtLevel1(offerTick);
          if (field.isEmpty()) {
            offerList.level1[index] = field;
            field = local.level2().flipBitAtLevel2(offerTick);
            local = local.level2(field);
            if (field.isEmpty()) {
              local = local.level1(field);
              local = local.level0(field);
              mor.leaf = LeafLib.EMPTY;
              return (0, local);
            }
            index = field.firstLevel1Index();
            field = offerList.level1[index];
          }
          local = local.level1(field);
          index = field.firstLevel0Index(index);
          field = offerList.level0[index];
        }
        local = local.level0(field);
        leaf = offerList.leafs[field.firstLeafIndex(index)];
      }
      mor.leaf = leaf;
      nextId = leaf.getNextOfferId();
    }
    return (nextId, local);
  }
  /* # General Market Order */
  //+clear+
  /* General market orders set up the market order with a given `taker` (`msg.sender` in the most common case). Returns `(totalGot, totalGave, penaltyReceived, feePaid)`.
  Note that the `taker` can be anyone. This is safe when `taker == msg.sender`, but `generalMarketOrder` must not be called with `taker != msg.sender` unless a security check is done after (see [`MgvOfferTakingWithPermit`](#mgvoffertakingwithpermit.sol)`. */

  function generalMarketOrder(
    OLKey memory olKey,
    int maxLogPrice,
    uint fillVolume,
    bool fillWants,
    address taker,
    uint maxGasreqForFailingOffers
  ) internal returns (uint takerGot, uint takerGave, uint bounty, uint fee) {
    unchecked {
      /* Checking that `takerWants` and `takerGives` fit in 104 bits prevents overflow during the main market order loop. */
      require(fillVolume <= MAX_SAFE_VOLUME, "mgv/mOrder/fillVolume/tooBig");
      require(LogPriceLib.inRange(maxLogPrice), "mgv/mOrder/logPrice/outOfRange");

      /* `MultiOrder` (defined above) maintains information related to the entire market order. During the order, initial `wants`/`gives` values minus the accumulated amounts traded so far give the amounts that remain to be traded. */
      MultiOrder memory mor;
      mor.maxLogPrice = maxLogPrice;
      mor.taker = taker;
      mor.fillWants = fillWants;

      /* `SingleOrder` is defined in `MgvLib.sol` and holds information for ordering the execution of one offer. */
      MgvLib.SingleOrder memory sor;
      sor.olKey = olKey;
      OfferList storage offerList;
      (sor.global, sor.local, offerList) = _config(olKey);
      mor.maxRecursionDepth = sor.global.maxRecursionDepth();
      /* We have an upper limit on total gasreq for failing offers to avoid failing offers delivering nothing and exhausting gaslimit for the transaction. */
      mor.maxGasreqForFailingOffers =
        maxGasreqForFailingOffers > 0 ? maxGasreqForFailingOffers : sor.global.maxGasreqForFailingOffers();

      /* Throughout the execution of the market order, the `sor`'s offer id and other parameters will change. We start with the current best offer id (0 if the book is empty). */

      mor.leaf = offerList.leafs[sor.local.bestTick().leafIndex()];
      sor.offerId = mor.leaf.getNextOfferId();
      sor.offer = offerList.offerData[sor.offerId].offer;
      /* fillVolume evolves but is initially however much remains in the market order. */
      mor.fillVolume = fillVolume;

      /* For the market order to even start, the market needs to be both active, and not currently protected from reentrancy. */
      activeMarketOnly(sor.global, sor.local);
      unlockedMarketOnly(sor.local);

      /* ### Initialization */
      /* The market order will operate as follows : it will go through offers from best to worse, starting from `offerId`, and: */
      /* * will maintain remaining `takerWants` and `takerGives` values. The initial `takerGives/takerWants` ratio is the average price the taker will accept. Better prices may be found early in the book, and worse ones later.
       * will not set `prev`/`next` pointers to their correct locations at each offer taken (this is an optimization enabled by forbidding reentrancy).
       * after consuming a segment of offers, will update the current `best` offer to be the best remaining offer on the book. */

      /* We start be enabling the reentrancy lock for this (`outbound_tkn`,`inbound_tkn`) offerList. */
      sor.local = sor.local.lock(true);
      offerList.local = sor.local;

      emit OrderStart();

      /* Call recursive `internalMarketOrder` function.*/
      internalMarketOrder(offerList, mor, sor);

      /* Over the course of the market order, a penalty reserved for `msg.sender` has accumulated in `mor.totalPenalty`. No actual transfers have occurred yet -- all the ethers given by the makers as provision are owned by Mangrove. `sendPenalty` finally gives the accumulated penalty to `msg.sender`. */
      sendPenalty(mor.totalPenalty);

      emit OrderComplete(olKey.hash(), taker, mor.totalGot, mor.totalGave, mor.totalPenalty, mor.feePaid);

      //+clear+
      return (mor.totalGot, mor.totalGave, mor.totalPenalty, mor.feePaid);
    }
  }

  /* ## Internal market order */
  //+clear+
  /* `internalMarketOrder` works recursively. Going downward, each successive offer is executed until the market order stops (due to: volume exhausted, bad price, or empty book). Then the [reentrancy lock is lifted](#internalMarketOrder/liftReentrancy). Going upward, each offer's `maker` contract is called again with its remaining gas and given the chance to update its offers on the book. */
  function internalMarketOrder(OfferList storage offerList, MultiOrder memory mor, MgvLib.SingleOrder memory sor)
    internal
  {
    unchecked {
      if (
        mor.fillVolume > 0 && sor.offer.logPrice() <= mor.maxLogPrice && sor.offerId > 0 && mor.maxRecursionDepth > 0
          && mor.gasreqForFailingOffers <= mor.maxGasreqForFailingOffers
      ) {
        mor.maxRecursionDepth--;

        /* #### Case 1 : End of order */
        /* We execute the offer currently stored in `sor` if its price is better than or equal to the price the taker is ready to accept (`maxTick`). */

        uint gasused; // gas used by `makerExecute`
        bytes32 makerData; // data returned by maker

        /* <a id="MgvOfferTaking/statusCodes"></a> `mgvData` is an internal Mangrove status code. It may appear in an [`OrderResult`](#MgvLib/OrderResult). Its possible values are:
      * `"mgv/tradeSuccess"`: offer execution succeeded. Will appear in `OrderResult`.
      * `"mgv/notEnoughGasForMakerTrade"`: cannot give maker close enough to `gasreq`. Triggers a revert of the entire order.
      * `"mgv/makerRevert"`: execution of `makerExecute` reverted. Will appear in `OrderResult`.
      * `"mgv/makerTransferFail"`: maker could not send outbound_tkn tokens. Will appear in `OrderResult`.
      * `"mgv/makerReceiveFail"`: maker could not receive inbound_tkn tokens. Will appear in `OrderResult`.
      * `"mgv/takerTransferFail"`: taker could not send inbound_tkn tokens. Triggers a revert of the entire order.

      `mgvData` should not be exploitable by the maker! */
        bytes32 mgvData;

        /* Load additional information about the offer. */
        sor.offerDetail = offerList.offerData[sor.offerId].detail;

        /* `execute` will adjust `sor.wants`,`sor.gives`, and may attempt to execute the offer if its price is low enough. It is crucial that an error due to `taker` triggers a revert. That way, if [`mgvData`](#MgvOfferTaking/statusCodes) is not `"mgv/tradeSuccess"` then the maker is at fault. */
        /* Post-execution, `sor.wants`/`sor.gives` reflect how much was sent/taken by the offer. We will need it after the recursive call, so we save it in local variables. Same goes for `offerId`, `sor.offer` and `sor.offerDetail`. */

        (gasused, makerData, mgvData) = execute(offerList, mor, sor);

        /* Keep cached copy of current `sor` values to restore them later to send to posthook. */
        uint takerWants = sor.wants;
        uint takerGives = sor.gives;
        uint offerId = sor.offerId;
        MgvStructs.OfferPacked offer = sor.offer;
        MgvStructs.OfferDetailPacked offerDetail = sor.offerDetail;

        /* If execution was successful, we update fillVolume downwards. Assume `mor.fillWants`: it is known statically that `mor.fillVolume - sor.wants` does not underflow. See the [`execute` function](#MgvOfferTaking/computeVolume) for details. */
        if (mgvData == "mgv/tradeSuccess") {
          mor.fillVolume -= mor.fillWants ? sor.wants : sor.gives;
        }

        /* We move `sor` to the next offer. Note that the current state is inconsistent, since we have not yet updated `sor.offerDetails`. */
        /* It is known statically that `mor.initialGives - mor.totalGave` does not underflow since
          1. `mor.totalGave` was increased by `sor.gives` during `execute`,
          2. `sor.gives` was at most `mor.initialGives - mor.totalGave` from earlier step,
          3. `sor.gives` may have been clamped _down_ during `execute` (to "`offer.wants`" if the offer is entirely consumed, or to `makerWouldWant`, cf. code of `execute`).
        */
        (sor.offerId, sor.local) = getNextBest(offerList, mor, sor.offer, sor.local, sor.olKey.tickScale);

        sor.offer = offerList.offerData[sor.offerId].offer;

        internalMarketOrder(offerList, mor, sor);

        /* Restore `sor` values from before recursive call */
        sor.wants = takerWants;
        sor.gives = takerGives;
        sor.offerId = offerId;
        sor.offer = offer;
        sor.offerDetail = offerDetail;

        /* After an offer execution, we may run callbacks and increase the total penalty. As that part is common to market orders and cleaning, it lives in its own `postExecute` function. */
        postExecute(mor, sor, gasused, makerData, mgvData);
        /* #### Case 2 : End of market order */
        /* The taker has gotten its requested volume, no more offers match, or we have reached the end of the book, we conclude the market order. */
        /* During the market order, all executed offers have been removed from the book. We end by stitching together the `best` offer pointer and the new best offer. */
      } else {
        // mark current offer as having no prev if necessary
        // update leaf if necessary
        MgvStructs.OfferPacked offer = sor.offer;
        Tick tick = offer.tick(sor.olKey.tickScale);
        if (offer.prev() != 0) {
          offerList.offerData[sor.offerId].offer = sor.offer.prev(0);
          mor.leaf = mor.leaf.setTickFirst(tick, sor.offerId);
        }

        // maybe some updates below are useless? if we don't update these we must take it into account elsewhere
        // no need to test whether level2 has been reached since by default its stored in local

        sor.local = sor.local.tickPosInLeaf(mor.leaf.firstOfferPosition());
        // no need to test whether mor.level2 != offerList.level2 since update is ~free
        // ! local.level0[sor.local.bestTick().level0Index()] is now wrong
        // sor.local = sor.local.level0(mor.level0);

        int index = tick.leafIndex();
        // leaf cached in memory is flushed to storage everytime it gets emptied, but at the end of a market order we need to store it correctly
        // second conjunct is for when you did not ever read leaf
        if (!offerList.leafs[index].eq(mor.leaf)) {
          offerList.leafs[index] = mor.leaf;
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

        /* In an inverted Mangrove, amounts have been lent by each offer's maker to the taker. We now call the taker. This is a noop in a normal Mangrove. */
        executeEnd(mor, sor);
      }
    }
  }

  /* # Cleaning */
  // FIXME: Document cleaning
  /* Cleans multiple offers, i.e. executes them and remove them from the book if they fail, transferring the failure penaly as bounty to the caller. If an offer succeeds, the execution of that offer is reverted, it stays in the book, and no bounty is paid; The `clean` function itself will not revert.
  
  It takes a `CleanTarget[]` as penultimate argument, with each `CleanTarget` identifying an offer to clean and the execution parameters that will make it fail. The return values are the number of successfully cleaned offers and the total bounty received.
  Note that we do not distinguish further between mismatched arguments/offer fields on the one hand, and an execution failure on the other. Still, a failed offer has to pay a penalty, and ultimately transaction logs explicitly mention execution failures (see `MgvLib.sol`).

  Any `taker` can be impersonated when cleaning because the function reverts if the offer succeeds, cancelling any token transfers. And after a `clean` where the offer has failed, all token transfers have been reverted -- but the sender will still have received the bounty of the failing offers. */
  function cleanByImpersonation(OLKey memory olKey, MgvLib.CleanTarget[] calldata targets, address taker)
    external
    returns (uint successes, uint bounty)
  {
    unchecked {
      emit OrderStart();

      for (uint i = 0; i < targets.length; ++i) {
        bytes memory encodedCall;
        {
          MgvLib.CleanTarget calldata target = targets[i];
          encodedCall = abi.encodeCall(
            this.internalCleanByImpersonation,
            (olKey, target.offerId, target.logPrice, target.gasreq, target.takerWants, taker)
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

      emit OrderComplete(olKey.hash(), msg.sender, 0, 0, bounty, 0);
    }
  }

  function internalCleanByImpersonation(
    OLKey memory olKey,
    uint offerId,
    int logPrice,
    uint gasreq,
    uint takerWants,
    address taker
  ) external returns (uint bounty) {
    unchecked {
      /* `internalClean` must be used with a call (hence the `external` modifier) so its effect can be reverted. But a call from the outside would mean the bounty would get stuck in Mangrove. */
      require(msg.sender == address(this), "mgv/clean/protected");

      MultiOrder memory mor;
      {
        require(LogPriceLib.inRange(logPrice), "mgv/clean/logPrice/outOfRange");
        mor.maxLogPrice = logPrice;
      }
      {
        require(uint96(takerWants) == takerWants, "mgv/clean/takerWants/96bits");
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

      /* For the snipes to even start, the market needs to be both active and not currently protected from reentrancy. */
      activeMarketOnly(sor.global, sor.local);
      unlockedMarketOnly(sor.local);

      /* FIXME: edit comment: If we removed the `isLive` conditional, a single expired or nonexistent offer in `targets` would revert the entire transaction (by the division by `offer.gives` below since `offer.gives` would be 0). We also check that `gasreq` is not worse than specified. A taker who does not care about `gasreq` can specify any amount larger than $2^{24}-1$. A mismatched price will be detected by `execute`. */
      require(sor.offer.isLive(), "mgv/clean/offerNotLive");
      require(sor.offerDetail.gasreq() <= gasreq, "mgv/clean/gasreqTooLow");
      require(sor.offer.logPrice() == logPrice, "mgv/clean/tickMismatch");

      /* We start be enabling the reentrancy lock for this (`outbound_tkn`,`inbound_tkn`) pair. */
      sor.local = sor.local.lock(true);
      offerList.local = sor.local;

      {
        /* `execute` will adjust `sor.wants`,`sor.gives`, and will attempt to execute the offer. It is crucial that an error due to `taker` triggers a revert. That way [`mgvData`](#MgvOfferTaking/statusCodes) not equal to `"mgv/tradeSuccess"` means the failure is the maker's fault. */
        /* Post-execution, `sor.wants`/`sor.gives` reflect how much was sent/taken by the offer. */
        (uint gasused, bytes32 makerData, bytes32 mgvData) = execute(offerList, mor, sor);

        require(mgvData != "mgv/tradeSuccess", "mgv/clean/offerDidNotFail");

        /* In the market order, we were able to avoid stitching back offers after every `execute` since we knew a continuous segment starting at best would be consumed. Here, we cannot do this optimisation since the offer may be anywhere in the book. So we stitch together offers immediately after `execute`. */
        sor.local = dislodgeOffer(offerList, sor.olKey.tickScale, sor.offer, sor.local, true);

        /* <a id="internalSnipes/liftReentrancy"></a> Now that the current snipe is over, we can lift the lock on the book. In the same operation we
        * lift the reentrancy lock, and
        * update the storage

        so we are free from out of order storage writes.
        */
        sor.local = sor.local.lock(false);
        offerList.local = sor.local;

        /* No fees are paid since offer execution failed. */

        /* In an inverted Mangrove, amounts have been lent by each offer's maker to the taker. We now call the taker. This is a noop in a normal Mangrove. */
        executeEnd(mor, sor);

        /* After an offer execution, we may run callbacks and increase the total penalty. As that part is common to market orders and snipes, it lives in its own `postExecute` function. */
        postExecute(mor, sor, gasused, makerData, mgvData);
      }

      bounty = mor.totalPenalty;
    }
  }

  /* # General execution */
  /* During a market order or a clean, offers get executed. The following code takes care of executing a single offer with parameters given by a `SingleOrder` within a larger context given by a `MultiOrder`. */

  /* ## Execute */
  /* Execution of the offer will be attempted with volume limited by the offer's advertised volume.
     NB: The caller must ensure that the price of the offer is low enough; This is not checked here.

     Summary of the meaning of the return values:
    * `gasused` is the gas consumed by the execution
    * `makerData` is the data returned after executing the offer
    * `mgvData` is an [internal Mangrove status code](#MgvOfferTaking/statusCodes).
  */
  function execute(OfferList storage offerList, MultiOrder memory mor, MgvLib.SingleOrder memory sor)
    internal
    returns (uint gasused, bytes32 makerData, bytes32 mgvData)
  {
    unchecked {
      {
        uint fillVolume = mor.fillVolume;
        uint offerGives = sor.offer.gives();
        uint offerWants = sor.offer.wants();
        /* <a id="MgvOfferTaking/computeVolume"></a> Volume requested depends on total gives (or wants) by taker. Let `volume = sor.wants` if `mor.fillWants` is true, and `volume = sor.gives` otherwise; note that `volume <= fillVolume` in all cases. Example with `fillWants=true`: if `offerGives < fillVolume` the first branch of the outer `if` sets `volume = offerGives` and we are done; otherwise the 1st branch of the inner if is taken and sets `volume = fillVolume` and we are done. */
        if ((mor.fillWants && offerGives < fillVolume) || (!mor.fillWants && offerWants < fillVolume)) {
          sor.wants = offerGives;
          sor.gives = offerWants;
        } else {
          if (mor.fillWants) {
            sor.gives = LogPriceLib.inboundFromOutboundUp(sor.offer.logPrice(), fillVolume);
            sor.wants = fillVolume;
          } else {
            // offerWants = 0 is forbidden at offer writing
            sor.wants = LogPriceLib.outboundFromInbound(sor.offer.logPrice(), fillVolume);
            sor.gives = fillVolume;
          }
        }
      }
      /* The flashloan is executed by call to `flashloan`. If the call reverts, it means the maker failed to send back `sor.wants` `outbound_tkn` to the taker. Notes :
       * `msg.sender` is Mangrove itself in those calls -- all operations related to the actual caller should be done outside of this call.
       * any spurious exception due to an error in Mangrove code will be falsely blamed on the Maker, and its provision for the offer will be unfairly taken away.
       */
      bool success;
      bytes memory retdata;
      {
        // Clear fields that maker must not see
        /* NB: It should be more efficient to do this in `makerExecute` instead as we would not have to restore the fields afterwards.
         * However, for unknown reasons that solution consumes significantly more gas, so we do it here instead. */
        MgvStructs.OfferPacked offer = sor.offer;
        sor.offer = offer.clearFieldsForMaker();
        MgvStructs.LocalPacked local = sor.local;
        sor.local = local.clearFieldsForMaker();

        (success, retdata) = address(this).call(abi.encodeCall(this.flashloan, (sor, mor.taker)));

        // Restore cleared fields
        sor.offer = offer;
        sor.local = local;
      }

      /* `success` is true: trade is complete */
      if (success) {
        /* In case of success, `retdata` encodes the gas used by the offer, and an arbitrary 256 bits word sent by the maker.  */
        (gasused, makerData) = abi.decode(retdata, (uint, bytes32));
        /* `mgvData` indicates trade success */
        mgvData = bytes32("mgv/tradeSuccess");

        /* If configured to do so, Mangrove notifies an external contract that a successful trade has taken place. */
        if (sor.global.notify()) {
          IMgvMonitor(sor.global.monitor()).notifySuccess(sor, mor.taker);
        }

        /* We update the totals in the multiorder based on the adjusted `sor.wants`/`sor.gives`. */
        /* overflow: sor.{wants,gives} are on 96bits, sor.total{Got,Gave} are on 256 bits. */
        mor.totalGot += sor.wants;
        mor.totalGave += sor.gives;
      } else {
        /* In case of failure, `retdata` encodes a short [status code](#MgvOfferTaking/statusCodes), the gas used by the offer, and an arbitrary 256 bits word sent by the maker.  */
        (mgvData, gasused, makerData) = innerDecode(retdata);
        /* Note that in the `if`s, the literals are bytes32 (stack values), while as revert arguments, they are strings (memory pointers). */
        if (mgvData == "mgv/makerRevert" || mgvData == "mgv/makerTransferFail" || mgvData == "mgv/makerReceiveFail") {
          /* Update (an upper bound) on gasreq required for failing offers */
          mor.gasreqForFailingOffers += sor.offerDetail.gasreq();
          /* If configured to do so, Mangrove notifies an external contract that a failed trade has taken place. */
          if (sor.global.notify()) {
            IMgvMonitor(sor.global.monitor()).notifyFail(sor, mor.taker);
          }
          /* It is crucial that any error code which indicates an error caused by the taker triggers a revert, because functions that call `execute` consider that when `mgvData` is not `"mgv/tradeSuccess"`, then the maker should be blamed. */
        } else if (mgvData == "mgv/notEnoughGasForMakerTrade") {
          revert("mgv/notEnoughGasForMakerTrade");
        } else if (mgvData == "mgv/takerTransferFail") {
          revert("mgv/takerTransferFail");
        } else {
          /* This code must be unreachable except if the call to flashloan went OOG and there is enough gas to revert here. **Danger**: if a well-crafted offer/maker offerList can force a revert of `flashloan`, Mangrove will be stuck. */
          revert("mgv/swapError");
        }
      }

      /* Delete the offer. The last argument indicates whether the offer should be stripped of its provision (yes if execution failed, no otherwise). We cannot partially strip an offer provision (for instance, remove only the penalty from a failing offer and leave the rest) since the provision associated with an offer is always deduced from the (gasprice,gasbase,gasreq) parameters and not stored independently. We delete offers whether the amount remaining on offer is > density or not for the sake of uniformity (code is much simpler). We also expect prices to move often enough that the maker will want to update their price anyway. To simulate leaving the remaining volume in the offer, the maker can program their `makerPosthook` to `updateOffer` and put the remaining volume back in. */
      dirtyDeleteOffer(offerList.offerData[sor.offerId], sor.offer, sor.offerDetail, mgvData != "mgv/tradeSuccess");
    }
  }

  /* ## flashloan (abstract) */
  /* Externally called by `execute`, flashloan lends money (from the taker to the maker, or from the maker to the taker, depending on the implementation) then calls `makerExecute` to run the maker liquidity fetching code. If `makerExecute` is unsuccessful, `flashloan` reverts (but the larger orderbook traversal will continue). 

  All `flashloan` implementations must `require(msg.sender) == address(this))`. */
  function flashloan(MgvLib.SingleOrder calldata sor, address taker)
    external
    virtual
    returns (uint gasused, bytes32 makerData);

  /* ## Maker Execute */
  /* Called by `flashloan`, `makerExecute` runs the maker code and checks that it can safely send the desired assets to the taker. */

  function makerExecute(MgvLib.SingleOrder calldata sor) internal returns (uint gasused, bytes32 makerData) {
    unchecked {
      bytes memory cd = abi.encodeCall(IMaker.makerExecute, (sor));

      uint gasreq = sor.offerDetail.gasreq();
      address maker = sor.offerDetail.maker();
      uint oldGas = gasleft();
      /* We let the maker pay for the overhead of checking remaining gas and making the call, as well as handling the return data (constant gas since only the first 32 bytes of return data are read). So the `require` below is just an approximation: if the overhead of (`require` + cost of `CALL`) is $h$, the maker will receive at worst $\textrm{gasreq} - \frac{63h}{64}$ gas. */
      /* Note : as a possible future feature, we could stop an order when there's not enough gas left to continue processing offers. This could be done safely by checking, as soon as we start processing an offer, whether `63/64(gasleft-offer_gasbase) > gasreq`. If no, we could stop and know by induction that there is enough gas left to apply fees, stitch offers, etc for the offers already executed. */
      if (!(oldGas - oldGas / 64 >= gasreq)) {
        innerRevert([bytes32("mgv/notEnoughGasForMakerTrade"), "", ""]);
      }

      bool callSuccess;
      (callSuccess, makerData) = controlledCall(maker, gasreq, cd);

      gasused = oldGas - gasleft();

      if (!callSuccess) {
        innerRevert([bytes32("mgv/makerRevert"), bytes32(gasused), makerData]);
      }

      bool transferSuccess = transferTokenFrom(sor.olKey.outbound, maker, address(this), sor.wants);

      if (!transferSuccess) {
        innerRevert([bytes32("mgv/makerTransferFail"), bytes32(gasused), makerData]);
      }
    }
  }

  /* ## executeEnd (abstract) */
  /* Called by `internalSnipes` and `internalMarketOrder`, `executeEnd` may run implementation-specific code after all makers have been called once. In [`InvertedMangrove`](#InvertedMangrove), the function calls the taker once so they can act on their flashloan. In [`Mangrove`], it does nothing. */
  function executeEnd(MultiOrder memory mor, MgvLib.SingleOrder memory sor) internal virtual;

  /* ## Post execute */
  /* At this point, we know an offer execution was attempted. After executing an offer (whether in a market order or in snipes), we
     1. Call the maker's posthook and sum the total gas used.
     2. If offer failed: sum total penalty due to msg.sender and give remainder to maker.
   */
  function postExecute(
    MultiOrder memory mor,
    MgvLib.SingleOrder memory sor,
    uint gasused,
    bytes32 makerData,
    bytes32 mgvData
  ) internal {
    unchecked {
      if (mgvData == "mgv/tradeSuccess") {
        beforePosthook(sor);
      }

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
            sor.olKey.hash(), sor.offerId, sor.wants, sor.gives, penalty, mgvData, posthookData
          );
        } else {
          emit OfferFail(sor.olKey.hash(), sor.offerId, sor.wants, sor.gives, penalty, mgvData);
        }
      } else {
        if (!callSuccess) {
          emit OfferSuccessWithPosthookData(sor.olKey.hash(), sor.offerId, sor.wants, sor.gives, posthookData);
        } else {
          emit OfferSuccess(sor.olKey.hash(), sor.offerId, sor.wants, sor.gives);
        }
      }
    }
  }

  /* ## beforePosthook (abstract) */
  /* Called by `makerPosthook`, this function can run implementation-specific code before calling the maker has been called a second time. In [`InvertedMangrove`](#InvertedMangrove), all makers are called once so the taker gets all of its money in one shot. Then makers are traversed again and the money is sent back to each taker using `beforePosthook`. In [`Mangrove`](#Mangrove), `beforePosthook` does nothing. */

  function beforePosthook(MgvLib.SingleOrder memory sor) internal virtual;

  /* ## Maker Posthook */
  function makerPosthook(MgvLib.SingleOrder memory sor, uint gasLeft, bytes32 makerData, bytes32 mgvData)
    internal
    returns (uint gasused, bool callSuccess, bytes32 posthookData)
  {
    unchecked {
      /* At this point, mgvData can only be `"mgv/tradeSuccess"`, `"mgv/makerRevert"`, `"mgv/makerTransferFail"` or `"mgv/makerReceiveFail"` */
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
  /* Calls an external function with controlled gas expense. A direct call of the form `(,bytes memory retdata) = maker.call{gas}(selector,...args)` enables a griefing attack: the maker uses half its gas to write in its memory, then reverts with that memory segment as argument. After a low-level call, solidity automaticaly copies `returndatasize` bytes of `returndata` into memory. So the total gas consumed to execute a failing offer could exceed `gasreq + offer_gasbase` where `n` is the number of failing offers. In case of success, we read the first 32 bytes of returndata (the signature of `makerExecute` is `bytes32`). Otherwise, for compatibility with most errors that bubble up from contract calls and Solidity's `require`, we read 32 bytes of returndata starting from the 69th (4 bytes of method sig + 32 bytes of offset + 32 bytes of string length). */
  function controlledCall(address callee, uint gasreq, bytes memory cd) internal returns (bool success, bytes32 data) {
    unchecked {
      bytes32[4] memory retdata;

      /* if success, read returned bytes 1..32, otherwise read returned bytes 69..100. */
      assembly {
        success := call(gasreq, callee, 0, add(cd, 32), mload(cd), retdata, 100)
        data := mload(add(mul(iszero(success), 68), retdata))
      }
    }
  }

  /* # Penalties */
  /* Offers are just promises. They can fail. Penalty provisioning discourages from failing too much: we ask makers to provision more ETH than the expected gas cost of executing their offer and penalize them accoridng to wasted gas.

     Under normal circumstances, we should expect to see bots with a profit expectation dry-running offers locally and executing `snipe` on failing offers, collecting the penalty. The result should be a mostly clean book for actual takers (i.e. a book with only successful offers).

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

      uint provision = 10 ** 9 * sor.offerDetail.gasprice() * (gasreq + sor.offerDetail.offer_gasbase());

      /* We set `gasused = min(gasused,gasreq)` since `gasreq < gasused` is possible e.g. with `gasreq = 0` (all calls consume nonzero gas). */
      if (gasused > gasreq) {
        gasused = gasreq;
      }

      /* As an invariant, `applyPenalty` is only called when `mgvData` is not in `["mgv/tradeSuccess"]` */
      uint penalty = 10 ** 9 * sor.global.gasprice() * (gasused + sor.local.offer_gasbase());

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
        /* It should be statically provable that this transfer cannot return false under well-behaved ERC20s and a non-blacklisted, non-0 target, if governance does not call withdrawERC20 during order execution. */
        require(transferToken(sor.olKey.outbound, mor.taker, mor.totalGot), "mgv/MgvFailToPayTaker");
      }
    }
  }

  /* # Misc. functions */

  /* Regular solidity reverts prepend the string argument with a [function signature](https://docs.soliditylang.org/en/v0.7.6/control-structures.html#revert). Since we wish to transfer data through a revert, the `innerRevert` function does a low-level revert with only the required data. `innerCode` decodes this data. */
  function innerDecode(bytes memory data) internal pure returns (bytes32 mgvData, uint gasused, bytes32 makerData) {
    unchecked {
      /* The `data` pointer is of the form `[mgvData,gasused,makerData]` where each array element is contiguous and has size 256 bits. */
      assembly {
        mgvData := mload(add(data, 32))
        gasused := mload(add(data, 64))
        makerData := mload(add(data, 96))
      }
    }
  }

  /* <a id="MgvOfferTaking/innerRevert"></a>`innerRevert` reverts a raw triple of values to be interpreted by `innerDecode`.    */
  function innerRevert(bytes32[3] memory data) internal pure {
    unchecked {
      assembly {
        revert(data, 96)
      }
    }
  }
}
