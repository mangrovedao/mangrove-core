// SPDX-License-Identifier:	BSD-2-Clause

// TradeHandler.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.7.0;
pragma abicoder v2;

import {MgvPack as MP} from "../../MgvPack.sol";
import "../../Mangrove.sol";
import "../../MgvLib.sol";

import "hardhat/console.sol";

contract TradeHandler {
  // internal bytes32 to select appropriate posthook
  bytes32 constant RENEGED = "mgvOffer/reneged";
  bytes32 constant OUTOFLIQUIDITY = "mgvOffer/outOfLiquidity";

  // to wrap potentially reverting calls to mangrove
  event PosthookFail(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint offerId,
    string message
  );

  event NotEnoughLiquidity(address token, uint amountMissing);
  event PostHookError(address outbound_tkn, address inbound_tkn, uint offerId);

  /// @notice extracts old offer from the order that is received from the Mangrove
  function unpackOfferFromOrder(MgvLib.SingleOrder calldata order)
    internal
    pure
    returns (
      uint offer_wants,
      uint offer_gives,
      uint gasreq,
      uint gasprice
    )
  {
    gasreq = MP.offerDetail_unpack_gasreq(order.offerDetail);
    (, , offer_wants, offer_gives, gasprice) = MP.offer_unpack(order.offer);
  }

  function getMissingProvision(
    Mangrove mgv,
    address outbound_tkn,
    address inbound_tkn,
    uint gasreq,
    uint gasprice,
    uint offerId
  ) internal view returns (uint) {
    (bytes32 globalData, bytes32 localData) = mgv.config(
      outbound_tkn,
      inbound_tkn
    );
    bytes32 offerData = mgv.offers(outbound_tkn, inbound_tkn, offerId);
    bytes32 offerDetailData = mgv.offerDetails(
      outbound_tkn,
      inbound_tkn,
      offerId
    );
    uint _gp;
    if (MP.global_unpack_gasprice(globalData) > gasprice) {
      _gp = MP.global_unpack_gasprice(globalData);
    } else {
      _gp = gasprice;
    }
    uint bounty = (gasreq +
      MP.local_unpack_overhead_gasbase(localData) +
      MP.local_unpack_offer_gasbase(localData)) *
      _gp *
      10**9; // in WEI
    uint currentProvisionLocked = (MP.offerDetail_unpack_gasreq(
      offerDetailData
    ) +
      MP.offerDetail_unpack_overhead_gasbase(offerDetailData) +
      MP.offerDetail_unpack_offer_gasbase(offerDetailData)) *
      MP.offer_unpack_gasprice(offerData) *
      10**9;
    uint currentProvision = currentProvisionLocked +
      mgv.balanceOf(address(this));
    return (currentProvision >= bounty ? 0 : bounty - currentProvision);
  }

  //queries the mangrove to get current gasprice (considered to compute bounty)
  function getCurrentGasPrice(Mangrove mgv) internal view returns (uint) {
    (bytes32 global_pack, ) = mgv.config(address(0), address(0));
    return MP.global_unpack_gasprice(global_pack);
  }

  //truncate some bytes into a byte32 word
  function truncateBytes(bytes memory data) internal pure returns (bytes32 w) {
    assembly {
      w := mload(add(data, 32))
    }
  }

  function bytesOfWord(bytes32 w) internal pure returns (bytes memory) {
    bytes memory b = new bytes(32);
    assembly {
      mstore(add(b, 32), w)
    }
    return b;
  }
}
