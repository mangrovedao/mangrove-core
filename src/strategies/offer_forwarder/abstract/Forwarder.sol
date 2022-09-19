// SPDX-License-Identifier:	BSD-2-Clause

// Forwarder.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import { MangroveOffer } from "../../MangroveOffer.sol";
import "mgv_src/strategies/interfaces/IForwarder.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import "mgv_src/strategies/interfaces/IOfferLogic.sol";
import "mgv_src/preprocessed/MgvPack.post.sol" as MgvPack;
import "mgv_src/MgvLib.sol";

///@title Class for maker contracts that forward external offer makers instructions to Mangrove in a permissionless fashion.
///@notice Each offer posted via this contract are managed by their offer maker, not by this contract's admin.
///@notice This class implements IForwarder, which contains specific Forwarder logic functions in additions to IOfferlogic interface.
abstract contract Forwarder is IForwarder, MangroveOffer {
  ///@notice data associated to each offer published on Mangrove by `this` contract.
  struct OwnerData {
    // offer owner address
    address owner;
    // under approx of the portion of this contract's balance on mangrove
    // that can be returned to the user's reserve when this offer is deprovisioned
    uint96 wei_balance;
  }

  ///@notice Owner data mapping.
  ///@dev outbound_tkn => inbound_tkn => offerId => OwnerData
  mapping(IERC20 => mapping(IERC20 => mapping(uint => OwnerData)))
    internal ownerData;

  ///@notice Forwarder constructor
  ///@param mgv the deployed Mangrove contract on which `this` contract will post offers.
  ///@param router_ the router that `this` contract will use to pull/push liquidity from offer maker's reserve. This cannot be `NO_ROUTER`. 
  constructor(
    IMangrove mgv,
    AbstractRouter router_
  ) MangroveOffer(mgv) {
    require (router_ != NO_ROUTER, "Forwarder logics must have a router");
    setRouter(router_);
  }

  ///@inheritdoc IForwarder
  function offerOwners(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint[] calldata offerIds
  ) public view override returns (address[] memory offerOwners_) {
    offerOwners_ = new address[](offerIds.length);
    for (uint i = 0; i < offerIds.length; i++) {
      offerOwners_[i] = ownerOf(outbound_tkn, inbound_tkn, offerIds[i]);
    }
  }

  /// @notice grants managing rights on a particular offer.
  /// @param outbound_tkn the outbound token of the offer list.
  /// @param inbound_tkn the inbound token of the offer list.
  /// @param offerId the offer identifier in the offer list.
  /// @param owner the address of the offer maker who will have ownership over the offer.
  function addOwner(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId,
    address owner
  ) internal {
    ownerData[outbound_tkn][inbound_tkn][offerId] = OwnerData({
      owner: owner,
      wei_balance: uint96(0)
    });
    emit NewOwnedOffer(MGV, outbound_tkn, inbound_tkn, offerId, owner);
  }

  /// @notice computes the `gasprice` that is covered by the provision given in argument.
  /// @param gasreq the gas required by the offer
  /// @param provision the amount of native token one is using to provision the offer
  /// @return gasprice the gas price that is covered by `provision`.
  /// @dev the returned gasprice is slightly lower than the real gasprice that the provision can cover because of the rounding error due to division
  function deriveGasprice(
    uint gasreq,
    uint provision,
    uint offer_gasbase
  ) internal pure returns (uint gasprice) {
    unchecked {
      uint num = (offer_gasbase + gasreq) * 10**9;
      // pre-check to avoir underflow since 0 is interpreted as "use mangrove's gasprice"
      require(provision >= num, "mgv/insufficientProvision");
      gasprice = provision / num;
      // leftover is provision - num;
    }
  }

  ///@inheritdoc IForwarder
  function ownerOf(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId
  ) public view override returns (address owner) {
    owner = ownerData[outbound_tkn][inbound_tkn][offerId].owner;
    require(owner != address(0), "multiUser/unknownOffer");
  }

  ///@inheritdoc IOfferLogic
  function reserve() public view override returns (address) {
    address mkr_reserve = _reserve(msg.sender);
    return mkr_reserve == address(0) ? msg.sender : mkr_reserve;
  }

  ///@inheritdoc IOfferLogic
  function setReserve(address reserve_) external override {
    _setReserve(msg.sender, reserve_);
  }

  ///@notice Memory allocation of `_newOffer` variables
  ///@param outbound_tkn token contract 
  ///@param inbound_tkn token contract
  ///@param wants the amount of inbound tokens the maker wants for a complete fill
  ///@param gives the amount of outbound tokens the maker gives for a complete fill
  ///@param pivotId a best pivot estimate for cheap offer insertion in the offer list
  ///@param caller msg.sender of the calling external function
  ///@param fund remainder of msg.value as received by the external function
  ///@param noRevert is set to true if calling function does not wish `_newOffer` to revert on error. Out of gas exception is always possible though.
  struct NewOfferData {
    IERC20 outbound_tkn; 
    IERC20 inbound_tkn;
    uint wants;
    uint gives;
    uint gasreq;
    uint pivotId;
    address caller;
    uint fund;
    bool noRevert;
  }

  /// @notice Inserts a new offer on a Mangrove Offer List. Should be called by any desendant of `Forwarder` wishing to post a new offer.
  /// @param offData memory location of the function's arguments
  /// @return offerId
  /// @dev offer forwarders do not manage user funds on Mangrove, as a consequence:
  /// An offer maker's recoverable provisions on Mangrove is just the sum $S_locked(maker)$ of locked provision in all live offers it owns 
  /// plus the sum $S_free(maker)$ of `wei_balance`'s in all dead offers it owns (see `OwnerData.wei_balance`). 
  /// Notice that $S_locked(maker)$ is not part of `this` contract's balance on Mangrove.
  /// However $\sum_i S_free(maker_i)$ <= MGV.balanceOf(address(this))`. 
  /// Any fund of an offer maker on Mangrove that is either not locked on Mangrove or stored in the `OwnerData` free wei's is thus not recoverable by offer maker.
  /// Therefore we need to make sure that all `msg.value` is captured by the `gasprice` at which the offer will be posted.
  /// To do so, we do not let offer maker fix a gasprice. Rather we derive the gasprice based on `msg.value`.
  /// Because of rounding errors in `deriveGasprice` a small amount of WEIs will accumulate in mangrove's balance of `this` contract
  /// We could assign this dust to the corresponding `wei_balance` of `OwnerData` but this would entail a storage write whose gas cost would exceed the saved dust.
  /// Note that this dust is not burnt, as it can be retrieved by this contract's admin via `withdrawFromMangrove`.
  function _newOffer(
    NewOfferData memory offData
  ) internal returns (uint offerId) {
    (MgvPack.Global.t global, MgvPack.Local.t local) = MGV.config(
      address(offData.outbound_tkn),
      address(offData.inbound_tkn)
    );
    // convention for default gasreq value
    offData.gasreq = (offData.gasreq > type(uint24).max) ? offerGasreq() : offData.gasreq;
    // computing gasprice implied by offer provision
    uint gasprice = deriveGasprice(
      offData.gasreq,
      offData.fund,
      local.offer_gasbase()
    );
    // mangrove will take max(`mko.gasprice`, `global.gasprice`)
    // if `mko.gasprice < global.gasprice` Mangrove will use available provision of this contract to provision the offer
    // this would potentially take native tokens that have been released after some offer managed by this contract have failed
    // so one needs to make sure here that only provision of this call will be used to provision the offer on mangrove
    require(
      gasprice >= global.gasprice(),
      "mgv/insufficientProvision"
    );
    // this call cannot revert for lack of provision (by design)
    // it may revert if `offData.fund` yields a gasprice that is too high (mangrove's gasprice is uint16)
    // or if `offData.gives` is below density (dust)
    try MGV.newOffer{value: offData.fund}(
      address(offData.outbound_tkn),
      address(offData.inbound_tkn),
      offData.wants,
      offData.gives,
      offData.gasreq,
      gasprice,
      offData.pivotId
    ) returns (uint offerId_) {
      // assign `offerId_` to caller
      addOwner(offData.outbound_tkn, offData.inbound_tkn, offerId_, offData.caller); 
      offerId = offerId_;
    } catch Error(string memory reason){
      /// letting revert bubble up unless `noRevert` is positioned.
      require (offData.noRevert, reason);
      offerId = 0;
    }
  }

  struct UpdateOfferData {
    MgvPack.Global.t global;
    MgvPack.Local.t local;
    MgvPack.OfferDetail.t offer_detail;
    uint fund;
    IERC20 outbound_tkn;
    IERC20 inbound_tkn;
    uint wants;
    uint gives;
    uint gasreq;
    uint gasprice;
    uint pivotId;
    uint offerId;
    uint wei_balance;
    address owner;
  }

  ///@notice updates an offer existing on Mangrove (not necessarily live).
  ///@dev gasreq == max_int indicates one wishes to use ofr_gasreq (default value)
  ///@dev gasprice is overridden by the value computed by taking into account :
  /// * value transferred on current tx
  /// * if offer was deprovisioned after a fail, amount of wei (still on this contract balance on Mangrove) that should be counted as offer owner's
  /// * if offer is still live, its current locked provision
  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice, // value ignored but kept to maintain compatibility with `Direct` offers
    uint pivotId,
    uint offerId
    ) external payable override {
    OwnerData memory od = ownerData[outbound_tkn][inbound_tkn][
      offerId
    ];
    require(
      msg.sender == od.owner,
      "Multi/updateOffer/unauthorized"
    );
    gasprice; // ssh
    UpdateOfferData memory upd; 
    // upd.gasprice is deliberately left at 0
    upd.offer_detail = MGV.offerDetails(
      address(outbound_tkn),
      address(inbound_tkn),
      offerId
    );
    (upd.global, upd.local) = MGV.config(
      address(outbound_tkn),
      address(inbound_tkn)
    );
    upd.fund = msg.value;
    upd.outbound_tkn = outbound_tkn;
    upd.inbound_tkn = inbound_tkn;
    upd.wants = wants;
    upd.gives = gives;
    upd.gasreq = gasreq > type(uint24).max ? offerGasreq() : gasreq;
    upd.pivotId = pivotId;
    upd.offerId = offerId;
    upd.owner = msg.sender;

    // if `wei_balance` > 0 then `this` contract has a balance on Mangrove >= `wei_balance`.
    upd.wei_balance = od.wei_balance;
    _updateOffer(upd);
  }

  // upd.gasprice is kept to 0 because it will be derived from `msg.value` 
  // not doing this would allow a user to submit an `new/updateOffer` underprovisioned for the announced gasprice
  // Mangrove would then erroneously take missing WEIs in `this` contract free balance (possibly coming from uncollected deprovisioned offers after a fail).
  // need to treat 2 cases:
  // * if offer is deprovisioned one needs to use msg.value and `ownerData.wei_balance` to derive gasprice (deprovisioning sets offer.gasprice to 0)
  // * if offer is still live one should compute its currently locked provision $MgvPack$ and derive gasprice based on msg.value + $MgvPack$ (note if msg.value = 0 offer can be reposted with offer.gasprice)

  function _updateOffer(UpdateOfferData memory upd)
    private
  { 
    // storing current offer gasprice into `upd` struct
    upd.gasprice = upd.offer_detail.gasprice();
    if (upd.gasprice == 0) {
      // offer was previously deprovisioned, we add the portion of this contract WEI pool on Mangrove that belongs to this offer (if any)
      if (upd.wei_balance > 0) {
        upd.fund += upd.wei_balance;
        ownerData[upd.outbound_tkn][upd.inbound_tkn][upd.offerId] = OwnerData({
          owner: upd.owner,
          wei_balance: 0
        });
      }
      // gasprice for this offer will be computed using msg.value and available funds on Mangrove attributed to `offerId`'s owner
      upd.gasprice = deriveGasprice(
        upd.gasreq,
        upd.fund,
        upd.local.offer_gasbase()
      );
    } else {
      // offer is still provisioned as offer.gasprice requires
      if (upd.fund > 0) {
        // caller wishes to add provision to existing provision
        // we retrieve current offer provision based on upd.gasprice (which is current offer gasprice)
        upd.fund +=
          upd.gasprice *
          10**9 *
          (upd.offer_detail.gasreq() + upd.local.offer_gasbase());
        upd.gasprice = deriveGasprice(
          upd.gasreq,
          upd.fund,
          upd.local.offer_gasbase()
        );
      }
      // if value == 0  we keep upd.gasprice unchanged
    }
    // if `upd.fund` is too low, offer gasprice might be below mangrove gasprice
    // Mangrove will then take its own gasprice for the offer and would possibly tap into `this` contract's pool to cover for the missing provision
    require(
      upd.gasprice >= upd.global.gasprice(),
      "Forwarder/updateOffer/NotEnoughProvision"
    );
    MGV.updateOffer{value: upd.fund}(
      address(upd.outbound_tkn),
      address(upd.inbound_tkn),
      upd.wants,
      upd.gives,
      upd.gasreq,
      upd.gasprice,
      upd.pivotId,
      upd.offerId
    );
  }

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove. Function call will throw if `this` contract is not the owner of `offerId`.
  ///@param deprovision is true if offer owner wishes to have the offer's provision pushed to its reserve
  function retractOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) public override returns (uint free_wei) {
    OwnerData memory od = ownerData[outbound_tkn][inbound_tkn][offerId];
    require(
      od.owner == msg.sender || address(MGV) == msg.sender,
      "Multi/retractOffer/unauthorized"
    );
    if (od.wei_balance > 0) {
      // offer was already retracted and deprovisioned by Mangrove after a trade failure
      // wei_balance is part of this contract's pooled free wei and can be redeemed by offer owner
      free_wei = deprovision ? od.wei_balance : 0;
    } else {
      free_wei = MGV.retractOffer(
        address(outbound_tkn),
        address(inbound_tkn),
        offerId,
        deprovision
      );
    }
    if (free_wei > 0) {
      // pulling free wei from Mangrove to `this`
      require(MGV.withdraw(free_wei), "Forwarder/withdrawFail");
      // resetting pending returned provision
      ownerData[outbound_tkn][inbound_tkn][offerId] = OwnerData({
        owner: od.owner,
        wei_balance: 0
      });
      // sending WEI's to offer owner. Note that this call could occur nested inside a call to `makerExecute` originating from Mangrove
      // this is still safe because WEI's are being sent to offer owner who has no incentive to make current trade fail. 
      (bool noRevert, ) = od.owner.call{value: free_wei}("");
      require(noRevert, "Forwarder/weiTransferFail");
    }
  }

  // NB anyone can call but msg.sender will only be able to withdraw from its reserve
  function withdrawToken(
    IERC20 token,
    address receiver,
    uint amount
  ) external override returns (bool success) {
    require(receiver != address(0), "Forwarder/withdrawToken/0xReceiver");
    return router().withdrawToken(token, reserve(), receiver, amount);
  }

  function tokenBalance(IERC20 token) external view override returns (uint) {
    return router().reserveBalance(token, reserve());
  }

  // put received inbound tokens on offer owner reserve
  // if nothing is done at that stage then it could still be done in the posthook but it cannot be a flush
  // since `this` contract balance would have the accumulated takers inbound tokens
  // here we make sure nothing remains unassigned after a trade
  function __put__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    IERC20 outTkn = IERC20(order.outbound_tkn);
    IERC20 inTkn = IERC20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);
    address target = _reserve(owner);
    router().push(inTkn, target == address(0) ? owner : target, amount);
    return 0;
  }

  // get outbound tokens from offer owner reserve
  function __get__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    IERC20 outTkn = IERC20(order.outbound_tkn);
    IERC20 inTkn = IERC20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);
    // telling router one is requiring `amount` of `outTkn` for `owner`.
    // because `pull` is strict, `pulled <= amount` (cannot be greater)
    // we do not check local balance here because multi user contracts do not keep more balance than what has been pulled
    address source = _reserve(owner);
    uint pulled = router().pull(
      outTkn,
      source == address(0) ? owner : source,
      amount,
      true
    );
    return amount - pulled;
  }

  // if offer failed to execute or reneged Mangrove has deprovisioned it
  // the wei balance of `this` contract on Mangrove is now positive
  // this fallback returns an under approx of the provision that has been returned to this contract
  // being under approx implies `this` contract might accumulate a small amount of wei over time
  function __posthookFallback__(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) internal virtual override returns (bytes32) {
    result; // ssh
    mapping(uint => OwnerData) storage semiBookOwnerData = ownerData[IERC20(order.outbound_tkn)][IERC20(order.inbound_tkn)];
    OwnerData memory od = semiBookOwnerData[order.offerId];
    // NB if several offers of `this` contract have failed during the market order, the balance of this contract on Mangrove will contain cumulated free provision

    // computing an under approximation of returned provision because of this offer's failure
    (MgvPack.Global.t global, MgvPack.Local.t local) = MGV.config(
      order.outbound_tkn,
      order.inbound_tkn
    );
    uint gaspriceInWei = global.gasprice() * 10**9;
    uint provision = 10**9 *
      order.offerDetail.gasprice() *
      (order.offerDetail.gasreq() + order.offerDetail.offer_gasbase());

    // gas estimate to complete posthook ~ 1500, putting 3000 to be overapproximating
    uint approxBounty = (order.offerDetail.gasreq() -
      gasleft() +
      3000 +
      local.offer_gasbase()) * gaspriceInWei;

    uint approxReturnedProvision = approxBounty >= provision
      ? 0
      : provision - approxBounty;

    // storing the portion of this contract's balance on Mangrove that should be attributed back to the failing offer's owner
    // those free WEIs can be retrieved by offer owner, by calling `retractOffer` with the `deprovision` flag.
    semiBookOwnerData[order.offerId] = OwnerData({
      owner: od.owner,
      wei_balance: uint96(approxReturnedProvision) // previous wei_balance is always 0 here: if offer failed in the past, `updateOffer` did reuse it
    });
    return "";
  }

  function __checkList__(IERC20 token) internal view virtual override {
    AbstractRouter router_ = router();
    require(router_ != NO_ROUTER, "Forwarder/MissingRouter");
    router_.checkList(token, reserve());
    super.__checkList__(token);
  }
}
