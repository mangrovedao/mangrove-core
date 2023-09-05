// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib, MgvStructs, Tick, Leaf, Field, LogPriceLib, OLKey} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import "mgv_lib/Debug.sol";

struct VolumeData {
  uint totalGot;
  uint totalGave;
  uint totalGasreq;
}

struct Market {
  address tkn0;
  address tkn1;
  uint tickScale;
}

/// @notice Config of a market. Assumes a context where `tkn0` and `tkn1` are defined. `config01` is the local config of the `tkn0/tkn1` offer list. `config10` is the config of the `tkn1/tkn0` offer list.
struct MarketConfig {
  MgvStructs.LocalUnpacked config01;
  MgvStructs.LocalUnpacked config10;
}

/// @notice We choose a canonical orientation for all markets based on the numerical values of their token addresses. That way we can uniquely identify a market with two addresses given in any order.
/// @return address the lowest of the given arguments (numerically)
/// @return address the highest of the given arguments (numerically)
function order(address tkn0, address tkn1) pure returns (address, address) {
  return uint160(tkn0) < uint160(tkn1) ? (tkn0, tkn1) : (tkn1, tkn0);
}

// canonically order the tokens of a Market
// modifies in-place
function order(Market memory market) pure {
  (market.tkn0, market.tkn1) = order(market.tkn0, market.tkn1);
}

// flip tkn0/tkn1 of a market. Useful before conversion to OLKey
// creates a copy
function flipped(Market memory market) pure returns (Market memory) {
  return Market(market.tkn1, market.tkn0, market.tickScale);
}

// convert Market to OLKey
// creates a copy
function toOLKey(Market memory market) pure returns (OLKey memory) {
  return OLKey(market.tkn0, market.tkn1, market.tickScale);
}

contract MgvReader {
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
  /**
   * @notice Open markets tracking (below) provides information about which markets on Mangrove are open. Anyone can update a market status by calling `updateMarket`.
   * @notice The array of structs `_openMarkets` is the array of all currently open markets (up to a delay in calling `updateMarkets`). A market is a triplet of tokens `(tkn0,tkn1,tickScale)`. The which token is 0 which token is 1 is non-meaningful but canonical (see `order`).
   * @notice In this contract, 'markets' are defined by non-oriented offerLists. Usually markets come with a base/quote orientation. Please keep that in mind.
   * @notice A market {tkn0,tkn1} is open if either the tkn0/tkn1 offer list is active or the tkn1/tkn0 offer list is active.
   */

  Market[] internal _openMarkets;

  /// @notice Markets can be added or removed from `_openMarkets` array. To remove a market, we must remember its position in the array. The `marketPositions` mapping does that. The mapping goes outbound => inbound => tickScale => positions.
  mapping(address => mapping(address => mapping(uint => uint))) internal marketPositions;

  IMangrove public immutable MGV;

  constructor(address mgv) {
    MGV = IMangrove(payable(mgv));
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
        startId = MGV.best(olKey);
      } else {
        startId = MGV.offers(olKey, fromId).gives() > 0 ? fromId : 0;
      }

      uint currentId = startId;

      while (currentId != 0 && length < maxOffers) {
        currentId = nextOfferId(olKey, MGV.offers(olKey, currentId));
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
      MgvStructs.OfferPacked[] memory offers = new MgvStructs.OfferPacked[](length);
      MgvStructs.OfferDetailPacked[] memory details = new MgvStructs.OfferDetailPacked[](length);

      uint i = 0;

      while (currentId != 0 && i < length) {
        offerIds[i] = currentId;
        offers[i] = MGV.offers(olKey, currentId);
        details[i] = MGV.offerDetails(olKey, currentId);
        currentId = nextOfferId(olKey, offers[i]);
        i = i + 1;
      }

      return (currentId, offerIds, offers, details);
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
      MgvStructs.OfferUnpacked[] memory offers = new MgvStructs.OfferUnpacked[](length);
      MgvStructs.OfferDetailUnpacked[] memory details = new MgvStructs.OfferDetailUnpacked[](length);

      uint i = 0;
      while (currentId != 0 && i < length) {
        offerIds[i] = currentId;
        (offers[i], details[i]) = MGV.offerInfo(olKey, currentId);
        currentId = nextOfferIdById(olKey, currentId);
        i = i + 1;
      }

      return (currentId, offerIds, offers, details);
    }
  }

  /* Returns the minimum outbound_tkn volume to give on the outbound_tkn/inbound_tkn offer list for an offer that requires gasreq gas. */
  function minVolume(OLKey memory olKey, uint gasreq) public view returns (uint) {
    MgvStructs.LocalPacked _local = local(olKey);
    return _local.density().multiplyUp(gasreq + _local.offer_gasbase());
  }

  /* Returns the provision necessary to post an offer on the outbound_tkn/inbound_tkn offer list. You can set gasprice=0 or use the overload to use Mangrove's internal gasprice estimate. */
  function getProvision(OLKey memory olKey, uint ofr_gasreq, uint ofr_gasprice) public view returns (uint) {
    unchecked {
      (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local) = MGV.config(olKey);
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

  /* Sugar for checking whether a offer list is empty. There is no offer with id 0, so if the id of the offer list's best offer is 0, it means the offer list is empty. */
  function isEmptyOB(OLKey memory olKey) public view returns (bool) {
    return MGV.best(olKey) == 0;
  }

  /* Returns the fee that would be extracted from the given volume of outbound_tkn tokens on Mangrove's outbound_tkn/inbound_tkn offer list. */
  function getFee(OLKey memory olKey, uint outVolume) public view returns (uint) {
    (, MgvStructs.LocalPacked _local) = MGV.config(olKey);
    return ((outVolume * _local.fee()) / 10000);
  }

  /* Returns the given amount of outbound_tkn tokens minus the fee on Mangrove's outbound_tkn/inbound_tkn offer list. */
  function minusFee(OLKey memory olKey, uint outVolume) public view returns (uint) {
    (, MgvStructs.LocalPacked _local) = MGV.config(olKey);
    return (outVolume * (10_000 - _local.fee())) / 10000;
  }

  /* Sugar for getting only global/local config */
  function global() public view returns (MgvStructs.GlobalPacked) {
    (MgvStructs.GlobalPacked _global,) = MGV.config(OLKey(address(0), address(0), 0));
    return _global;
  }

  function local(OLKey memory olKey) public view returns (MgvStructs.LocalPacked) {
    (, MgvStructs.LocalPacked _local) = MGV.config(olKey);
    return _local;
  }

  function globalUnpacked() public view returns (MgvStructs.GlobalUnpacked memory) {
    return global().to_struct();
  }

  function localUnpacked(OLKey memory olKey) public view returns (MgvStructs.LocalUnpacked memory) {
    return local(olKey).to_struct();
  }

  /* `marketOrderBy*`, `internalMarketOrder`, and `execute` all together simulate a market order on Mangrove and return the cumulative `totalGot`, `totalGave`, and `totalGasreq` for each offer traversed. We assume offer execution is successful and uses exactly its `gasreq`. 
  We do not account for gasbase.
  * Calling this from an EOA will give you an estimate of the volumes you will receive, but you may as well `eth_call` Mangrove.
  * Calling this from a contract will let the contract choose what to do after receiving a response.
  * If `!accumulate`, only return the total cumulative volume.
  */
  function marketOrderByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants)
    public
    view
    returns (VolumeData[] memory)
  {
    return marketOrderByVolume(olKey, takerWants, takerGives, fillWants, true);
  }

  function marketOrderByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants, bool accumulate)
    public
    view
    returns (VolumeData[] memory)
  {
    uint fillVolume = fillWants ? takerWants : takerGives;
    int maxLogPrice = LogPriceConversionLib.logPriceFromVolumes(takerGives, takerWants);
    return marketOrderByLogPrice(olKey, maxLogPrice, fillVolume, fillWants, accumulate);
  }

  function marketOrderByLogPrice(OLKey memory olKey, int maxLogPrice, uint fillVolume, bool fillWants)
    public
    view
    returns (VolumeData[] memory)
  {
    return marketOrderByLogPrice(olKey, maxLogPrice, fillVolume, fillWants, true);
  }

  function marketOrderByLogPrice(OLKey memory olKey, int maxLogPrice, uint fillVolume, bool fillWants, bool accumulate)
    public
    view
    returns (VolumeData[] memory)
  {
    MarketOrder memory mr;
    mr.olKey = olKey;
    (, mr.local) = MGV.config(olKey);
    mr.offerId = MGV.best(olKey);
    mr.offer = MGV.offers(olKey, mr.offerId);
    mr.maxLogPrice = maxLogPrice;
    mr.currentFillVolume = fillVolume;
    mr.initialFillVolume = fillVolume;
    mr.fillWants = fillWants;
    mr.accumulate = accumulate;

    internalMarketOrder(mr);

    return mr.volumeData;
  }

  function internalMarketOrder(MarketOrder memory mr) internal view {
    console.log("internalMO");
    console.log("  mr.maxLogPrice: %s", vm.toString(mr.maxLogPrice));
    console.log("  mr.offerID: %s,  logPrice: %s", mr.offerId, vm.toString(mr.offer.logPrice()));
    unchecked {
      if (mr.currentFillVolume > 0 && mr.offerId > 0 && mr.offer.logPrice() <= mr.maxLogPrice) {
        uint currentIndex = mr.numOffers;

        mr.offerDetail = MGV.offerDetails(mr.olKey, mr.offerId);

        execute(mr);

        uint totalGot = mr.totalGot;
        uint totalGave = mr.totalGave;
        uint totalGasreq = mr.totalGasreq;

        mr.numOffers++;
        mr.currentFillVolume -= mr.fillWants ? mr.currentWants : mr.currentGives;

        mr.offerId = nextOfferId(mr.olKey, mr.offer);
        mr.offer = MGV.offers(mr.olKey, mr.offerId);

        internalMarketOrder(mr);

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

  function execute(MarketOrder memory mr) internal pure {
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

  /// @return uint The number of open markets.
  function numOpenMarkets() external view returns (uint) {
    return _openMarkets.length;
  }

  /// @return markets all open markets
  /// @return configs the configs of each markets
  /// @notice If the ith market is [tkn0,tkn1], then the ith config will be a MarketConfig where config01 is the config for the tkn0/tkn1 offer list, and config10 is the config for the tkn1/tkn0 offer list.
  function openMarkets() external view returns (Market[] memory, MarketConfig[] memory) {
    return openMarkets(0, _openMarkets.length, true);
  }

  /// @notice List open markets, and optionally skip querying Mangrove for all the market configurations.
  /// @param withConfig if false, the second return value will be the empty array.
  /// @return Market[] all open markets
  /// @return MarketConfig[] corresponding configs, or the empty array if withConfig is false.
  function openMarkets(bool withConfig) external view returns (Market[] memory, MarketConfig[] memory) {
    return openMarkets(0, _openMarkets.length, withConfig);
  }

  /// @notice Get a slice of open markets, with accompanying market configs
  /// @return markets The following slice of _openMarkets: [from..min(_openMarkets.length,from+maxLen)]
  /// @return configs corresponding configs
  /// @dev throws if `from > _openMarkets.length`
  function openMarkets(uint from, uint maxLen)
    external
    view
    returns (Market[] memory markets, MarketConfig[] memory configs)
  {
    return openMarkets(from, maxLen, true);
  }

  /// @notice Get a slice of open markets, with accompanying market configs or not.
  /// @param withConfig if false, the second return value will be the empty array.
  /// @return markets The following slice of _openMarkets: [from..min(_openMarkets.length,from+maxLen)]
  /// @return configs corresponding configs, or the empty array if withConfig is false.
  /// @dev if there is a delay in updating a market, it is possible that an 'open market' (according to this contract) is not in fact open and that config01.active and config10.active are both false.
  /// @dev throws if `from > _openMarkets.length`
  function openMarkets(uint from, uint maxLen, bool withConfig)
    public
    view
    returns (Market[] memory markets, MarketConfig[] memory configs)
  {
    uint numMarkets = _openMarkets.length;
    if (from + maxLen > numMarkets) {
      maxLen = numMarkets - from;
    }
    markets = new Market[](maxLen);
    configs = new MarketConfig[](withConfig ? maxLen : 0);
    unchecked {
      for (uint i = 0; i < maxLen; ++i) {
        address tkn0 = _openMarkets[from + i].tkn0;
        address tkn1 = _openMarkets[from + i].tkn1;
        uint tickScale = _openMarkets[from + i].tickScale;
        // copy
        markets[i] = Market({tkn0: tkn0, tkn1: tkn1, tickScale: tickScale});

        if (withConfig) {
          configs[i].config01 = localUnpacked(toOLKey(markets[i]));
          configs[i].config10 = localUnpacked(toOLKey(flipped(markets[i])));
        }
      }
    }
  }

  /// @param market the market
  /// @return bool Whether the {tkn0,tkn1} market is open.
  /// @dev May not reflect the true state of the market on Mangrove if `updateMarket` was not called recently enough.
  function isMarketOpen(Market memory market) external view returns (bool) {
    (market.tkn0, market.tkn1) = order(market.tkn0, market.tkn1);
    return marketPositions[market.tkn0][market.tkn1][market.tickScale] > 0;
  }

  /// @notice return the configuration for the given market
  /// @param market the market
  /// @return config The market configuration. config01 and config10 follow the order given in arguments, not the canonical order
  /// @dev This function queries Mangrove so all the returned info is up-to-date.
  function marketConfig(Market memory market) external view returns (MarketConfig memory config) {
    config.config01 = localUnpacked(toOLKey(market));
    config.config10 = localUnpacked(toOLKey(flipped(market)));
  }

  /// @notice Permisionless update of _openMarkets array.
  /// @notice Will consider a market open iff either the offer lists tkn0/tkn1 or tkn1/tkn0 are open on Mangrove.
  function updateMarket(Market memory market) external {
    (market.tkn0, market.tkn1) = order(market.tkn0, market.tkn1);
    bool openOnMangrove = local(toOLKey(market)).active() || local(toOLKey(flipped(market))).active();
    uint position = marketPositions[market.tkn0][market.tkn1][market.tickScale];

    if (openOnMangrove && position == 0) {
      _openMarkets.push(market);
      marketPositions[market.tkn0][market.tkn1][market.tickScale] = _openMarkets.length;
    } else if (!openOnMangrove && position > 0) {
      uint numMarkets = _openMarkets.length;
      if (numMarkets > 1) {
        // avoid array holes
        Market memory lastMarket = _openMarkets[numMarkets - 1];

        _openMarkets[position - 1] = lastMarket;
        //FIXME add tests that check the last component (lastMarket.tickScale) is correct
        marketPositions[lastMarket.tkn0][lastMarket.tkn1][lastMarket.tickScale] = position;
      }
      _openMarkets.pop();
      marketPositions[market.tkn0][market.tkn1][market.tickScale] = 0;
    }
  }

  /* Next/Prev offers */

  // FIXME subticks for gas?
  // utility fn
  /// @notice Get the offer after a given offer, given its id
  function nextOfferIdById(OLKey memory olKey, uint offerId) public view returns (uint) {
    return nextOfferId(olKey, MGV.offers(olKey, offerId));
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
      Leaf leaf = MGV.leafs(olKey, index);
      leaf = leaf.eraseToTick(offerTick);
      if (leaf.isEmpty()) {
        index = offerTick.level0Index();
        Field field = MGV.level0(olKey, index);
        field = field.eraseToTick0(offerTick);
        if (field.isEmpty()) {
          index = offerTick.level1Index();
          field = MGV.level1(olKey, index);
          field = field.eraseToTick1(offerTick);
          if (field.isEmpty()) {
            field = MGV.level2(olKey);
            field = field.eraseToTick2(offerTick);
            // FIXME: should I let log2 not revert, but just return 0 if x is 0?
            if (field.isEmpty()) {
              return 0;
            }
            index = field.firstLevel1Index();
            field = MGV.level1(olKey, index);
          }
          index = field.firstLevel0Index(index);
          field = MGV.level0(olKey, index);
        }
        leaf = MGV.leafs(olKey, field.firstLeafIndex(index));
      }
      nextId = leaf.getNextOfferId();
    }
    return nextId;
  }

  /// @notice Get the offer before a given offer, given its id
  function prevOfferIdById(OLKey memory olKey, uint offerId) public view returns (uint) {
    return prevOfferId(olKey, MGV.offers(olKey, offerId));
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
      Leaf leaf = MGV.leafs(olKey, index);
      leaf = leaf.eraseFromTick(offerTick);
      if (leaf.isEmpty()) {
        index = offerTick.level0Index();
        Field field = MGV.level0(olKey, index);
        field = field.eraseFromTick0(offerTick);
        if (field.isEmpty()) {
          index = offerTick.level1Index();
          field = MGV.level1(olKey, index);
          field = field.eraseFromTick1(offerTick);
          if (field.isEmpty()) {
            field = MGV.level2(olKey);
            field = field.eraseFromTick2(offerTick);
            // FIXME: should I let log2 not revert, but just return 0 if x is 0?
            if (field.isEmpty()) {
              return 0;
            }
            index = field.lastLevel1Index();
            field = MGV.level1(olKey, index);
          }
          index = field.lastLevel0Index(index);
          field = MGV.level0(olKey, index);
        }
        leaf = MGV.leafs(olKey, field.lastLeafIndex(index));
      }
      prevId = leaf.getNextOfferId();
    }
    return prevId;
  }
}
