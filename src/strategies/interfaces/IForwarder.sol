// SPDX-License-Identifier:	BSD-2-Clause

// IForwarder.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity >=0.7.0;

pragma abicoder v2;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

///@title IForwarder
///@notice Interface for contracts that manage liquidity on Mangrove on behalf of multiple offer makers
interface IForwarder {
  ///@notice Logging new offer owner
  ///@param mangrove Mangrove contract on which the offer is posted
  ///@param outbound_tkn the outbound token of the offer list.
  ///@param inbound_tkn the inbound token of the offer list.
  ///@param owner the offer maker that can manage the offer.
  event NewOwnedOffer(
    IMangrove mangrove, IERC20 indexed outbound_tkn, IERC20 indexed inbound_tkn, uint indexed offerId, address owner
  );

  ///@notice Logging reserve approval
  event ReserveApproval(address indexed reserve_, address indexed maker, bool isApproved);

  ///@notice view for reserve approvals
  function reserveApprovals(address reserve_, address maker) external view returns (bool);

  ///@notice reserve (who must be `msg.sender`) approves `maker` for pooling.
  function approvePooledMaker(address maker) external;

  ///@notice reserve (who must be `msg.sender`) revokes `maker` from its approved poolers.
  function revokePooledMaker(address maker) external;

  /// @notice view on offer owners.
  /// @param outbound_tkn the outbound token of the offer list.
  /// @param inbound_tkn the inbound token of the offer list.
  /// @param offerIds an array of offer identifiers on the offer list.
  /// @return offer_owners an array of the same length where the address at position i is the owner of `offerIds[i]`
  /// @dev if `offerIds[i]==address(0)` if and only if this offer has no owner.
  function offerOwners(IERC20 outbound_tkn, IERC20 inbound_tkn, uint[] calldata offerIds)
    external
    view
    returns (address[] memory offer_owners);

  /// @notice view on an offer owner.
  /// @param outbound_tkn the outbound token of the offer list.
  /// @param inbound_tkn the inbound token of the offer list.
  /// @param offerId the offer identifier on the offer list.
  /// @return owner the offer maker that can manage the offer.
  /// @dev `ownerOf(in,out,id)` is equivalent to `offerOwners(in, out, [id])` but more gas efficient.
  function ownerOf(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId) external view returns (address owner);
}
