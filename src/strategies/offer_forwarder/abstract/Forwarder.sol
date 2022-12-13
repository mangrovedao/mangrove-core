// SPDX-License-Identifier:	BSD-2-Clause

// Forwarder.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MangroveOffer, MOS} from "mgv_src/strategies/MangroveOffer.sol";
import {IForwarder} from "mgv_src/strategies/interfaces/IForwarder.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {IOfferLogic} from "mgv_src/strategies/interfaces/IOfferLogic.sol";
import {MgvLib, IERC20, MgvStructs} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

///@title Class for maker contracts that forward offer makers instructions to Mangrove in a permissionless fashion.
///@notice Each offer posted via this contract are managed by their offer maker, not by this contract's admin.
///@notice This class implements IForwarder, which contains specific Forwarder logic functions in additions to IOfferLogic interface.

abstract contract Forwarder is IForwarder, MangroveOffer {
  // approx of amount of gas units required to complete `__posthookFallback__` when evaluating penalty.
  uint constant GAS_APPROX = 2000;

  ///@notice data associated to each offer published on Mangrove by this contract.
  ///@param owner address of the account that can manage (update or retract) the offer
  ///@param weiBalance fraction of `this` balance on Mangrove that is assigned to `owner`.
  ///@dev `OwnerData` packs into one word.
  struct OwnerData {
    address owner;
    uint96 weiBalance;
  }

  ///@notice Owner data mapping.
  ///@dev mapping is outbound_tkn -> inbound_tkn -> offerId -> OwnerData
  ///@dev 'ownerData[out][in][offerId].owner == maker` if `maker` is offer owner of `offerId` in the `(out, in)` offer list.
  mapping(IERC20 => mapping(IERC20 => mapping(uint => OwnerData))) internal ownerData;

  ///@notice modifier to enforce function caller to be offer owner
  modifier onlyOwner(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId) {
    require(ownerData[outbound_tkn][inbound_tkn][offerId].owner == msg.sender, "AccessControlled/Invalid");
    _;
  }

  ///@notice modifier to enforce function caller to be offer owner or MGV (for use in the offer logic)
  modifier mgvOrOwner(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId) {
    if (msg.sender != address(MGV)) {
      require(ownerData[outbound_tkn][inbound_tkn][offerId].owner == msg.sender, "AccessControlled/Invalid");
    }
    _;
  }

  ///@notice Forwarder constructor
  ///@param mgv the deployed Mangrove contract on which this contract will post offers.
  ///@param router the router that this contract will use to pull/push liquidity from offer maker's reserve. This must not be `NO_ROUTER`.
  ///@param gasreq Gas requirement when posting offers via this strategy, excluding router requirement.
  constructor(IMangrove mgv, AbstractRouter router, uint gasreq) MangroveOffer(mgv, gasreq) {
    require(router != NO_ROUTER, "Forwarder logics must have a router");
    setRouter(router);
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
  /// @param leftover the fraction of `msg.value` that is not locked in the offer provision due to rounding error (see `_newOffer`).
  function addOwner(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, address owner, uint leftover) internal {
    ownerData[outbound_tkn][inbound_tkn][offerId] = OwnerData({owner: owner, weiBalance: uint96(leftover)});
    emit NewOwnedOffer(MGV, outbound_tkn, inbound_tkn, offerId, owner);
  }

  /// @notice computes the maximum `gasprice` that can be covered by the amount of provision given in argument.
  /// @param gasreq the gas required by the offer
  /// @param provision the amount of native token one wishes to use, to provision the offer on Mangrove.
  /// @param offerGasbase Mangrove's offer_gasbase.
  /// @return gasprice the gas price that is covered by `provision` - `leftover`.
  /// @return leftover the sub amount of `provision` that is not used to provision the offer.
  /// @dev the returned gasprice is slightly lower than the real gasprice that the provision can cover because of the rounding error due to division
  function deriveGasprice(uint gasreq, uint provision, uint offerGasbase)
    internal
    pure
    returns (uint gasprice, uint leftover)
  {
    unchecked {
      uint num = (offerGasbase + gasreq) * 10 ** 9;
      // pre-check to avoid underflow since 0 is interpreted as "use Mangrove's gasprice"
      require(provision >= num, "mgv/insufficientProvision");
      // Gasprice is eventually a uint16, so too much provision would yield a gasprice overflow
      // Reverting here with a clearer reason
      require(provision < type(uint16).max * num, "Forwarder/provisionTooHigh");
      gasprice = provision / num;

      // computing amount of native tokens that are not going to be locked on Mangrove
      // this amount should still be recoverable by offer maker when retracting the offer
      leftover = provision - (gasprice * 10 ** 9 * (offerGasbase + gasreq));
    }
  }

  ///@inheritdoc IForwarder
  function ownerOf(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId) public view override returns (address owner) {
    owner = ownerData[outbound_tkn][inbound_tkn][offerId].owner;
    require(owner != address(0), "Forwarder/unknownOffer");
  }

  /// @notice Inserts a new offer on a Mangrove Offer List.
  /// @dev If inside a hook, one should call `_newOffer` to create a new offer and not directly `MGV.newOffer` to make sure one is correctly dealing with:
  /// * offer ownership
  /// * offer provisions and gasprice
  /// @param args memory location of the function's arguments
  /// @param owner the address of the offer owner
  /// @return offerId the identifier of the new offer on the offer list. Can be 0 if posting was rejected by Mangrove and `args.noRevert` is `true`.
  /// Forwarder logic does not manage user funds on Mangrove, as a consequence:
  /// An offer maker's redeemable provisions on Mangrove is just the sum $S_locked(maker)$ of locked provision in all live offers it owns
  /// plus the sum $S_free(maker)$ of `weiBalance`'s in all dead offers it owns (see `OwnerData.weiBalance`).
  /// Notice $\sum_i S_free(maker_i)$ <= MGV.balanceOf(address(this))`.
  /// Any fund of an offer maker on Mangrove that is either not locked on Mangrove or stored in the `OwnerData` free wei's is thus not recoverable by the offer maker (although it is admin recoverable).
  /// Therefore we need to make sure that all `msg.value` is either used to provision the offer at `gasprice` or stored in the offer data under `weiBalance`.
  /// To do so, we do not let offer maker fix a gasprice. Rather we derive the gasprice based on `msg.value`.
  /// Because of rounding errors in `deriveGasprice` a small amount of WEIs will accumulate in mangrove's balance of `this` contract
  /// We assign this leftover to the corresponding `weiBalance` of `OwnerData`.
  function _newOffer(OfferArgs memory args, address owner) internal returns (uint offerId) {
    (MgvStructs.GlobalPacked global, MgvStructs.LocalPacked local) =
      MGV.config(address(args.outbound_tkn), address(args.inbound_tkn));
    // convention for default gasreq value
    args.gasreq = (args.gasreq > type(uint24).max) ? offerGasreq() : args.gasreq;
    // computing max `gasprice` such that `offData.fund` covers `offData.gasreq` at `gasprice`
    (uint gasprice, uint leftover) = deriveGasprice(args.gasreq, args.fund, local.offer_gasbase());
    // mangrove will take max(`mko.gasprice`, `global.gasprice`)
    // if `mko.gasprice < global.gasprice` Mangrove will use available provision of this contract to provision the offer
    // this would potentially take native tokens that have been released after some offer managed by this contract have failed
    // so one needs to make sure here that only provision of this call will be used to provision the offer on mangrove
    require(gasprice >= global.gasprice(), "mgv/insufficientProvision");
    // the call below cannot revert for lack of provision (by design)
    // it may still revert if `offData.fund` yields a gasprice that is too high (mangrove's gasprice is uint16)
    // or if `offData.gives` is below density (dust)
    try MGV.newOffer{value: args.fund}(
      address(args.outbound_tkn), address(args.inbound_tkn), args.wants, args.gives, args.gasreq, gasprice, args.pivotId
    ) returns (uint offerId_) {
      // assign `offerId_` to caller
      addOwner(args.outbound_tkn, args.inbound_tkn, offerId_, owner, leftover);
      offerId = offerId_;
    } catch Error(string memory reason) {
      /// letting revert bubble up unless `noRevert` is positioned.
      require(args.noRevert, reason);
      offerId = 0;
    }
  }

  ///@notice memory allocation for `_updateOffer` variables
  ///@param gasprice derived gasprice of the offer
  ///@param leftover portion of `msg.value` that are not allocated to offer's provision
  struct UpdateOfferVars {
    uint leftover;
    MgvStructs.GlobalPacked global;
    MgvStructs.LocalPacked local;
    MgvStructs.OfferDetailPacked offerDetail;
  }

  ///@notice Internal `updateOffer`, using arguments and variables on memory to avoid stack too deep.
  ///@return reason in {REPOST_FAILED_DUST, REPOST_FAILED} if update was rejected by Mangrove and `args.noRevert` is `true` or REPOST_SUCCESS otherwise
  function _updateOffer(OfferArgs memory args, uint offerId) internal override returns (bytes32) {
    unchecked {
      UpdateOfferVars memory vars;
      (vars.global, vars.local) = MGV.config(address(args.outbound_tkn), address(args.inbound_tkn));
      vars.offerDetail = MGV.offerDetails(address(args.outbound_tkn), address(args.inbound_tkn), offerId);

      uint old_gasreq = vars.offerDetail.gasreq();
      args.gasreq = args.gasreq >= type(uint24).max ? old_gasreq : args.gasreq;
      // re-deriving gasprice only if necessary
      if (
        args.fund > 0 // user adds more provision
          || args.gasreq != old_gasreq // offer's `gasreq` is modified
          || vars.offerDetail.offer_gasbase() != vars.local.offer_gasbase() // governance has updated `offer_gasbase`
      ) {
        // adding current locked provision to funds (0 if offer is deprovisioned)
        uint locked_funds = vars.offerDetail.gasprice() * 10 ** 9 * (old_gasreq + vars.offerDetail.offer_gasbase());
        // note that if `args.gasreq < old_gasreq` then offer gasprice will increase (even if `args.fund == 0`) to match the incurred excess of locked provision
        (args.gasprice, vars.leftover) =
          deriveGasprice(args.gasreq, args.fund + locked_funds, vars.local.offer_gasbase());

        // leftover can be safely cast to uint96 since it's a rounding error
        // adding `leftover` to potential previous value since it was not included in args.fund
        ownerData[args.outbound_tkn][args.inbound_tkn][offerId].weiBalance += uint96(vars.leftover);
      } else {
        // no funds are added so we keep old gasprice
        args.gasprice = vars.offerDetail.gasprice();
      }
      // if `args.fund` is too low, offer gasprice might be below mangrove's gasprice
      // Mangrove will then take its own gasprice for the offer and would possibly tap into `this` contract's balance to cover for the missing provision
      require(args.gasprice >= vars.global.gasprice(), "mgv/insufficientProvision");
      try MGV.updateOffer{value: args.fund}(
        address(args.outbound_tkn),
        address(args.inbound_tkn),
        args.wants,
        args.gives,
        args.gasreq,
        args.gasprice,
        args.pivotId,
        offerId
      ) {
        return REPOST_SUCCESS;
      } catch Error(string memory reason) {
        require(args.noRevert, reason);
        return bytes32(bytes(reason));
      }
    }
  }

  ///@inheritdoc IOfferLogic
  function provisionOf(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId)
    external
    view
    override
    returns (uint provision)
  {
    provision = _provisionOf(outbound_tkn, inbound_tkn, offerId);
    unchecked {
      provision += ownerData[outbound_tkn][inbound_tkn][offerId].weiBalance;
    }
  }

  ///@inheritdoc IOfferLogic
  function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
    public
    override
    mgvOrOwner(outbound_tkn, inbound_tkn, offerId)
    returns (uint freeWei)
  {
    OwnerData storage od = ownerData[outbound_tkn][inbound_tkn][offerId];
    freeWei = deprovision ? od.weiBalance : 0; // (a)
    freeWei += MGV.retractOffer(address(outbound_tkn), address(inbound_tkn), offerId, deprovision); // (b)
    if (freeWei > 0) {
      // pulling free wei from Mangrove to `this`
      require(MGV.withdraw(freeWei), "Forwarder/withdrawFail");
      // resetting pending returned provision
      od.weiBalance = 0;
      // Griefing issue: the call below could occur nested inside a call to `makerExecute` originating from Mangrove, so `owner` could make the current trade fail.
      // Here we are safe because callee is offer owner and has no incentive to make current trade fail or waste gas.
      // w.r.t reentrancy:
      // * `od.weiBalance` is set to 0 (storage write) prior to this call, so a reentrant call to `retractOffer` would give `freeWei = 0` at (a)
      // * further call to `MGV.retractOffer` will yield no more WEIs so `freeWei += 0` at (b)
      // * (a /\ b) imply that the above call to `MGV.withdraw` will be done with `freeWei == 0`.
      // * `retractOffer` is the only function that allows non admin users to withdraw WEIs from Mangrove.
      (bool noRevert,) = od.owner.call{value: freeWei}("");
      require(noRevert, "mgvOffer/weiTransferFail");
    }
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
    uint pushed = router().push(inTkn, reserve(owner), amount);
    return amount - pushed;
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
    uint pulled = router().pull(outTkn, reserve(owner), amount, true);
    return amount - pulled; // this will make trade fail if `amount != pulled`
  }

  ///@dev if offer failed to execute, Mangrove retracts and deprovisions it after the posthook call.
  /// As a consequence if this hook is reached, `this` balance on Mangrove *will* increase, after the posthook,
  /// of some amount $n$ of native tokens. We evaluate here an underapproximation $~n$ in order to credit the offer maker in a pull based manner:
  /// failed offer owner can retrieve $~n$ by calling `retractOffer` on the failed offer.
  /// because $~n<n$ a small amount of WEIs will accumulate on the balance of `this` on Mangrove over time.
  /// Note that these WEIs are not burnt since they can be admin retrieved using `withdrawFromMangrove`.
  /// @inheritdoc MangroveOffer
  function __handleResidualProvision__(MgvLib.SingleOrder calldata order) internal virtual override {
    mapping(uint => OwnerData) storage semiBookOwnerData =
      ownerData[IERC20(order.outbound_tkn)][IERC20(order.inbound_tkn)];
    // NB if several offers of `this` contract have failed during the market order, the balance of this contract on Mangrove will contain cumulated free provision

    // computing an under approximation of returned provision because of this offer's failure
    uint gasreq = order.offerDetail.gasreq();
    uint provision = 10 ** 9 * order.offerDetail.gasprice() * (gasreq + order.offerDetail.offer_gasbase());

    // gasUsed estimate to complete posthook and penalize this offer is ~1750 (empirical estimate)
    uint gasprice = order.global.gasprice() * 10 ** 9;
    uint approxGasConsumption = gasreq + GAS_APPROX + order.local.offer_gasbase();
    uint approxBounty = (approxGasConsumption - gasleft()) * gasprice;
    uint approxReturnedProvision = approxBounty >= provision ? 0 : provision - approxBounty;

    // storing the portion of this contract's balance on Mangrove that should be attributed back to the failing offer's owner
    // those free WEIs can be retrieved by offer owner, by calling `retractOffer` with the `deprovision` flag.
    semiBookOwnerData[order.offerId].weiBalance += uint96(approxReturnedProvision);
  }
}
