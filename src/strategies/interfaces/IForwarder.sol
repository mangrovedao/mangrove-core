// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity >=0.8.10;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

///@title IForwarder
///@notice Interface for contracts that manage liquidity on Mangrove on behalf of multiple offer makers
interface IForwarder {
  ///@notice Logging new offer owner
  ///@param mangrove Mangrove contract on which the offer is posted
  ///@param outbound_tkn the outbound token of the offer list.
  ///@param inbound_tkn the inbound token of the offer list.
  ///@param offerId the Mangrove offer id.
  ///@param owner the offer maker that can manage the offer.
  event NewOwnedOffer(
    IMangrove mangrove, IERC20 indexed outbound_tkn, IERC20 indexed inbound_tkn, uint indexed offerId, address owner
  );

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
