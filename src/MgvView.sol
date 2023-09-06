// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {
  MgvLib,
  IMgvMonitor,
  MgvStructs,
  IERC20,
  Leaf,
  Field,
  Density,
  DensityLib,
  OLKey,
  LogPriceLib,
  LogPriceConversionLib,
  Tick
} from "./MgvLib.sol";
import "mgv_src/MgvCommon.sol";

struct VolumeData {
  uint totalGot;
  uint totalGave;
  uint totalGasreq;
}

// Contains view functions, to reduce Mangrove contract size
contract MgvView is MgvCommon {
  /* # Configuration Reads */
  /* Reading the configuration for an offer list involves reading the config global to all offerLists and the local one. In addition, a global parameter (`gasprice`) and a local one (`density`) may be read from the oracle. */
  function config(OLKey memory olKey)
    public
    view
    returns (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local)
  {
    unchecked {
      (_global, _local,) = _config(olKey);
      unlockedMarketOnly(_local);
    }
  }

  function balanceOf(address maker) external view returns (uint balance) {
    balance = _balanceOf[maker];
  }

  // FIXME: Make these external again once tree navigation is no longer needed in this contract
  function leafs(OLKey memory olKey, int index) public view returns (Leaf) {
    OfferList storage _offerList = offerLists[olKey.hash()];
    unlockedMarketOnly(_offerList.local);
    return _offerList.leafs[index];
  }

  function level0(OLKey memory olKey, int index) public view returns (Field) {
    OfferList storage _offerList = offerLists[olKey.hash()];
    MgvStructs.LocalPacked _local = _offerList.local;
    unlockedMarketOnly(_local);

    if (_local.bestTick().level0Index() == index) {
      return _local.level0();
    } else {
      return _offerList.level0[index];
    }
  }

  function level1(OLKey memory olKey, int index) public view returns (Field) {
    OfferList storage _offerList = offerLists[olKey.hash()];
    MgvStructs.LocalPacked _local = _offerList.local;
    unlockedMarketOnly(_local);

    if (_local.bestTick().level1Index() == index) {
      return _local.level1();
    } else {
      return _offerList.level1[index];
    }
  }

  function level2(OLKey memory olKey) public view returns (Field) {
    OfferList storage _offerList = offerLists[olKey.hash()];
    MgvStructs.LocalPacked _local = _offerList.local;
    unlockedMarketOnly(_local);
    return _local.level2();
  }

  /* Returns the configuration in an ABI-compatible struct. Should not be called internally, would be a huge memory copying waste. Use `config` instead. */
  function configInfo(OLKey memory olKey)
    external
    view
    returns (MgvStructs.GlobalUnpacked memory _global, MgvStructs.LocalUnpacked memory _local)
  {
    unchecked {
      (MgvStructs.GlobalPacked __global, MgvStructs.LocalPacked __local) = config(olKey);
      unlockedMarketOnly(__local);
      _global = __global.to_struct();
      _local = __local.to_struct();
    }
  }

  /* Sugar for getting only global/local config */
  function global() public view returns (MgvStructs.GlobalPacked) {
    (MgvStructs.GlobalPacked _global,) = config(OLKey(address(0), address(0), 0));
    return _global;
  }

  function local(OLKey memory olKey) public view returns (MgvStructs.LocalPacked) {
    (, MgvStructs.LocalPacked _local) = config(olKey);
    return _local;
  }

  function globalUnpacked() public view returns (MgvStructs.GlobalUnpacked memory) {
    return global().to_struct();
  }

  function localUnpacked(OLKey memory olKey) public view returns (MgvStructs.LocalUnpacked memory) {
    return local(olKey).to_struct();
  }

  /* Convenience function to check whether given an offer list is locked */
  function locked(OLKey memory olKey) external view returns (bool) {
    return offerLists[olKey.hash()].local.lock();
  }

  /* # Read functions */
  /* Convenience function to get best offer of the given offerList */
  function best(OLKey memory olKey) public view returns (uint offerId) {
    unchecked {
      OfferList storage _offerList = offerLists[olKey.hash()];
      MgvStructs.LocalPacked _local = _offerList.local;
      unlockedMarketOnly(_local);
      return _offerList.leafs[_local.bestTick().leafIndex()].getNextOfferId();
    }
  }

  /* Convenience function for checking whether a offer list is empty. There is no offer with id 0, so if the id of the offer list's best offer is 0, it means the offer list is empty. */
  function isEmptyOB(OLKey memory olKey) external view returns (bool) {
    return best(olKey) == 0;
  }

  /* Returns the minimum outbound_tkn volume to give on the outbound_tkn/inbound_tkn offer list for an offer that requires gasreq gas. */
  function minVolume(OLKey memory olKey, uint gasreq) public view returns (uint) {
    MgvStructs.LocalPacked _local = local(olKey);
    return _local.density().multiplyUp(gasreq + _local.offer_gasbase());
  }

  /* Returns the provision necessary to post an offer on the outbound_tkn/inbound_tkn offer list. You can set gasprice=0 or use the overload to use Mangrove's internal gasprice estimate. */
  function getProvision(OLKey memory olKey, uint ofr_gasreq, uint ofr_gasprice) public view returns (uint) {
    unchecked {
      (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local) = config(olKey);
      uint gp;
      uint global_gasprice = _global.gasprice();
      if (global_gasprice > ofr_gasprice) {
        gp = global_gasprice;
      } else {
        gp = ofr_gasprice;
      }
      return (ofr_gasreq + _local.offer_gasbase()) * gp * 10 ** 9;
    }
  }

  // FIXME: once out/in/scale are packed, we can re-add an overload function like this:
  // function getProvisionWithDefaultGasPrice(address outbound_tkn, address inbound_tkn, ..., uint gasreq) public view returns (uint) {
  //   (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local) = MGV.config(olKey);
  //   return ((gasreq + _local.offer_gasbase()) * uint(_global.gasprice()) * 10 ** 9);
  // }

  /* Returns the fee that would be extracted from the given volume of outbound_tkn tokens on Mangrove's outbound_tkn/inbound_tkn offer list. */
  function getFee(OLKey memory olKey, uint outVolume) external view returns (uint) {
    (, MgvStructs.LocalPacked _local) = config(olKey);
    return ((outVolume * _local.fee()) / 10000);
  }

  /* Returns the given amount of outbound_tkn tokens minus the fee on Mangrove's outbound_tkn/inbound_tkn offer list. */
  function minusFee(OLKey memory olKey, uint outVolume) external view returns (uint) {
    (, MgvStructs.LocalPacked _local) = config(olKey);
    return (outVolume * (10_000 - _local.fee())) / 10000;
  }

  /* Convenience function to get an offer in packed format */
  function offers(OLKey memory olKey, uint offerId) public view returns (MgvStructs.OfferPacked offer) {
    OfferList storage _offerList = offerLists[olKey.hash()];
    unlockedMarketOnly(_offerList.local);
    return _offerList.offerData[offerId].offer;
  }

  /* Convenience function to get an offer detail in packed format */
  function offerDetails(OLKey memory olKey, uint offerId)
    public
    view
    returns (MgvStructs.OfferDetailPacked offerDetail)
  {
    OfferList storage _offerList = offerLists[olKey.hash()];
    unlockedMarketOnly(_offerList.local);
    return _offerList.offerData[offerId].detail;
  }

  /* Returns information about an offer in ABI-compatible structs. Do not use internally, would be a huge memory-copying waste. Use `offerLists[outbound_tkn][inbound_tkn].offers` and `offerLists[outbound_tkn][inbound_tkn].offerDetails` instead. */
  function offerInfo(OLKey memory olKey, uint offerId)
    public
    view
    returns (MgvStructs.OfferUnpacked memory offer, MgvStructs.OfferDetailUnpacked memory offerDetail)
  {
    unchecked {
      OfferList storage _offerList = offerLists[olKey.hash()];
      unlockedMarketOnly(_offerList.local);
      OfferData storage offerData = _offerList.offerData[offerId];
      offer = offerData.offer.to_struct();
      offerDetail = offerData.detail.to_struct();
    }
  }

  /*
   * Returns two uints.
   *
   * `startId` is the id of the best live offer with id equal or greater than
   * `fromId`, 0 if there is no such offer.
   *
   * `length` is 0 if `startId == 0`. Other it is the number of live offers as good or worse than the offer with
   * id `startId`.
   */
  function offerListEndPoints(OLKey memory olKey, uint fromId, uint maxOffers)
    public
    view
    returns (uint startId, uint length)
  {
    unchecked {
      if (fromId == 0) {
        startId = best(olKey);
      } else {
        startId = offers(olKey, fromId).gives() > 0 ? fromId : 0;
      }

      uint currentId = startId;

      while (currentId != 0 && length < maxOffers) {
        currentId = nextOfferId(olKey, offers(olKey, currentId));
        length = length + 1;
      }

      return (startId, length);
    }
  }

  struct OfferListArgs {
    OLKey olKey;
    uint fromId;
    uint maxOffers;
  }
  // Returns the orderbook for the outbound_tkn/inbound_tkn/tickScale offer list in packed form. First number is id of next offer (0 is we're done). First array is ids, second is offers (as bytes32), third is offerDetails (as bytes32). Array will be of size `min(# of offers in out/in list, maxOffers)`.

  function packedOfferList(OLKey memory olKey, uint fromId, uint maxOffers)
    public
    view
    returns (uint, uint[] memory, MgvStructs.OfferPacked[] memory, MgvStructs.OfferDetailPacked[] memory)
  {
    unchecked {
      OfferListArgs memory olh = OfferListArgs(olKey, fromId, maxOffers);
      (uint currentId, uint length) = offerListEndPoints(olh.olKey, olh.fromId, olh.maxOffers);

      uint[] memory offerIds = new uint[](length);
      MgvStructs.OfferPacked[] memory _offers = new MgvStructs.OfferPacked[](length);
      MgvStructs.OfferDetailPacked[] memory details = new MgvStructs.OfferDetailPacked[](length);

      uint i = 0;

      while (currentId != 0 && i < length) {
        offerIds[i] = currentId;
        _offers[i] = offers(olKey, currentId);
        details[i] = offerDetails(olKey, currentId);
        currentId = nextOfferId(olKey, _offers[i]);
        i = i + 1;
      }

      return (currentId, offerIds, _offers, details);
    }
  }

  // Returns the orderbook for the outbound_tkn/inbound_tkn/tickScale offer list in unpacked form. First number is id of next offer (0 if we're done). First array is ids, second is offers (as structs), third is offerDetails (as structs). Array will be of size `min(# of offers in out/in list, maxOffers)`.
  function offerList(OLKey memory olKey, uint fromId, uint maxOffers)
    public
    view
    returns (uint, uint[] memory, MgvStructs.OfferUnpacked[] memory, MgvStructs.OfferDetailUnpacked[] memory)
  {
    unchecked {
      OfferListArgs memory olh = OfferListArgs(olKey, fromId, maxOffers);
      (uint currentId, uint length) = offerListEndPoints(olh.olKey, olh.fromId, olh.maxOffers);

      uint[] memory offerIds = new uint[](length);
      MgvStructs.OfferUnpacked[] memory _offers = new MgvStructs.OfferUnpacked[](length);
      MgvStructs.OfferDetailUnpacked[] memory details = new MgvStructs.OfferDetailUnpacked[](length);

      uint i = 0;
      while (currentId != 0 && i < length) {
        offerIds[i] = currentId;
        (_offers[i], details[i]) = offerInfo(olKey, currentId);
        currentId = nextOfferIdById(olKey, currentId);
        i = i + 1;
      }

      return (currentId, offerIds, _offers, details);
    }
  }

  /* Next/Prev offers */
  // FIXME subticks for gas?
  // utility fn
  // VERY similar to MgvOfferTaking's getNextBest
  /// @notice Get the offer after a given offer, given its id
  function nextOfferIdById(OLKey memory olKey, uint offerId) public view returns (uint) {
    return nextOfferId(olKey, offers(olKey, offerId));
  }

  //FIXME replace these functions with "call mangrove for next offer, revert, return offer id"?
  /// @notice Get the offer after a given offer
  function nextOfferId(OLKey memory olKey, MgvStructs.OfferPacked offer) public view returns (uint) {
    // WARNING
    // If the offer is not actually recorded in the offer list, results will be meaningless.
    // if (offer.gives() == 0) {
    //   revert("Offer is not live, prev/next meaningless.");
    // }
    Tick offerTick = offer.tick(olKey.tickScale);
    uint nextId = offer.next();
    if (nextId == 0) {
      int index = offerTick.leafIndex();
      Leaf leaf = leafs(olKey, index);
      leaf = leaf.eraseToTick(offerTick);
      if (leaf.isEmpty()) {
        index = offerTick.level0Index();
        Field field = level0(olKey, index);
        field = field.eraseToTick0(offerTick);
        if (field.isEmpty()) {
          index = offerTick.level1Index();
          field = level1(olKey, index);
          field = field.eraseToTick1(offerTick);
          if (field.isEmpty()) {
            field = level2(olKey);
            field = field.eraseToTick2(offerTick);
            // FIXME: should I let log2 not revert, but just return 0 if x is 0?
            if (field.isEmpty()) {
              return 0;
            }
            index = field.firstLevel1Index();
            field = level1(olKey, index);
          }
          index = field.firstLevel0Index(index);
          field = level0(olKey, index);
        }
        leaf = leafs(olKey, field.firstLeafIndex(index));
      }
      nextId = leaf.getNextOfferId();
    }
    return nextId;
  }

  /// @notice Get the offer before a given offer, given its id
  function prevOfferIdById(OLKey memory olKey, uint offerId) public view returns (uint) {
    return prevOfferId(olKey, offers(olKey, offerId));
  }

  /// @notice Get the offer before a given offer
  function prevOfferId(OLKey memory olKey, MgvStructs.OfferPacked offer) public view returns (uint offerId) {
    // WARNING
    // If the offer is not actually recorded in the offer list, results will be meaningless.
    // if (offer.gives() == 0) {
    //   revert("Offer is not live, prev/next meaningless.");
    // }
    Tick offerTick = offer.tick(olKey.tickScale);
    uint prevId = offer.prev();
    if (prevId == 0) {
      int index = offerTick.leafIndex();
      Leaf leaf = leafs(olKey, index);
      leaf = leaf.eraseFromTick(offerTick);
      if (leaf.isEmpty()) {
        index = offerTick.level0Index();
        Field field = level0(olKey, index);
        field = field.eraseFromTick0(offerTick);
        if (field.isEmpty()) {
          index = offerTick.level1Index();
          field = level1(olKey, index);
          field = field.eraseFromTick1(offerTick);
          if (field.isEmpty()) {
            field = level2(olKey);
            field = field.eraseFromTick2(offerTick);
            // FIXME: should I let log2 not revert, but just return 0 if x is 0?
            if (field.isEmpty()) {
              return 0;
            }
            index = field.lastLevel1Index();
            field = level1(olKey, index);
          }
          index = field.lastLevel0Index(index);
          field = level0(olKey, index);
        }
        leaf = leafs(olKey, field.lastLeafIndex(index));
      }
      prevId = leaf.getNextOfferId();
    }
    return prevId;
  }

  /* Permit-related view functions */

  function allowances(address outbound_tkn, address inbound_tkn, address owner, address spender)
    external
    view
    returns (uint allowance)
  {
    allowance = _allowances[outbound_tkn][inbound_tkn][owner][spender];
  }

  function nonces(address owner) external view returns (uint nonce) {
    nonce = _nonces[owner];
  }

  // Note: the accessor for DOMAIN_SEPARATOR is defined in MgvStorage
  function PERMIT_TYPEHASH() external pure returns (bytes32) {
    return _PERMIT_TYPEHASH;
  }

  struct MarketOrder {
    OLKey olKey;
    int maxLogPrice;
    uint initialFillVolume;
    uint totalGot;
    uint totalGave;
    uint totalGasreq;
    uint currentFillVolume;
    uint currentWants;
    uint currentGives;
    bool fillWants;
    uint offerId;
    MgvStructs.OfferPacked offer;
    MgvStructs.OfferDetailPacked offerDetail;
    MgvStructs.LocalPacked local;
    VolumeData[] volumeData;
    uint numOffers;
    bool accumulate;
  }

  /* `simulateMarketOrderBy*`, `simulateInternalMarketOrder`, and `simulateExecute` all together simulate a market order on Mangrove and return the cumulative `totalGot`, `totalGave`, and `totalGasreq` for each offer traversed. We assume offer execution is successful and uses exactly its `gasreq`. 
  We do not account for gasbase.
  * Calling this from an EOA will give you an estimate of the volumes you will receive, but you may as well `eth_call` Mangrove.
  * Calling this from a contract will let the contract choose what to do after receiving a response.
  * If `!accumulate`, only return the total cumulative volume.
  */
  function simulateMarketOrderByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants)
    external
    view
    returns (VolumeData[] memory)
  {
    return simulateMarketOrderByVolume(olKey, takerWants, takerGives, fillWants, true);
  }

  function simulateMarketOrderByVolume(
    OLKey memory olKey,
    uint takerWants,
    uint takerGives,
    bool fillWants,
    bool accumulate
  ) public view returns (VolumeData[] memory) {
    uint fillVolume = fillWants ? takerWants : takerGives;
    int maxLogPrice = LogPriceConversionLib.logPriceFromVolumes(takerGives, takerWants);
    return simulateMarketOrderByLogPrice(olKey, maxLogPrice, fillVolume, fillWants, accumulate);
  }

  function simulateMarketOrderByLogPrice(OLKey memory olKey, int maxLogPrice, uint fillVolume, bool fillWants)
    public
    view
    returns (VolumeData[] memory)
  {
    return simulateMarketOrderByLogPrice(olKey, maxLogPrice, fillVolume, fillWants, true);
  }

  function simulateMarketOrderByLogPrice(
    OLKey memory olKey,
    int maxLogPrice,
    uint fillVolume,
    bool fillWants,
    bool accumulate
  ) public view returns (VolumeData[] memory) {
    MarketOrder memory mr;
    mr.olKey = olKey;
    (, mr.local) = config(olKey);
    mr.offerId = best(olKey);
    mr.offer = offers(olKey, mr.offerId);
    mr.maxLogPrice = maxLogPrice;
    mr.currentFillVolume = fillVolume;
    mr.initialFillVolume = fillVolume;
    mr.fillWants = fillWants;
    mr.accumulate = accumulate;

    simulateInternalMarketOrder(mr);

    return mr.volumeData;
  }

  function simulateInternalMarketOrder(MarketOrder memory mr) internal view {
    unchecked {
      if (mr.currentFillVolume > 0 && mr.offerId > 0 && mr.offer.logPrice() <= mr.maxLogPrice) {
        uint currentIndex = mr.numOffers;

        mr.offerDetail = offerDetails(mr.olKey, mr.offerId);

        simulateExecute(mr);

        uint totalGot = mr.totalGot;
        uint totalGave = mr.totalGave;
        uint totalGasreq = mr.totalGasreq;

        mr.numOffers++;
        mr.currentFillVolume -= mr.fillWants ? mr.currentWants : mr.currentGives;

        mr.offerId = nextOfferId(mr.olKey, mr.offer);
        mr.offer = offers(mr.olKey, mr.offerId);

        simulateInternalMarketOrder(mr);

        if (mr.accumulate || currentIndex == 0) {
          uint concreteFee = (mr.totalGot * mr.local.fee()) / 10_000;
          mr.volumeData[currentIndex] =
            VolumeData({totalGot: totalGot - concreteFee, totalGave: totalGave, totalGasreq: totalGasreq});
        }
      } else {
        if (mr.accumulate) {
          mr.volumeData = new VolumeData[](mr.numOffers);
        } else {
          mr.volumeData = new VolumeData[](1);
        }
      }
    }
  }

  function simulateExecute(MarketOrder memory mr) internal pure {
    unchecked {
      {
        // caching
        uint fillVolume = mr.currentFillVolume;
        uint offerGives = mr.offer.gives();
        uint offerWants = mr.offer.wants();

        if ((mr.fillWants && offerGives < fillVolume) || (!mr.fillWants && offerWants < fillVolume)) {
          mr.currentWants = offerGives;
          mr.currentGives = offerWants;
        } else {
          if (mr.fillWants) {
            mr.currentGives = LogPriceLib.inboundFromOutboundUp(mr.offer.logPrice(), fillVolume);
            mr.currentWants = fillVolume;
          } else {
            // offerWants = 0 is forbidden at offer writing
            mr.currentWants = LogPriceLib.outboundFromInbound(mr.offer.logPrice(), fillVolume);
            mr.currentGives = fillVolume;
          }
        }
      }

      // flashloan would normally be called here

      // if success branch of original mangrove code, assumed to be true
      mr.totalGot += mr.currentWants;
      mr.totalGave += mr.currentGives;
      mr.totalGasreq += mr.offerDetail.gasreq();
      /* end if success branch **/
    }
  }
}
