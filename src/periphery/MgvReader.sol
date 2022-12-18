// SPDX-License-Identifier:	AGPL-3.0

// MgvReader.sol

// Copyright (C) 2021 ADDMA.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity ^0.8.10;

import {MgvLib, MgvStructs} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import "forge-std/console.sol";

struct VolumeData {
  uint totalGot;
  uint totalGave;
  uint totalGasreq;
}

contract MgvReader {
  struct MarketOrder {
    address outbound_tkn;
    address inbound_tkn;
    uint initialWants;
    uint initialGives;
    uint totalGot;
    uint totalGave;
    uint totalGasreq;
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
   * @notice The array of pairs `_openMarkets` is the array of all currently open markets (up to a delay in calling `updateMarkets`). A market is a pair of tokens `[tkn0,tkn1]`. The orientation is non-meaningful but canonical (see `order`).
   * @notice In this contract, 'markets' are defined by non-oriented pairs. Usually markets come with a base/quote orientation. Please keep that in mind.
   * @notice A market {tkn0,tkn1} is open if either the tkn0/tkn1 offer list is active or the tkn1/tkn0 offer list is active.
   */
  address[2][] internal _openMarkets;

  /// @notice Markets can be added or removed from `_openMarkets` array. To remove a market, we must remember its position in the array. The `marketPositions` mapping does that.
  mapping(address => mapping(address => uint)) internal marketPositions;

  /// @notice Config of a market. Assumes a context where `tkn0` and `tkn1` are defined. `config01` is the local config of the `tkn0/tkn1` offer list. `config10` is the config of the `tkn1/tkn0` offer list.
  struct MarketConfig {
    MgvStructs.LocalUnpacked config01;
    MgvStructs.LocalUnpacked config10;
  }

  IMangrove immutable MGV;

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
  function offerListEndPoints(address outbound_tkn, address inbound_tkn, uint fromId, uint maxOffers)
    public
    view
    returns (uint startId, uint length)
  {
    unchecked {
      if (fromId == 0) {
        startId = MGV.best(outbound_tkn, inbound_tkn);
      } else {
        startId = MGV.offers(outbound_tkn, inbound_tkn, fromId).gives() > 0 ? fromId : 0;
      }

      uint currentId = startId;

      while (currentId != 0 && length < maxOffers) {
        currentId = MGV.offers(outbound_tkn, inbound_tkn, currentId).next();
        length = length + 1;
      }

      return (startId, length);
    }
  }

  // Returns the orderbook for the outbound_tkn/inbound_tkn pair in packed form. First number is id of next offer (0 is we're done). First array is ids, second is offers (as bytes32), third is offerDetails (as bytes32). Array will be of size `min(# of offers in out/in list, maxOffers)`.
  function packedOfferList(address outbound_tkn, address inbound_tkn, uint fromId, uint maxOffers)
    public
    view
    returns (uint, uint[] memory, MgvStructs.OfferPacked[] memory, MgvStructs.OfferDetailPacked[] memory)
  {
    unchecked {
      (uint currentId, uint length) = offerListEndPoints(outbound_tkn, inbound_tkn, fromId, maxOffers);

      uint[] memory offerIds = new uint[](length);
      MgvStructs.OfferPacked[] memory offers = new MgvStructs.OfferPacked[](length);
      MgvStructs.OfferDetailPacked[] memory details = new MgvStructs.OfferDetailPacked[](length);

      uint i = 0;

      while (currentId != 0 && i < length) {
        offerIds[i] = currentId;
        offers[i] = MGV.offers(outbound_tkn, inbound_tkn, currentId);
        details[i] = MGV.offerDetails(outbound_tkn, inbound_tkn, currentId);
        currentId = offers[i].next();
        i = i + 1;
      }

      return (currentId, offerIds, offers, details);
    }
  }

  // Returns the orderbook for the outbound_tkn/inbound_tkn pair in unpacked form. First number is id of next offer (0 if we're done). First array is ids, second is offers (as structs), third is offerDetails (as structs). Array will be of size `min(# of offers in out/in list, maxOffers)`.
  function offerList(address outbound_tkn, address inbound_tkn, uint fromId, uint maxOffers)
    public
    view
    returns (uint, uint[] memory, MgvStructs.OfferUnpacked[] memory, MgvStructs.OfferDetailUnpacked[] memory)
  {
    unchecked {
      (uint currentId, uint length) = offerListEndPoints(outbound_tkn, inbound_tkn, fromId, maxOffers);

      uint[] memory offerIds = new uint[](length);
      MgvStructs.OfferUnpacked[] memory offers = new MgvStructs.OfferUnpacked[](length);
      MgvStructs.OfferDetailUnpacked[] memory details = new MgvStructs.OfferDetailUnpacked[](length);

      uint i = 0;
      while (currentId != 0 && i < length) {
        offerIds[i] = currentId;
        (offers[i], details[i]) = MGV.offerInfo(outbound_tkn, inbound_tkn, currentId);
        currentId = offers[i].next;
        i = i + 1;
      }

      return (currentId, offerIds, offers, details);
    }
  }

  /* Returns the minimum outbound_tkn volume to give on the outbound_tkn/inbound_tkn offer list for an offer that requires gasreq gas. */
  function minVolume(address outbound_tkn, address inbound_tkn, uint gasreq) public view returns (uint) {
    MgvStructs.LocalPacked _local = local(outbound_tkn, inbound_tkn);
    return (gasreq + _local.offer_gasbase()) * _local.density();
  }

  /* Returns the provision necessary to post an offer on the outbound_tkn/inbound_tkn offer list. You can set gasprice=0 or use the overload to use Mangrove's internal gasprice estimate. */
  function getProvision(address outbound_tkn, address inbound_tkn, uint ofr_gasreq, uint ofr_gasprice)
    public
    view
    returns (uint)
  {
    unchecked {
      (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local) = MGV.config(outbound_tkn, inbound_tkn);
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

  function getProvision(address outbound_tkn, address inbound_tkn, uint gasreq) public view returns (uint) {
    (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local) = MGV.config(outbound_tkn, inbound_tkn);
    return ((gasreq + _local.offer_gasbase()) * uint(_global.gasprice()) * 10 ** 9);
  }

  /* Sugar for checking whether a offer list is empty. There is no offer with id 0, so if the id of the offer list's best offer is 0, it means the offer list is empty. */
  function isEmptyOB(address outbound_tkn, address inbound_tkn) public view returns (bool) {
    return MGV.best(outbound_tkn, inbound_tkn) == 0;
  }

  /* Returns the fee that would be extracted from the given volume of outbound_tkn tokens on Mangrove's outbound_tkn/inbound_tkn offer list. */
  function getFee(address outbound_tkn, address inbound_tkn, uint outVolume) public view returns (uint) {
    (, MgvStructs.LocalPacked _local) = MGV.config(outbound_tkn, inbound_tkn);
    return ((outVolume * _local.fee()) / 10000);
  }

  /* Returns the given amount of outbound_tkn tokens minus the fee on Mangrove's outbound_tkn/inbound_tkn offer list. */
  function minusFee(address outbound_tkn, address inbound_tkn, uint outVolume) public view returns (uint) {
    (, MgvStructs.LocalPacked _local) = MGV.config(outbound_tkn, inbound_tkn);
    return (outVolume * (10_000 - _local.fee())) / 10000;
  }

  /* Sugar for getting only global/local config */
  function global() public view returns (MgvStructs.GlobalPacked) {
    (MgvStructs.GlobalPacked _global,) = MGV.config(address(0), address(0));
    return _global;
  }

  function local(address outbound_tkn, address inbound_tkn) public view returns (MgvStructs.LocalPacked) {
    (, MgvStructs.LocalPacked _local) = MGV.config(outbound_tkn, inbound_tkn);
    return _local;
  }

  function globalUnpacked() public view returns (MgvStructs.GlobalUnpacked memory) {
    return global().to_struct();
  }

  function localUnpacked(address outbound_tkn, address inbound_tkn)
    public
    view
    returns (MgvStructs.LocalUnpacked memory)
  {
    return local(outbound_tkn, inbound_tkn).to_struct();
  }

  /* marketOrder, internalMarketOrder, and execute all together simulate a market order on mangrove and return the cumulative totalGot, totalGave and totalGasreq for each offer traversed. We assume offer execution is successful and uses exactly its gasreq. 
  We do not account for gasbase.
  * Calling this from an EOA will give you an estimate of the volumes you will receive, but you may as well `eth_call` Mangrove.
  * Calling this from a contract will let the contract choose what to do after receiving a response.
  * If `!accumulate`, only return the total cumulative volume.
  */
  function marketOrder(
    address outbound_tkn,
    address inbound_tkn,
    uint takerWants,
    uint takerGives,
    bool fillWants,
    bool accumulate
  ) public view returns (VolumeData[] memory) {
    MarketOrder memory mr;
    mr.outbound_tkn = outbound_tkn;
    mr.inbound_tkn = inbound_tkn;
    (, mr.local) = MGV.config(outbound_tkn, inbound_tkn);
    mr.offerId = mr.local.best();
    mr.offer = MGV.offers(outbound_tkn, inbound_tkn, mr.offerId);
    mr.currentWants = takerWants;
    mr.currentGives = takerGives;
    mr.initialWants = takerWants;
    mr.initialGives = takerGives;
    mr.fillWants = fillWants;
    mr.accumulate = accumulate;

    internalMarketOrder(mr, true);

    return mr.volumeData;
  }

  function marketOrder(address outbound_tkn, address inbound_tkn, uint takerWants, uint takerGives, bool fillWants)
    external
    view
    returns (VolumeData[] memory)
  {
    return marketOrder(outbound_tkn, inbound_tkn, takerWants, takerGives, fillWants, true);
  }

  function internalMarketOrder(MarketOrder memory mr, bool proceed) internal view {
    unchecked {
      if (proceed && (mr.fillWants ? mr.currentWants > 0 : mr.currentGives > 0) && mr.offerId > 0) {
        uint currentIndex = mr.numOffers;

        mr.offerDetail = MGV.offerDetails(mr.outbound_tkn, mr.inbound_tkn, mr.offerId);

        bool executed = execute(mr);

        uint totalGot = mr.totalGot;
        uint totalGave = mr.totalGave;
        uint totalGasreq = mr.totalGasreq;

        if (executed) {
          mr.numOffers++;
          mr.currentWants = mr.initialWants > mr.totalGot ? mr.initialWants - mr.totalGot : 0;
          mr.currentGives = mr.initialGives - mr.totalGave;
          mr.offerId = mr.offer.next();
          mr.offer = MGV.offers(mr.outbound_tkn, mr.inbound_tkn, mr.offerId);
        }

        internalMarketOrder(mr, executed);

        if (executed && (mr.accumulate || currentIndex == 0)) {
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

  function execute(MarketOrder memory mr) internal pure returns (bool) {
    unchecked {
      {
        // caching
        uint offerWants = mr.offer.wants();
        uint offerGives = mr.offer.gives();
        uint takerWants = mr.currentWants;
        uint takerGives = mr.currentGives;

        if (offerWants * takerWants > offerGives * takerGives) {
          return false;
        }

        if ((mr.fillWants && offerGives < takerWants) || (!mr.fillWants && offerWants < takerGives)) {
          mr.currentWants = offerGives;
          mr.currentGives = offerWants;
        } else {
          if (mr.fillWants) {
            uint product = offerWants * takerWants;
            mr.currentGives = product / offerGives + (product % offerGives == 0 ? 0 : 1);
          } else {
            if (offerWants == 0) {
              mr.currentWants = offerGives;
            } else {
              mr.currentWants = (offerGives * takerGives) / offerWants;
            }
          }
        }
      }

      // flashloan would normally be called here

      /**
       * if success branch of original mangrove code, assumed to be true
       */
      mr.totalGot += mr.currentWants;
      mr.totalGave += mr.currentGives;
      mr.totalGasreq += mr.offerDetail.gasreq();
      return true;
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
  function openMarkets() external view returns (address[2][] memory, MarketConfig[] memory) {
    return openMarkets(0, _openMarkets.length, true);
  }

  /// @notice List open markets, and optionally skip querying Mangrove for all the market configurations.
  /// @param withConfig if false, the second return value will be the empty array.
  /// @return address[2][] all open markets
  /// @return MarketConfig[] corresponding configs, or the empty array if withConfig is false.
  function openMarkets(bool withConfig) external view returns (address[2][] memory, MarketConfig[] memory) {
    return openMarkets(0, _openMarkets.length, withConfig);
  }

  /// @notice Get a slice of open markets, with accompanying market configs
  /// @return markets The following slice of _openMarkets: [from..min(_openMarkets.length,from+maxLen)]
  /// @return configs corresponding configs
  /// @dev throws if `from > _openMarkets.length`
  function openMarkets(uint from, uint maxLen)
    external
    view
    returns (address[2][] memory markets, MarketConfig[] memory configs)
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
    returns (address[2][] memory markets, MarketConfig[] memory configs)
  {
    uint numMarkets = _openMarkets.length;
    if (from + maxLen > numMarkets) {
      maxLen = numMarkets - from;
    }
    markets = new address[2][](maxLen);
    configs = new MarketConfig[](withConfig ? maxLen : 0);
    unchecked {
      for (uint i = 0; i < maxLen; i++) {
        address tkn0 = _openMarkets[from + i][0];
        address tkn1 = _openMarkets[from + i][1];
        markets[i] = [tkn0, tkn1];

        if (withConfig) {
          configs[i].config01 = localUnpacked(tkn0, tkn1);
          configs[i].config10 = localUnpacked(tkn1, tkn0);
        }
      }
    }
  }

  /// @notice We choose a canonical orientation for all markets based on the numerical values of their token addresses. That way we can uniquely identify a market with two addresses given in any order.
  /// @return address the lowest of the given arguments (numerically)
  /// @return address the highest of the given arguments (numerically)
  function order(address tkn0, address tkn1) public pure returns (address, address) {
    return uint160(tkn0) < uint160(tkn1) ? (tkn0, tkn1) : (tkn1, tkn0);
  }

  /// @param tkn0 one token of the market
  /// @param tkn1 another token of the market
  /// @return bool Whether the {tkn0,tkn1} market is open.
  /// @dev May not reflect the true state of the market on Mangrove if `updateMarket` was not called recently enough.
  function isMarketOpen(address tkn0, address tkn1) external view returns (bool) {
    (tkn0, tkn1) = order(tkn0, tkn1);
    return marketPositions[tkn0][tkn1] > 0;
  }

  /// @notice return the configuration for the given market
  /// @param tkn0 one token of the market
  /// @param tkn1 another token of the market
  /// @return config The market configuration. config01 and config10 follow the order given in arguments, not the canonical order
  /// @dev This function queries Mangrove so all the returned info is up-to-date.
  function marketConfig(address tkn0, address tkn1) external view returns (MarketConfig memory config) {
    config.config01 = localUnpacked(tkn0, tkn1);
    config.config10 = localUnpacked(tkn1, tkn0);
  }

  /// @notice Permisionless update of _openMarkets array.
  /// @notice Will consider a market open iff either the offer lists tkn0/tkn1 or tkn1/tkn0 are open on Mangrove.
  function updateMarket(address tkn0, address tkn1) external {
    bool openOnMangrove = local(tkn0, tkn1).active() || local(tkn1, tkn0).active();
    (tkn0, tkn1) = order(tkn0, tkn1);
    uint position = marketPositions[tkn0][tkn1];

    if (openOnMangrove && position == 0) {
      _openMarkets.push([tkn0, tkn1]);
      marketPositions[tkn0][tkn1] = _openMarkets.length;
    } else if (!openOnMangrove && position > 0) {
      uint numMarkets = _openMarkets.length;
      if (numMarkets > 1) {
        // avoid array holes
        address[2] memory lastMarket = _openMarkets[numMarkets - 1];

        _openMarkets[position - 1] = lastMarket;
        marketPositions[lastMarket[0]][lastMarket[1]] = position;
      }
      _openMarkets.pop();
      marketPositions[tkn0][tkn1] = 0;
    }
  }
}
