// SPDX-License-Identifier:	AGPL-3.0

// MgvReader.sol

// Copyright (C) 2021 Giry SAS.
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
pragma solidity ^0.7.6;
pragma abicoder v2;
import {MgvLib as ML} from "../MgvLib.sol";
import {MgvPack as MP} from "../MgvPack.sol";

interface MangroveLike {
  function best(address, address) external view returns (uint);

  function offers(
    address,
    address,
    uint
  ) external view returns (bytes32);

  function offerDetails(
    address,
    address,
    uint
  ) external view returns (bytes32);

  function offerInfo(
    address,
    address,
    uint
  ) external view returns (ML.Offer memory, ML.OfferDetail memory);

  function config(address, address) external view returns (bytes32, bytes32);
}

contract MgvReader {
  MangroveLike immutable mgv;

  constructor(address _mgv) {
    mgv = MangroveLike(payable(_mgv));
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
  function offerListEndPoints(
    address outbound_tkn,
    address inbound_tkn,
    uint fromId,
    uint maxOffers
  ) public view returns (uint startId, uint length) {
    if (fromId == 0) {
      startId = mgv.best(outbound_tkn, inbound_tkn);
    } else {
      startId = MP.offer_unpack_gives(
        mgv.offers(outbound_tkn, inbound_tkn, fromId)
      ) > 0
        ? fromId
        : 0;
    }

    uint currentId = startId;

    while (currentId != 0 && length < maxOffers) {
      currentId = MP.offer_unpack_next(
        mgv.offers(outbound_tkn, inbound_tkn, currentId)
      );
      length = length + 1;
    }

    return (startId, length);
  }

  // Returns the orderbook for the outbound_tkn/inbound_tkn pair in packed form. First number is id of next offer (0 is we're done). First array is ids, second is offers (as bytes32), third is offerDetails (as bytes32). Array will be of size `min(# of offers in out/in list, maxOffers)`.
  function packedOfferList(
    address outbound_tkn,
    address inbound_tkn,
    uint fromId,
    uint maxOffers
  )
    public
    view
    returns (
      uint,
      uint[] memory,
      bytes32[] memory,
      bytes32[] memory
    )
  {
    (uint currentId, uint length) = offerListEndPoints(
      outbound_tkn,
      inbound_tkn,
      fromId,
      maxOffers
    );

    uint[] memory offerIds = new uint[](length);
    bytes32[] memory offers = new bytes32[](length);
    bytes32[] memory details = new bytes32[](length);

    uint i = 0;

    while (currentId != 0 && i < length) {
      offerIds[i] = currentId;
      offers[i] = mgv.offers(outbound_tkn, inbound_tkn, currentId);
      details[i] = mgv.offerDetails(outbound_tkn, inbound_tkn, currentId);
      currentId = MP.offer_unpack_next(offers[i]);
      i = i + 1;
    }

    return (currentId, offerIds, offers, details);
  }

  // Returns the orderbook for the outbound_tkn/inbound_tkn pair in unpacked form. First number is id of next offer (0 if we're done). First array is ids, second is offers (as structs), third is offerDetails (as structs). Array will be of size `min(# of offers in out/in list, maxOffers)`.
  function offerList(
    address outbound_tkn,
    address inbound_tkn,
    uint fromId,
    uint maxOffers
  )
    public
    view
    returns (
      uint,
      uint[] memory,
      ML.Offer[] memory,
      ML.OfferDetail[] memory
    )
  {
    (uint currentId, uint length) = offerListEndPoints(
      outbound_tkn,
      inbound_tkn,
      fromId,
      maxOffers
    );

    uint[] memory offerIds = new uint[](length);
    ML.Offer[] memory offers = new ML.Offer[](length);
    ML.OfferDetail[] memory details = new ML.OfferDetail[](length);

    uint i = 0;
    while (currentId != 0 && i < length) {
      offerIds[i] = currentId;
      (offers[i], details[i]) = mgv.offerInfo(
        outbound_tkn,
        inbound_tkn,
        currentId
      );
      currentId = offers[i].next;
      i = i + 1;
    }

    return (currentId, offerIds, offers, details);
  }

  function getProvision(
    address outbound_tkn,
    address inbound_tkn,
    uint ofr_gasreq,
    uint ofr_gasprice
  ) external view returns (uint) {
    (bytes32 global, bytes32 local) = mgv.config(outbound_tkn, inbound_tkn);
    uint _gp;
    uint global_gasprice = MP.global_unpack_gasprice(global);
    if (global_gasprice > ofr_gasprice) {
      _gp = global_gasprice;
    } else {
      _gp = ofr_gasprice;
    }
    return
      (ofr_gasreq +
        MP.local_unpack_overhead_gasbase(local) +
        MP.local_unpack_offer_gasbase(local)) *
      _gp *
      10**9;
  }

  /* Returns the configuration in an ABI-compatible struct. Should not be called internally, would be a huge memory copying waste. Use `config` instead. */
  function config(address outbound_tkn, address inbound_tkn)
    external
    view
    returns (ML.Global memory global, ML.Local memory local)
  {
    (bytes32 _global, bytes32 _local) = mgv.config(outbound_tkn, inbound_tkn);
    return (
      ML.Global({
        monitor: $$(global_monitor("_global")),
        useOracle: $$(global_useOracle("_global")) > 0,
        notify: $$(global_notify("_global")) > 0,
        gasprice: $$(global_gasprice("_global")),
        gasmax: $$(global_gasmax("_global")),
        dead: $$(global_dead("_global")) > 0
      }),
      ML.Local({
        active: $$(local_active("_local")) > 0,
        overhead_gasbase: $$(local_overhead_gasbase("_local")),
        offer_gasbase: $$(local_offer_gasbase("_local")),
        fee: $$(local_fee("_local")),
        density: $$(local_density("_local")),
        best: $$(local_best("_local")),
        lock: $$(local_lock("_local")) > 0,
        last: $$(local_last("_local"))
      })
    );
  }
}
