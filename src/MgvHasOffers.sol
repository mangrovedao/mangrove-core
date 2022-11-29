// SPDX-License-Identifier:	AGPL-3.0

// MgvHasOffers.sol

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

import {MgvLib, HasMgvEvents, IMgvMonitor, MgvStructs} from "./MgvLib.sol";
import {MgvRoot} from "./MgvRoot.sol";

/* `MgvHasOffers` contains the state variables and functions common to both market-maker operations and market-taker operations. Mostly: storing offers, removing them, updating market makers' provisions. */
contract MgvHasOffers is MgvRoot {
  /* # State variables */
  /* Given a `outbound_tkn`,`inbound_tkn` pair, the mappings `offers` and `offerDetails` associate two 256 bits words to each offer id. Those words encode information detailed in [`structs.js`](#structs.js).

     The mappings are `outbound_tkn => inbound_tkn => offerId => MgvStructs.OfferPacked|MgvStructs.OfferDetailPacked`.
   */
  mapping(address => mapping(address => mapping(uint => MgvStructs.OfferPacked))) public offers;
  mapping(address => mapping(address => mapping(uint => MgvStructs.OfferDetailPacked))) public offerDetails;

  /* Makers provision their possible penalties in the `balanceOf` mapping.

       Offers specify the amount of gas they require for successful execution ([`gasreq`](#structs.js/gasreq)). To minimize book spamming, market makers must provision a *penalty*, which depends on their `gasreq` and on the pair's [`offer_gasbase`](#structs.js/gasbase). This provision is deducted from their `balanceOf`. If an offer fails, part of that provision is given to the taker, as retribution. The exact amount depends on the gas used by the offer before failing.

       The Mangrove keeps track of their available balance in the `balanceOf` map, which is decremented every time a maker creates a new offer, and may be modified on offer updates/cancellations/takings.
     */
  mapping(address => uint) public balanceOf;

  /* # Read functions */
  /* Convenience function to get best offer of the given pair */
  function best(address outbound_tkn, address inbound_tkn) external view returns (uint) {
    unchecked {
      MgvStructs.LocalPacked local = locals[outbound_tkn][inbound_tkn];
      return local.best();
    }
  }

  /* Returns information about an offer in ABI-compatible structs. Do not use internally, would be a huge memory-copying waste. Use `offers[outbound_tkn][inbound_tkn]` and `offerDetails[outbound_tkn][inbound_tkn]` instead. */
  function offerInfo(address outbound_tkn, address inbound_tkn, uint offerId)
    external
    view
    returns (MgvStructs.OfferUnpacked memory offer, MgvStructs.OfferDetailUnpacked memory offerDetail)
  {
    unchecked {
      MgvStructs.OfferPacked _offer = offers[outbound_tkn][inbound_tkn][offerId];
      offer = _offer.to_struct();

      MgvStructs.OfferDetailPacked _offerDetail = offerDetails[outbound_tkn][inbound_tkn][offerId];
      offerDetail = _offerDetail.to_struct();
    }
  }

  /* # Provision debit/credit utility functions */
  /* `balanceOf` is in wei of ETH. */

  function debitWei(address maker, uint amount) internal {
    unchecked {
      uint makerBalance = balanceOf[maker];
      require(makerBalance >= amount, "mgv/insufficientProvision");
      balanceOf[maker] = makerBalance - amount;
      emit Debit(maker, amount);
    }
  }

  function creditWei(address maker, uint amount) internal {
    unchecked {
      balanceOf[maker] += amount;
      emit Credit(maker, amount);
    }
  }

  /* # Misc. low-level functions */
  /* ## Offer deletion */

  /* When an offer is deleted, it is marked as such by setting `gives` to 0. Note that provision accounting in Mangrove aims to minimize writes. Each maker `fund`s Mangrove to increase its balance. When an offer is created/updated, we compute how much should be reserved to pay for possible penalties. That amount can always be recomputed with `offerDetail.gasprice * (offerDetail.gasreq + offerDetail.offer_gasbase)`. The balance is updated to reflect the remaining available ethers.

     Now, when an offer is deleted, the offer can stay provisioned, or be `deprovision`ed. In the latter case, we set `gasprice` to 0, which induces a provision of 0. All code calling `dirtyDeleteOffer` with `deprovision` set to `true` must be careful to correctly account for where that provision is going (back to the maker's `balanceOf`, or sent to a taker as compensation). */
  function dirtyDeleteOffer(
    mapping(uint => MgvStructs.OfferPacked) storage semibook,
    mapping(uint => MgvStructs.OfferDetailPacked) storage semibookDetails,
    uint offerId,
    MgvStructs.OfferPacked offer,
    MgvStructs.OfferDetailPacked offerDetail,
    bool deprovision
  ) internal {
    unchecked {
      offer = offer.gives(0);
      if (deprovision) {
        offerDetail = offerDetail.gasprice(0);
      }
      semibook[offerId] = offer;
      semibookDetails[offerId] = offerDetail;
    }
  }

  /* ## Stitching the orderbook */

  /* Connect the offers `betterId` and `worseId` through their `next`/`prev` pointers. For more on the book structure, see [`structs.js`](#structs.js). Used after executing an offer (or a segment of offers), after removing an offer, or moving an offer.

  **Warning**: calling with `betterId = 0` will set `worseId` as the best. So with `betterId = 0` and `worseId = 0`, it sets the book to empty and loses track of existing offers.

  **Warning**: may make memory copy of `local.best` stale. Returns new `local`. */
  function stitchOffers(
    mapping(uint => MgvStructs.OfferPacked) storage semibook,
    uint betterId,
    uint worseId,
    MgvStructs.LocalPacked local
  ) internal returns (MgvStructs.LocalPacked) {
    unchecked {
      if (betterId != 0) {
        semibook[betterId] = semibook[betterId].next(worseId);
      } else {
        local = local.best(worseId);
      }

      if (worseId != 0) {
        semibook[worseId] = semibook[worseId].prev(betterId);
      }

      return local;
    }
  }

  /* ## Check offer is live */
  /* Check whether an offer is 'live', that is: inserted in the order book. The Mangrove holds a `outbound_tkn => inbound_tkn => id => MgvStructs.OfferPacked` mapping in storage. Offer ids that are not yet assigned or that point to since-deleted offer will point to an offer with `gives` field at 0. */
  function isLive(MgvStructs.OfferPacked offer) public pure returns (bool) {
    unchecked {
      return offer.gives() > 0;
    }
  }

  /* ## Pointers to partially evaluated mappings
    Reminder: deep mappings are accessed by composing the hash of each successive key. For the mapping at `map` at slot `slot`, `map[key1][key2]` points to keccak256(bytes.concat(key2, keccak256(bytes.concat(key1, uint(slot))))).

    To save gas, we save the partial evaluation of offerDetail and offer when it makes sense. Since memory structs cannot contain storage mappings, we convert to/from bytes32.
  */

  /* Return the storage pointer given by a partially evaluated mapping (`Offer` or `OfferDetail`), cast to a bytes32 */
  function tob32(mapping(uint => MgvStructs.OfferPacked) storage sb) internal pure returns (bytes32 val) {
    /// @solidity memory-safe-assembly
    assembly {
      val := sb.slot
    }
  }

  function tob32(mapping(uint => MgvStructs.OfferDetailPacked) storage sbd) internal pure returns (bytes32 val) {
    /// @solidity memory-safe-assembly
    assembly {
      val := sbd.slot
    }
  }

  /* Return given bytes32 cat to a partially evaluated mapping (`Offer` or `OfferDetail`) */
  function toSemibook(bytes32 val) internal pure returns (mapping(uint => MgvStructs.OfferPacked) storage sb) {
    /// @solidity memory-safe-assembly
    assembly {
      sb.slot := val
    }
  }

  function toSemibookDetails(bytes32 val)
    internal
    pure
    returns (mapping(uint => MgvStructs.OfferDetailPacked) storage sbd)
  {
    /// @solidity memory-safe-assembly
    assembly {
      sbd.slot := val
    }
  }
}
