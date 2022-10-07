// SPDX-License-Identifier:	BSD-2-Clause

// Forwarder.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

pragma abicoder v2;

import {MangroveOffer} from "src/strategies/MangroveOffer.sol";
import {IForwarder} from "src/strategies/interfaces/IForwarder.sol";
import {AbstractRouter} from "src/strategies/routers/AbstractRouter.sol";
import {IOfferLogic} from "src/strategies/interfaces/IOfferLogic.sol";
import {MgvLib, IERC20, MgvStructs} from "src/MgvLib.sol";
import {IMangrove} from "src/IMangrove.sol";
import {console2} from "forge-std/console2.sol";

///@title Class for maker contracts that forward external offer makers instructions to Mangrove in a permissionless fashion.
///@notice Each offer posted via this contract are managed by their offer maker, not by this contract's admin.
///@notice This class implements IForwarder, which contains specific Forwarder logic functions in additions to IOfferLogic interface.

abstract contract Forwarder is IForwarder, MangroveOffer {
  // approx of amount of gas units required to complete `__posthookFallback__` when evaluating penalty.
  uint constant GAS_APPROX = 2000;

  ///@notice data associated to each offer published on Mangrove by `this` contract.
  ///@param owner address of the account that can manage (update or retract) the offer
  ///@param wei_balance fraction of `this` contract's balance on Mangrove that can be retrieved by offer owner.
  struct OwnerData {
    address owner;
    uint96 wei_balance;
  }

  ///@notice Owner data mapping.
  ///@dev outbound_tkn => inbound_tkn => offerId => OwnerData
  mapping(IERC20 => mapping(IERC20 => mapping(uint => OwnerData))) internal ownerData;

  ///@notice modifier to enforce function caller to be either Mangrove or offer owner
  modifier mgvOrOwner(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId) {
    if (msg.sender != address(MGV)) {
      OwnerData memory od = ownerData[outbound_tkn][inbound_tkn][offerId];
      require(od.owner == msg.sender, "Forwarder/retractOffer/unauthorized");
    }
    _;
  }

  ///@notice Forwarder constructor
  ///@param mgv the deployed Mangrove contract on which `this` contract will post offers.
  ///@param router_ the router that `this` contract will use to pull/push liquidity from offer maker's reserve. This cannot be `NO_ROUTER`.
  constructor(IMangrove mgv, AbstractRouter router_) MangroveOffer(mgv) {
    require(router_ != NO_ROUTER, "Forwarder logics must have a router");
    setRouter(router_);
  }

  ///@inheritdoc IForwarder
  function offerOwners(IERC20 outbound_tkn, IERC20 inbound_tkn, uint[] calldata offerIds)
    public
    view
    override
    returns (address[] memory offerOwners_)
  {
    offerOwners_ = new address[](offerIds.length);
    for (uint i = 0; i < offerIds.length; i++) {
      offerOwners_[i] = ownerOf(outbound_tkn, inbound_tkn, offerIds[i]);
    }
  }

  /// @notice grants managing (update/retract) rights on a particular offer.
  /// @param outbound_tkn the outbound token coordinate of the offer list.
  /// @param inbound_tkn the inbound token coordinate of the offer list.
  /// @param offerId the offer identifier in the offer list.
  /// @param owner the address of the offer maker.
  /// @param leftover the fraction of msg.value that is not locked in the offer provision due to rounding error (see `_newOffer`).
  function addOwner(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, address owner, uint leftover) internal {
    ownerData[outbound_tkn][inbound_tkn][offerId] = OwnerData({owner: owner, wei_balance: uint96(leftover)});
    emit NewOwnedOffer(MGV, outbound_tkn, inbound_tkn, offerId, owner);
  }

  /// @notice computes the maximum `gasprice` that can be covered by the amount of provision given in argument.
  /// @param gasreq the gas required by the offer
  /// @param provision the amount of native token one is wishes to use, to provision the offer on Mangrove.
  /// @return gasprice the gas price that is covered by `provision` - `leftover`.
  /// @return leftover the sub amount of `provision` that is not used to provision the offer.
  /// @dev the returned gasprice is slightly lower than the real gasprice that the provision can cover because of the rounding error due to division
  function deriveGasprice(uint gasreq, uint provision, uint offer_gasbase)
    internal
    pure
    returns (uint gasprice, uint leftover)
  {
    unchecked {
      uint num = (offer_gasbase + gasreq) * 10 ** 9;
      // pre-check to avoid underflow since 0 is interpreted as "use mangrove's gasprice"
      require(provision >= num, "mgv/insufficientProvision");
      // Gasprice is eventually a uint16, so too much provision would yield a gasprice overflow
      // Reverting here with a clearer reason
      require(provision < type(uint16).max * num, "Forwarder/provisionTooHigh");
      gasprice = provision / num;

      // computing amount of native tokens that are not going to be locked on mangrove
      // this amount should still be recoverable by offer maker when retracting the offer
      leftover = provision - (gasprice * 10 ** 9 * (offer_gasbase + gasreq));
    }
  }

  ///@inheritdoc IForwarder
  function ownerOf(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId) public view override returns (address owner) {
    owner = ownerData[outbound_tkn][inbound_tkn][offerId].owner;
    require(owner != address(0), "Forwarder/unknownOffer");
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

  ///@notice Memory allocation for `_newOffer`'s arguments.
  ///@param outbound_tkn outbound token of the offer list.
  ///@param inbound_tkn inbound token of the offer list.
  ///@param wants the amount of inbound tokens the maker wants for a complete fill.
  ///@param gives the amount of outbound tokens the maker gives for a complete fill.
  ///@param gasreq gas required for trade execution.
  ///@param pivotId a best pivot estimate for cheap offer insertion in the offer list.
  ///@param caller msg.sender of the calling external function.
  ///@param fund WEIs in `this` contract's balance that are used to provision the offer.
  ///@param noRevert is set to true if calling function does not wish `_newOffer` to revert on error. Out of gas exception is always possible though.
  struct NewOfferArgs {
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

  /// @notice Inserts a new offer on a Mangrove Offer List.
  /// @dev If inside a hook, one should call `_newOffer` to create a new offer and not directly `MGV.newOffer` to make sure one is correctly dealing with:
  /// * offer ownership
  /// * offer provisions and gasprice
  /// @param offData memory location of the function's arguments
  /// @return offerId the identifier of the new offer on the offer list
  /// Forwarder logic does not manage user funds on Mangrove, as a consequence:
  /// An offer maker's redeemable provisions on Mangrove is just the sum $S_locked(maker)$ of locked provision in all live offers it owns
  /// plus the sum $S_free(maker)$ of `wei_balance`'s in all dead offers it owns (see `OwnerData.wei_balance`).
  /// Notice $\sum_i S_free(maker_i)$ <= MGV.balanceOf(address(this))`.
  /// Any fund of an offer maker on Mangrove that is either not locked on Mangrove or stored in the `OwnerData` free wei's is thus not recoverable by the offer maker.
  /// Therefore we need to make sure that all `msg.value` is either used to provision the offer at `gasprice` or stored in the offer data under `wei_balance`.
  /// To do so, we do not let offer maker fix a gasprice. Rather we derive the gasprice based on `msg.value`.
  /// Because of rounding errors in `deriveGasprice` a small amount of WEIs will accumulate in mangrove's balance of `this` contract
  /// We assign this leftover to the corresponding `wei_balance` of `OwnerData`.
  function _newOffer(NewOfferArgs memory offData) internal returns (uint offerId) {
    (MgvStructs.GlobalPacked global, MgvStructs.LocalPacked local) =
      MGV.config(address(offData.outbound_tkn), address(offData.inbound_tkn));
    // convention for default gasreq value
    offData.gasreq = (offData.gasreq > type(uint24).max) ? offerGasreq() : offData.gasreq;
    // computing max `gasprice` such that `offData.fund` covers `offData.gasreq` at `gasprice`
    (uint gasprice, uint leftover) = deriveGasprice(offData.gasreq, offData.fund, local.offer_gasbase());
    // mangrove will take max(`mko.gasprice`, `global.gasprice`)
    // if `mko.gasprice < global.gasprice` Mangrove will use available provision of this contract to provision the offer
    // this would potentially take native tokens that have been released after some offer managed by this contract have failed
    // so one needs to make sure here that only provision of this call will be used to provision the offer on mangrove
    require(gasprice >= global.gasprice(), "mgv/insufficientProvision");
    // the call below cannot revert for lack of provision (by design)
    // it may still revert if `offData.fund` yields a gasprice that is too high (mangrove's gasprice is uint16)
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
      addOwner(offData.outbound_tkn, offData.inbound_tkn, offerId_, offData.caller, leftover);
      offerId = offerId_;
    } catch Error(string memory reason) {
      /// letting revert bubble up unless `noRevert` is positioned.
      require(offData.noRevert, reason);
      offerId = 0;
    }
  }

  ///@dev the `gasprice` argument is always ignored in `Forwarder` logic, since it has to be derived from `msg.value` of the call (see `_newOffer`).
  ///@inheritdoc IOfferLogic
  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice, // value ignored but kept to satisfy `Forwarder is IOfferLogic`
    uint pivotId,
    uint offerId
  ) public payable override mgvOrOwner(outbound_tkn, inbound_tkn, offerId) {
    gasprice; // ssh
    UpdateOfferArgs memory upd;

    upd.offer_detail = MGV.offerDetails(address(outbound_tkn), address(inbound_tkn), offerId);
    (upd.global, upd.local) = MGV.config(address(outbound_tkn), address(inbound_tkn));
    // funds to compute new gasprice is msg.value. Will use old gasprice if no funds are given
    // it might be tempting to include `od.wei_balance` here but this will trigger a recomputation of the `gasprice`
    // each time a offer is updated.
    upd.fund = msg.value; // if called by Mangrove this will be 0
    upd.outbound_tkn = outbound_tkn;
    upd.inbound_tkn = inbound_tkn;
    upd.wants = wants;
    upd.gives = gives;
    upd.gasreq = gasreq > type(uint24).max ? upd.offer_detail.gasreq() : gasreq; // not using offerGasReq() to save a storage read.
    upd.pivotId = pivotId;
    upd.offerId = offerId;
    // wei_balance is used to provision offer
    _updateOffer(upd);
  }

  ///@notice Memory allocation of `_updateOffer` arguments
  ///@param global current block's global configuration variables of Mangrove
  ///@param local current block's configuration variables of the (outbound token, inbound token) offer list
  ///@param offer_detail a recap of the current block's offer details.
  ///@param fund available funds for provisioning the offer
  ///@param outbound_tkn token contract
  ///@param inbound_tkn token contract
  ///@param wants the new amount of inbound tokens the maker wants for a complete fill
  ///@param gives the new amount of outbound tokens the maker gives for a complete fill
  ///@param gasreq new gasreq for the updated offer.
  ///@param pivotId a best pivot estimate for cheap offer insertion in the offer list
  ///@param offerId the id of the offer to be updated
  struct UpdateOfferArgs {
    MgvStructs.GlobalPacked global;
    MgvStructs.LocalPacked local;
    MgvStructs.OfferDetailPacked offer_detail;
    uint fund;
    IERC20 outbound_tkn;
    IERC20 inbound_tkn;
    uint wants;
    uint gives;
    uint gasreq;
    uint pivotId;
    uint offerId;
    address owner;
  }

  ///@notice memory allocation for `_updateOffer` variables
  ///@param gasprice derived gasprice of the offer
  ///@param leftover portion of `msg.value` that are not allocated to offer's provision
  struct UpdateOfferVars {
    uint gasprice;
    uint leftover;
  }

  ///@notice Implementation body of `updateOffer`, using arguments and variables on memory to avoid stack too deep.
  function _updateOffer(UpdateOfferArgs memory args) private {
    UpdateOfferVars memory vars;
    // re-deriving gasprice only if necessary
    if (args.fund != 0) {
      // adding current locked provision to funds (0 if offer is deprovisioned)
      (vars.gasprice, vars.leftover) = deriveGasprice(
        args.gasreq,
        args.fund + args.offer_detail.gasprice() * 10 ** 9 * (args.offer_detail.gasreq() + args.local.offer_gasbase()),
        args.local.offer_gasbase()
      );
      // leftover can be safely cast to uint96 since it a rounding error
      // adding `leftover` to potential previous value since it was not included in args.fund
      ownerData[args.outbound_tkn][args.inbound_tkn][args.offerId].wei_balance += uint96(vars.leftover);
    } else {
      // no funds are added so we keep old gasprice
      vars.gasprice = args.offer_detail.gasprice();
    }

    // if `args.fund` is too low, offer gasprice might be below mangrove's gasprice
    // Mangrove will then take its own gasprice for the offer and would possibly tap into `this` contract's pool to cover for the missing provision
    require(vars.gasprice >= args.global.gasprice(), "mgv/insufficientProvision");
    MGV.updateOffer{value: args.fund}(
      address(args.outbound_tkn),
      address(args.inbound_tkn),
      args.wants,
      args.gives,
      args.gasreq,
      vars.gasprice,
      args.pivotId,
      args.offerId
    );
  }

  ///@inheritdoc IOfferLogic
  function provisionOf(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId)
    external
    view
    override
    returns (uint provision)
  {
    MgvStructs.OfferDetailPacked offer_detail = MGV.offerDetails(address(outbound_tkn), address(inbound_tkn), offerId);
    (, MgvStructs.LocalPacked local) = MGV.config(address(outbound_tkn), address(inbound_tkn));
    unchecked {
      provision = offer_detail.gasprice() * 10 ** 9 * (local.offer_gasbase() + offer_detail.gasreq());
      provision += ownerData[outbound_tkn][inbound_tkn][offerId].wei_balance;
    }
  }

  ///@inheritdoc IOfferLogic
  function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
    public
    override
    mgvOrOwner(outbound_tkn, inbound_tkn, offerId)
    returns (uint free_wei)
  {
    OwnerData memory od = ownerData[outbound_tkn][inbound_tkn][offerId];
    free_wei = deprovision ? od.wei_balance : 0;
    free_wei += MGV.retractOffer(address(outbound_tkn), address(inbound_tkn), offerId, deprovision);
    if (free_wei > 0) {
      // pulling free wei from Mangrove to `this`
      require(MGV.withdraw(free_wei), "Forwarder/withdrawFail");
      // resetting pending returned provision
      ownerData[outbound_tkn][inbound_tkn][offerId].wei_balance = 0;
      // sending WEI's to offer owner. Note that this call could occur nested inside a call to `makerExecute` originating from Mangrove
      // this is still safe because WEI's are being sent to offer owner who has no incentive to make current trade fail or waste gas.
      (bool noRevert,) = od.owner.call{value: free_wei}("");
      require(noRevert, "Forwarder/weiTransferFail");
    }
  }

  ///@inheritdoc IOfferLogic
  function withdrawToken(IERC20 token, address receiver, uint amount) external override returns (bool success) {
    require(receiver != address(0), "Forwarder/withdrawToken/0xReceiver");
    if (amount == 0) {
      success = true;
    }
    success = router().withdrawToken(token, reserve(), receiver, amount);
  }

  ///@inheritdoc IOfferLogic
  function tokenBalance(IERC20 token) external view override returns (uint) {
    return router().reserveBalance(token, reserve());
  }

  ///@dev put received inbound tokens on offer maker's reserve during `makerExecute`
  /// if nothing is done at that stage then it could still be done during `makerPosthook`.
  /// However one would then need to pay attention to the following fact:
  /// if `order.inbound_tkn` is not pushed to reserve during `makerExecute`, in the posthook of this offer execution, the `order.inbound_tkn` balance of this contract would then contain
  /// the sum of all payments of offers managed by `this` that are in a better position in the offer list (because posthook is called in the call stack order).
  /// here we maintain an invariant that `this` balance is empty (both for `order.inbound_tkn` and `order.outbound_tkn`) at the end of `makerExecute`.
  ///@inheritdoc MangroveOffer
  function __put__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    IERC20 outTkn = IERC20(order.outbound_tkn);
    IERC20 inTkn = IERC20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);
    address target = _reserve(owner);
    router().push(inTkn, target == address(0) ? owner : target, amount);
    return 0;
  }

  ///@dev get outbound tokens from offer owner reserve
  ///@inheritdoc MangroveOffer
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    IERC20 outTkn = IERC20(order.outbound_tkn);
    IERC20 inTkn = IERC20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);
    // telling router one is requiring `amount` of `outTkn` for `owner`.
    // because `pull` is strict, `pulled <= amount` (cannot be greater)
    // we do not check local balance here because multi user contracts do not keep more balance than what has been pulled
    address source = _reserve(owner);
    uint pulled = router().pull(outTkn, source == address(0) ? owner : source, amount, true);
    return amount - pulled; // this will make trade fail if `amount != pulled`
  }

  ///@dev if offer failed to execute, Mangrove retracts and deprovisions it after the posthook call.
  /// As a consequence if `__posthookFallback__` is reached, `this` balance on Mangrove *will* increase, after the posthook,
  /// of some amount $n$ of native tokens. We evaluate here an underapproximation $~n$ in order to credit the offer maker in a pull based manner:
  /// failed offer owner can retrieve $~n$ by calling `retractOffer` on the failed offer.
  /// because $~n<n$ a small amount of WEIs will accumulate on the balance of `this` on Mangrove over time.
  /// Note that these WEIs are not burnt since they can be admin retrieved using `withdrawFromMangrove`.
  /// @inheritdoc MangroveOffer
  function __posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result)
    internal
    virtual
    override
    returns (bytes32)
  {
    result; // ssh
    mapping(uint => OwnerData) storage semiBookOwnerData =
      ownerData[IERC20(order.outbound_tkn)][IERC20(order.inbound_tkn)];
    // NB if several offers of `this` contract have failed during the market order, the balance of this contract on Mangrove will contain cumulated free provision

    // computing an under approximation of returned provision because of this offer's failure
    (MgvStructs.GlobalPacked global, MgvStructs.LocalPacked local) = MGV.config(order.outbound_tkn, order.inbound_tkn);
    uint provision =
      10 ** 9 * order.offerDetail.gasprice() * (order.offerDetail.gasreq() + order.offerDetail.offer_gasbase());

    // gasUsed estimate to complete posthook and penalize this offer is ~1750 (empirical estimate)
    uint approxBounty =
      (order.offerDetail.gasreq() - (gasleft() - GAS_APPROX) + local.offer_gasbase()) * global.gasprice() * 10 ** 9;
    uint approxReturnedProvision = approxBounty >= provision ? 0 : provision - approxBounty;

    // storing the portion of this contract's balance on Mangrove that should be attributed back to the failing offer's owner
    // those free WEIs can be retrieved by offer owner, by calling `retractOffer` with the `deprovision` flag.
    semiBookOwnerData[order.offerId].wei_balance += uint96(approxReturnedProvision);
    // console2.log(gas - gasleft());
    return "";
  }

  ///@notice Verifying that this contract has a router and that its checklist does not revert.
  function __checkList__(IERC20 token) internal view virtual override {
    AbstractRouter router_ = router();
    require(router_ != NO_ROUTER, "Forwarder/MissingRouter");
    router_.checkList(token, reserve());
    super.__checkList__(token);
  }
}
