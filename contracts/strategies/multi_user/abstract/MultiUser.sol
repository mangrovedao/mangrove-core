// SPDX-License-Identifier:	BSD-2-Clause

// MultiUser.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "../../MangroveOffer.sol";
import "mgv_src/periphery/MgvReader.sol";
import "mgv_src/strategies/interfaces/IOfferLogicMulti.sol";

abstract contract MultiUser is IOfferLogicMulti, MangroveOffer {
  struct OfferData {
    // offer owner address
    address owner;
    // under approx of the portion of this contract's balance on mangrove
    // that can be returned to the user's reserve when this offer is deprovisioned
    uint96 wei_balance;
  }

  ///@dev outbound_tkn => inbound_tkn => offerId => OfferData
  mapping(IERC20 => mapping(IERC20 => mapping(uint => OfferData)))
    internal offerData;

  constructor(
    IMangrove _mgv,
    AbstractRouter _router,
    uint strat_gasreq
  ) MangroveOffer(_mgv, strat_gasreq) {
    require(address(_router) != address(0), "MultiUser/0xRouter");
    // define `_router` as the liquidity router for `this` and declare that `this` is allowed to call router.
    // NB router also needs to be approved for outbound/inbound token transfers by each user of this contract.
    set_router(_router);
  }

  /// @param offerIds an array of offer ids from the `outbound_tkn, inbound_tkn` offer list
  /// @return _offerOwners an array of the same length where the address at position i is the owner of `offerIds[i]`
  function offerOwners(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint[] calldata offerIds
  ) public view override returns (address[] memory _offerOwners) {
    _offerOwners = new address[](offerIds.length);
    for (uint i = 0; i < offerIds.length; i++) {
      _offerOwners[i] = ownerOf(outbound_tkn, inbound_tkn, offerIds[i]);
    }
  }

  /// @notice assigns an `owner` to `offerId`  on the `(outbound_tkn, inbound_tkn)` offer list
  function addOwner(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId,
    address owner
  ) internal {
    offerData[outbound_tkn][inbound_tkn][offerId] = OfferData({
      owner: owner,
      wei_balance: uint96(0)
    });
    emit NewOwnedOffer(MGV, outbound_tkn, inbound_tkn, offerId, owner);
  }

  /// @param gasreq the gas required by the offer
  /// @param provision the amount of native token one is using to provision the offer
  /// @return gasprice that the `provision` can cover for
  /// @dev the returned gasprice is slightly lower than the real gasprice that the provision can cover because of the rouding error due to division
  function derive_gasprice(
    uint gasreq,
    uint provision,
    uint offer_gasbase
  ) internal pure returns (uint gasprice) {
    uint num = (offer_gasbase + gasreq) * 10**9;
    // pre-check to avoir underflow
    require(provision >= num, "MultiUser/derive_gasprice/NotEnoughProvision");
    unchecked {
      gasprice = provision / num;
    }
  }

  function ownerOf(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId
  ) public view override returns (address owner) {
    owner = offerData[outbound_tkn][inbound_tkn][offerId].owner;
    require(owner != address(0), "multiUser/unkownOffer");
  }

  // splitting newOffer into external/internal in order to let internal calls specify who the owner of the newly created offer should be.
  // in case `newOffer` is being called during `makerExecute` or `posthook` calls.
  function newOffer(MakerOrder calldata mko)
    external
    payable
    override
    returns (uint offerId)
  {
    offerId = newOfferInternal(mko, msg.sender, msg.value);
  }

  function newOfferInternal(
    MakerOrder memory mko,
    address owner,
    uint provision
  ) internal returns (uint) {
    (P.Global.t global, P.Local.t local) = MGV.config(
      address(mko.outbound_tkn),
      address(mko.inbound_tkn)
    );
    // convention for default gasreq value
    mko.gasreq = (mko.gasreq > type(uint24).max) ? ofr_gasreq() : mko.gasreq;
    // computing gasprice implied by offer provision
    mko.gasprice = derive_gasprice(
      mko.gasreq,
      provision,
      local.offer_gasbase()
    );
    // mangrove will take max(`mko.gasprice`, `global.gasprice`)
    // if `mko.gapsrice < global.gasprice` Mangrove will use availble provision of this contract to provision the offer
    // this would potentially take native tokens that have been released after some offer managed by this contract have failed
    // so one needs to make sure here that only provision of this call will be used to provision the offer on mangrove
    require(
      mko.gasprice >= global.gasprice(),
      "MultiUser/newOffer/NotEnoughProvision"
    );

    // this call cannot revert for lack of provision (by design)
    mko.offerId = MGV.newOffer{value: provision}(
      $(mko.outbound_tkn),
      $(mko.inbound_tkn),
      mko.wants,
      mko.gives,
      mko.gasreq,
      mko.gasprice,
      mko.pivotId
    );
    //setting owner of offerId
    addOwner(mko.outbound_tkn, mko.inbound_tkn, mko.offerId, owner);
    return mko.offerId;
  }

  ///@notice update offer with parameters given in `mko`.
  ///@dev mko.gasreq == max_int indicates one wishes to use ofr_gasreq (default value)
  ///@dev mko.gasprice is overriden by the value computed by taking into account :
  /// * value transfered on current tx
  /// * if offer was deprovisioned after a fail, amount of wei (still on this contract balance on Mangrove) that should be counted as offer owner's
  /// * if offer is still live, its current locked provision
  function updateOffer(MakerOrder calldata mko) external payable {
    require(updateOfferInternal(mko, msg.value), "MultiUser/updateOfferFail");
  }

  // mko.gasprice is ignored (should be 0) because it needs to be derived from provision of the offer
  // not doing this would allow a user to submit an `new/updateOffer` underprovisioned for the announced gasprice
  // Mangrove would then erroneously take missing WEIs in `this` contract free balance (possibly coming from uncollected deprovisioned offers after a fail).
  // need to treat 2 cases:
  // * if offer is deprovisioned one needs to use msg.value and `offerData.wei_balance` to derive gasprice (deprovioning sets offer.gasprice to 0)
  // * if offer is still live one should compute its currenlty locked provision $P$ and derive gasprice based on msg.value + $P$ (note if msg.value = 0 offer can be reposted with offer.gasprice)

  struct UpdateData {
    P.Global.t global;
    P.Local.t local;
    P.OfferDetail.t offer_detail;
    uint provision;
  }

  function updateOfferInternal(MakerOrder memory mko, uint value)
    internal
    returns (bool)
  {
    OfferData memory od = offerData[mko.outbound_tkn][mko.inbound_tkn][
      mko.offerId
    ];
    UpdateData memory upd;
    require(
      msg.sender == od.owner || msg.sender == address(MGV),
      "Multi/updateOffer/unauthorized"
    );

    upd.offer_detail = MGV.offerDetails(
      $(mko.outbound_tkn),
      $(mko.inbound_tkn),
      mko.offerId
    );
    (upd.global, upd.local) = MGV.config(
      $(mko.outbound_tkn),
      $(mko.inbound_tkn)
    );
    upd.provision = value;
    // if `od.free_wei` > 0 then `this` contract has a free wei balance >= `od.free_wei`.
    // Gasprice must take this into account because Mangrove will pull into available WEIs if gasprice requires it.
    mko.gasreq = (mko.gasreq > type(uint24).max) ? ofr_gasreq() : mko.gasreq;
    mko.gasprice = upd.offer_detail.gasprice(); // 0 if offer is deprovisioned

    if (mko.gasprice == 0) {
      // offer was previously deprovisioned, we add the portion of this contract WEI pool on Mangrove that belongs to this offer (if any)
      if (od.wei_balance > 0) {
        upd.provision += od.wei_balance;
        offerData[mko.outbound_tkn][mko.inbound_tkn][mko.offerId] = OfferData({
          owner: od.owner,
          wei_balance: 0
        });
      }
      // gasprice for this offer will be computed using msg.value and available funds on Mangrove attributed to `offerId`'s owner
      mko.gasprice = derive_gasprice(
        mko.gasreq,
        upd.provision,
        upd.local.offer_gasbase()
      );
    } else {
      // offer is still provisioned as offer.gasprice requires
      if (value > 0) {
        // caller wishes to add provision to existing provision
        // we retrieve current offer provision based on upd.gasprice (which is current offer gasprice)
        upd.provision +=
          mko.gasprice *
          10**9 *
          (upd.offer_detail.gasreq() + upd.local.offer_gasbase());
        mko.gasprice = derive_gasprice(
          mko.gasreq,
          upd.provision,
          upd.local.offer_gasbase()
        );
      }
      // if value == 0  we keep upd.gasprice unchanged
    }
    require(
      mko.gasprice >= upd.global.gasprice(),
      "MultiUser/updateOffer/NotEnoughProvision"
    );
    try
      MGV.updateOffer{value: value}(
        $(mko.outbound_tkn),
        $(mko.inbound_tkn),
        mko.wants,
        mko.gives,
        mko.gasreq,
        mko.gasprice,
        mko.pivotId,
        mko.offerId
      )
    {
      return true;
    } catch {
      return false;
    }
  }

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove. Function call will throw if `this` contract is not the owner of `offerId`.
  ///@param deprovision is true if offer owner wishes to have the offer's provision pushed to its reserve
  function retractOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) public override returns (uint free_wei) {
    OfferData memory od = offerData[outbound_tkn][inbound_tkn][offerId];
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
        $(outbound_tkn),
        $(inbound_tkn),
        offerId,
        deprovision
      );
    }
    if (free_wei > 0) {
      // pulling free wei from Mangrove to `this`
      require(MGV.withdraw(free_wei), "MultiUser/withdrawFail");
      // resetting pending returned provision
      offerData[outbound_tkn][inbound_tkn][offerId] = OfferData({
        owner: od.owner,
        wei_balance: 0
      });
      // letting router decide what it should do with owner's free wei
      (bool noRevert, ) = msg.sender.call{value: free_wei}("");
      require(noRevert, "MultiUser/weiTransferFail");
    }
  }

  // NB anyone can call but msg.sender will only be able to withdraw from its reserve
  function withdrawToken(
    IERC20 token,
    address receiver,
    uint amount
  ) external override returns (bool success) {
    require(receiver != address(0), "MultiUser/withdrawToken/0xReceiver");
    return router().withdrawToken(token, msg.sender, receiver, amount);
  }

  function tokenBalance(IERC20 token) external view override returns (uint) {
    return router().reserveBalance(token, msg.sender);
  }

  // put received inbound tokens on offer owner reserve
  // if nothing is done at that stage then it could still be done in the posthook but it cannot be a flush
  // since `this` contract balance would have the accumulated takers inbound tokens
  // here we make sure nothing remains unassigned after a trade
  function __put__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    IERC20 outTkn = IERC20(order.outbound_tkn);
    IERC20 inTkn = IERC20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);
    router().push(inTkn, owner, amount);
    return 0;
  }

  // get outbound tokens from offer owner reserve
  function __get__(uint amount, ML.SingleOrder calldata order)
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
    uint pulled = router().pull(outTkn, owner, amount, true);
    return amount - pulled;
  }

  // if offer failed to execute or reneged Mangrove has deprovisioned it
  // the wei balance of `this` contract on Mangrove is now positive
  // this fallback returns an under approx of the provision that has been returned to this contract
  // being under approx implies `this` contract might accumulate a small amount of wei over time
  function __posthookFallback__(
    ML.SingleOrder calldata order,
    ML.OrderResult calldata result
  ) internal virtual override returns (bool success) {
    result; // ssh
    IERC20 outTkn = IERC20(order.outbound_tkn);
    IERC20 inTkn = IERC20(order.inbound_tkn);
    OfferData memory od = offerData[outTkn][inTkn][order.offerId];
    // NB if several offers of `this` contract have failed during the market order, the balance of this contract on Mangrove will contain cumulated free provision

    // computing an under approximation of returned provision because of this offer's failure
    (P.Global.t global, P.Local.t local) = MGV.config(
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
    offerData[outTkn][inTkn][order.offerId] = OfferData({
      owner: od.owner,
      wei_balance: uint96(approxReturnedProvision) // previous wei_balance is always 0 here: if offer failed in the past, `updateOffer` did reuse it
    });
    success = true;
  }

  function __checkList__(IERC20 token) internal view virtual override {
    router().checkList(token, msg.sender);
    super.__checkList__(token);
  }
}
