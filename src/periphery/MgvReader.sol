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

pragma abicoder v2;

import {MgvLib, MgvStructs} from "src/MgvLib.sol";
import {IMangrove} from "src/IMangrove.sol";

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

  function getProvision(address outbound_tkn, address inbound_tkn, uint ofr_gasreq, uint ofr_gasprice)
    external
    view
    returns (uint)
  {
    unchecked {
      (MgvStructs.GlobalPacked global, MgvStructs.LocalPacked local) = MGV.config(outbound_tkn, inbound_tkn);
      uint gp;
      uint global_gasprice = global.gasprice();
      if (global_gasprice > ofr_gasprice) {
        gp = global_gasprice;
      } else {
        gp = ofr_gasprice;
      }
      return (ofr_gasreq + local.offer_gasbase()) * gp * 10 ** 9;
    }
  }

  /* marketOrder, internalMarketOrder, and execute all together simulate a market order on mangrove and return the cumulative totalGot, totalGave and totalGasreq for each offer traversed. We assume offer execution is successful and uses exactly its gasreq. 
  We do not account for gasbase.
  * Calling this from an EOA will give you an estimate of the volumes you will receive, but you may as well `eth_call` Mangrove.
  * Calling this from a contract will let the contract choose what to do after receiving a response.
  */
  function marketOrder(address outbound_tkn, address inbound_tkn, uint takerWants, uint takerGives, bool fillWants)
    external
    view
    returns (VolumeData[] memory)
  {
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

    internalMarketOrder(mr, true);

    return mr.volumeData;
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

        if (executed) {
          uint concreteFee = (mr.totalGot * mr.local.fee()) / 10_000;
          mr.volumeData[currentIndex] =
            VolumeData({totalGot: totalGot - concreteFee, totalGave: totalGave, totalGasreq: totalGasreq});
        }
      } else {
        mr.volumeData = new VolumeData[](mr.numOffers);
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
}
