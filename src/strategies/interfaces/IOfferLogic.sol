// SPDX-License-Identifier:	BSD-2-Clause

// IOfferLogic.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity >=0.8.0;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20, IMaker} from "mgv_src/MgvLib.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";

///@title IOfferLogic interface for offer management
///@notice It is an IMaker for Mangrove.

interface IOfferLogic is IMaker {
  ///@notice Log incident (during post trade execution)
  event LogIncident(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 makerData,
    bytes32 mgvData
  );

  ///@notice Logging change of router address
  event SetRouter(AbstractRouter);

  ///@notice Actual gas requirement when posting offers via this strategy. Returned value may change if this contract's router is updated.
  ///@return total gas cost including router specific costs (if any).
  function offerGasreq() external view returns (uint total);

  ///@notice Computes missing provision to repost `offerId` at given `gasreq` and `gasprice` ignoring current contract's balance on Mangrove.
  ///@param outbound_tkn the outbound token used to identify the order book
  ///@param inbound_tkn the inbound token used to identify the order book
  ///@param gasreq the gas required by the offer. Give > type(uint24).max to use `this.offerGasreq()`
  ///@param gasprice the upper bound on gas price. Give 0 to use Mangrove's gasprice
  ///@param offerId the offer id. Set this to 0 if one is not reposting an offer
  ///@dev if `offerId` is not in the Order Book, will simply return how much is needed to post
  ///@return missingProvision to repost `offerId`.
  function getMissingProvision(IERC20 outbound_tkn, IERC20 inbound_tkn, uint gasreq, uint gasprice, uint offerId)
    external
    view
    returns (uint missingProvision);

  ///@notice sets a new router to pull outbound tokens from contract's reserve to `this` and push inbound tokens to reserve.
  ///@param router_ the new router contract that this contract should use. Use `NO_ROUTER` for no router.
  ///@dev new router needs to be approved by `this` to push funds to reserve (see `activate` function). It also needs to be approved by reserve to pull from it.
  function setRouter(AbstractRouter router_) external;

  ///@notice Approves a spender to transfer a certain amount of tokens on behalf of `this`.
  ///@param token the ERC20 token contract
  ///@param spender the approved spender
  ///@param amount the spending amount
  ///@dev admin may use this function to revoke specific approvals of `this` that are set after a call to `activate`.
  function approve(IERC20 token, address spender, uint amount) external returns (bool);

  ///@notice computes the amount of native tokens that can be redeemed when deprovisioning a given offer.
  ///@param outbound_tkn the outbound token of the offer list
  ///@param inbound_tkn the inbound token of the offer list
  ///@param offerId the identifier of the offer in the offer list
  ///@return provision the amount of native tokens that can be redeemed when deprovisioning the offer
  function provisionOf(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId) external view returns (uint provision);

  ///@notice verifies that this contract's current state is ready to be used by `msg.sender` to post offers on Mangrove
  ///@dev throws with a reason if something (e.g. an approval) is missing.
  function checkList(IERC20[] calldata tokens) external view;

  /// @notice performs the required approvals so as to allow `this` to interact with Mangrove on a set of assets.
  /// @param tokens the ERC20 `this` will approve to be able to trade on Mangrove's corresponding markets.
  function activate(IERC20[] calldata tokens) external;

  ///@notice withdraws native tokens from `this` balance on Mangrove.
  ///@param amount the amount of WEI one wishes to withdraw.
  ///@param receiver the address of the receiver of the funds.
  ///@dev Since a call is made to the `receiver`, this function is subject to reentrancy.
  function withdrawFromMangrove(uint amount, address payable receiver) external;

  ///@notice Memory allocation for `_new/updateOffer`'s arguments.
  ///@param outbound_tkn outbound token of the offer list.
  ///@param inbound_tkn inbound token of the offer list.
  ///@param wants the amount of inbound tokens the maker wants for a complete fill.
  ///@param gives the amount of outbound tokens the maker gives for a complete fill.
  ///@param gasreq the amount of gas units that are required to execute the trade (use type(uint).max for using `this.offerGasReq()`)
  ///@param gasprice the gasprice used to compute offer's provision (use 0 to use Mangrove's gasprice)
  ///@param pivotId a best pivot estimate for cheap offer insertion in the offer list.
  ///@param fund WEIs in `this` contract's balance that are used to provision the offer.
  ///@param noRevert is set to true if calling function does not wish `_newOffer` to revert on error.
  ///@param owner the offer maker managing the offer.
  ///@dev `owner` is required in `Forwarder` logics, when `_newOffer` or `_updateOffer` in called in a hook (`msg.sender==MGV`).
  struct OfferArgs {
    IERC20 outbound_tkn;
    IERC20 inbound_tkn;
    uint wants;
    uint gives;
    uint gasreq;
    uint gasprice;
    uint pivotId;
    uint fund;
    bool noRevert;
    address owner;
  }

  ///@notice Retracts an offer from an Offer List of Mangrove.
  ///@param outbound_tkn the outbound token of the offer list.
  ///@param inbound_tkn the inbound token of the offer list.
  ///@param offerId the identifier of the offer in the (`outbound_tkn`,`inbound_tkn`) offer list
  ///@param deprovision positioned if `msg.sender` wishes to redeem the offer's provision.
  ///@return received the amount of native tokens (in WEI) that have been retrieved by retracting the offer.
  ///@dev An offer that is retracted without `deprovision` is retracted from the offer list, but still has its provisions locked by Mangrove.
  ///@dev Calling this function, with the `deprovision` flag, on an offer that is already retracted must be used to retrieve the locked provisions.
  function retractOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` will receive the remaining provision (in WEI) associated to `offerId`.
  ) external returns (uint received);

  /// @notice getter of the reserve address of `maker`.
  /// @param maker the address of the offer maker one wishes to know the reserve of.
  /// @return reserve_ the address of the offer maker's reserve of liquidity.
  /// @dev if no reserve is set for maker, default reserve is maker's address. Thus this function never returns `address(0)`.
  function reserve(address maker) external view returns (address);

  /// @notice Contract's router getter.
  /// @dev if contract has a no router, function returns `NO_ROUTER`.
  function router() external view returns (AbstractRouter);
}
