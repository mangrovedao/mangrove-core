// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Forwarder, MangroveOffer} from "mgv_src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {IOrderLogic} from "mgv_src/strategies/interfaces/IOrderLogic.sol";
import {Permit2Router} from "mgv_src/strategies/routers/Permit2Router.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {MgvLib, IERC20} from "mgv_src/MgvLib.sol";

///@title MangroveOrder. A periphery contract to Mangrove protocol that implements "Good till cancelled" (GTC) orders as well as "Fill or kill" (FOK) orders.
///@notice A GTC order is a buy (sell) limit order complemented by a bid (ask) limit order, called a resting order, that occurs when the buy (sell) order was partially filled.
/// If the GTC is for some amount $a_goal$ at a price $p$, and the corresponding limit order was partially filled for $a_now < a_goal$,
/// the resting order should be posted for an amount $a_later = a_goal - a_now$ at price $p$.
///@notice A FOK order is simply a buy or sell limit order that is either completely filled or cancelled. No resting order is posted.
///@dev requiring no partial fill *and* a resting order is interpreted here as an instruction to revert if the resting order fails to be posted (e.g., if below density).

contract MangroveOrder is Forwarder, IOrderLogic {
  ///@notice `expiring[outbound_tkn][inbound_tkn][offerId]` gives timestamp beyond which `offerId` on the `(outbound_tkn, inbound_tkn)` offer list should renege on trade.
  ///@notice if the order tx is included after the expiry date, it reverts.
  ///@dev 0 means no expiry.
  mapping(IERC20 => mapping(IERC20 => mapping(uint => uint))) public expiring;

  ///@notice MangroveOrder is a Forwarder logic with a simple router.
  ///@param mgv The mangrove contract on which this logic will run taker and maker orders.
  ///@param permit2 The permit2 contract
  ///@param deployer The address of the admin of `this` at the end of deployment
  ///@param gasreq The gas required for `this` to execute `makerExecute` and `makerPosthook` when called by mangrove for a resting order.
  constructor(IMangrove mgv, IPermit2 permit2, address deployer, uint gasreq)
    Forwarder(mgv, new Permit2Router(permit2), gasreq)
  {
    // adding `this` contract to authorized makers of the router before setting admin rights of the router to deployer
    router().bind(address(this));
    router().setAdmin(deployer);
    // if `msg.sender` is not `deployer`, setting admin of `this` to `deployer`.
    // `deployer` will thus be able to call `activate` on `this` to enable trading on particular assets.
    if (msg.sender != deployer) {
      setAdmin(deployer);
    }
  }

  ///@notice The expiry of the offer has been set
  ///@param outbound_tkn the outbound token of the offer list.
  ///@param inbound_tkn the inbound token of the offer list.
  ///@param offerId the Mangrove offer id.
  ///@param date in seconds since unix epoch
  event SetExpiry(address indexed outbound_tkn, address indexed inbound_tkn, uint offerId, uint date);

  ///@inheritdoc IOrderLogic
  ///@dev We also allow Mangrove to call this so that it can part of an offer logic.
  function setExpiry(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, uint date)
    public
    mgvOrOwner(outbound_tkn, inbound_tkn, offerId)
  {
    expiring[outbound_tkn][inbound_tkn][offerId] = date;
    emit SetExpiry(address(outbound_tkn), address(inbound_tkn), offerId, date);
  }

  ///@notice updates an offer on Mangrove
  ///@dev this can be used to update price of the resting order
  ///@param outbound_tkn outbound token of the offer list
  ///@param inbound_tkn inbound token of the offer list
  ///@param wants new amount of `inbound_tkn` offer owner wants
  ///@param gives new amount of `outbound_tkn` offer owner gives
  ///@param pivotId pivot for the new rank of the offer
  ///@param offerId the id of the offer to be updated
  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId)
    external
    payable
    onlyOwner(outbound_tkn, inbound_tkn, offerId)
  {
    OfferArgs memory args;

    // funds to compute new gasprice is msg.value. Will use old gasprice if no funds are given
    args.fund = msg.value; // if inside a hook (Mangrove is `msg.sender`) this will be 0
    args.outbound_tkn = outbound_tkn;
    args.inbound_tkn = inbound_tkn;
    args.wants = wants;
    args.gives = gives;
    args.gasreq = offerGasreq();
    args.pivotId = pivotId;
    args.noRevert = false; // will throw if Mangrove reverts
    _updateOffer(args, offerId);
  }

  ///@notice Retracts an offer from an Offer List of Mangrove.
  ///@param outbound_tkn the outbound token of the offer list.
  ///@param inbound_tkn the inbound token of the offer list.
  ///@param offerId the identifier of the offer in the (`outbound_tkn`,`inbound_tkn`) offer list
  ///@param deprovision if set to `true` if offer owner wishes to redeem the offer's provision.
  ///@return freeWei the amount of native tokens (in WEI) that have been retrieved by retracting the offer.
  ///@dev An offer that is retracted without `deprovision` is retracted from the offer list, but still has its provisions locked by Mangrove.
  ///@dev Calling this function, with the `deprovision` flag, on an offer that is already retracted must be used to retrieve the locked provisions.
  function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
    public
    mgvOrOwner(outbound_tkn, inbound_tkn, offerId)
    returns (uint freeWei)
  {
    return _retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
  }

  ///Checks the current timestamps and reneges on trade (by reverting) if the offer has expired.
  ///@inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal virtual override returns (bytes32) {
    uint exp = expiring[IERC20(order.outbound_tkn)][IERC20(order.inbound_tkn)][order.offerId];
    require(exp == 0 || block.timestamp <= exp, "mgvOrder/expired");
    return super.__lastLook__(order);
  }

  ///@notice compares a taker order with a market order result and checks whether the order was entirely filled
  ///@param tko the taker order
  ///@param res the market order result
  ///@return true if the order was entirely filled, false otherwise.
  function checkCompleteness(TakerOrder calldata tko, TakerOrderResult memory res) internal pure returns (bool) {
    // The order can be incomplete if the price becomes too high or the end of the book is reached.
    if (tko.fillWants) {
      // when fillWants is true, the market order stops when `takerWants` units of `outbound_tkn` have been obtained (minus potential fees);
      return res.takerGot + res.fee >= tko.takerWants;
    } else {
      // otherwise, the market order stops when `takerGives` units of `inbound_tkn` have been sold.
      return res.takerGave >= tko.takerGives;
    }
  }

  //@notice pull inbound_tkn from the msg.sender with permit and then the forward market order to MGV
  //@param outbound_tkn outbound_tkn
  //@param inbound_tkn inbound_tkn
  //@param takerWants Amount of outbound_tkn taker wants
  //@param takerGives Amount of inbound_tkn taker gives
  //@param fillWants isBid
  //@param permit The permit data signed over by the owner
  //@param signature The signature to verify
  //@return totalGot Amount of outbound_tkn received
  //@return totalGave Amount of inbound_tkn received
  //@return totalPenalty Penalty received
  //@return feePaid Fee paid
  function marketOrderWithTransferApproval(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint takerWants,
    uint takerGives,
    bool fillWants,
    ISignatureTransfer.PermitTransferFrom calldata permit,
    bytes calldata signature
  ) external returns (uint totalGot, uint totalGave, uint totalPenalty, uint feePaid) {
    uint pulled = Permit2Router(address(router())).pull(inbound_tkn, msg.sender, takerGives, true, permit, signature);
    require(pulled == takerGives, "mgvOrder/transferInFail");
    (totalGot, totalGave, totalPenalty, feePaid) =
      MGV.marketOrder(address(outbound_tkn), address(inbound_tkn), takerWants, takerGives, fillWants);

    uint fund = takerGives - totalGave;
    if (fund > 0) {
      // refund the sender
      (bool noRevert,) =
        address(router()).call(abi.encodeWithSelector(router().push.selector, inbound_tkn, msg.sender, fund));
      require(noRevert, "mgvOrder/refundInboundTknFail");
    }
  }

  //@param tko TakerOrder struct
  function __take__(TakerOrder calldata tko) internal returns (TakerOrderResult memory res) {
    // Checking whether order is expired
    require(tko.expiryDate == 0 || block.timestamp <= tko.expiryDate, "mgvOrder/expired");

    // Notations:
    // NAT_USER: initial value of `msg.sender.balance` (native balance of user)
    // OUT/IN_USER: initial value of `tko.[out|in]bound_tkn.balanceOf(reserve(msg.sender))` (user's reserve balance of tokens)
    // NAT_THIS: initial value of `address(this).balance` (native balance of `this`)
    // OUT/IN_THIS: initial value of `tko.[out|in]bound_tkn.balanceOf(address(this))` (`this` balance of tokens)

    // PRE:
    // * User balances: (NAT_USER -`msg.value`, OUT_USER, IN_USER)
    // * `this` balances: (NAT_THIS +`msg.value`, OUT_THIS, IN_THIS)

    // Pulling funds from `msg.sender`'s reserve
    uint pulled = router().pull(tko.inbound_tkn, msg.sender, tko.takerGives, true);
    require(pulled == tko.takerGives, "mgvOrder/transferInFail");

    // POST:
    // * (NAT_USER-`msg.value`, OUT_USER, IN_USER-`tko.takerGives`)
    // * (NAT_THIS+`msg.value`, OUT_THIS, IN_THIS+`tko.takerGives`)

    (res.takerGot, res.takerGave, res.bounty, res.fee) = MGV.marketOrder({
      outbound_tkn: address(tko.outbound_tkn),
      inbound_tkn: address(tko.inbound_tkn),
      takerWants: tko.takerWants,
      takerGives: tko.takerGives,
      fillWants: tko.fillWants
    });

    // POST:
    // * (NAT_USER-`msg.value`, OUT_USER, IN_USER-`tko.takerGives`)
    // * (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS+`res.takerGot`, IN_THIS+`tko.takerGives`-`res.takerGave`)

    bool isComplete = checkCompleteness(tko, res);
    // when `!restingOrder` this implements FOK. When `restingOrder` the `postRestingOrder` function reverts if resting order fails to be posted and `fillOrKill`.
    // therefore we require `fillOrKill => (isComplete \/ restingOrder)`
    require(!tko.fillOrKill || isComplete || tko.restingOrder, "mgvOrder/partialFill");

    // sending inbound tokens to `msg.sender`'s reserve and sending back remaining outbound tokens
    if (res.takerGot > 0) {
      require(router().push(tko.outbound_tkn, msg.sender, res.takerGot) == res.takerGot, "mgvOrder/pushFailed");
    }
    uint inboundLeft = tko.takerGives - res.takerGave;
    if (inboundLeft > 0) {
      require(router().push(tko.inbound_tkn, msg.sender, inboundLeft) == inboundLeft, "mgvOrder/pushFailed");
    }
    // POST:
    // * (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
    // * (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS, IN_THIS)

    ///@dev collected bounty compensates gas consumption for the failed offer, but could be lower than the cost of an additional native token transfer
    /// instead of sending the bounty back to `msg.sender` we recycle it into the resting order's provision (so `msg.sender` can retrieve it when deprovisioning).
    /// corner case: if the bounty is large enough, this will make posting of the resting order fail because of `gasprice` overflow.
    /// The funds will then be sent back to `msg.sender` (see below).
    uint fund = msg.value + res.bounty;

    if ( // resting order is:
      tko.restingOrder // required
        && !isComplete // needed
    ) {
      // When posting a resting order `msg.sender` becomes a maker.
      // For maker orders, outbound tokens are what makers send. Here `msg.sender` sends `tko.inbound_tkn`.
      // The offer list on which this contract must post `msg.sender`'s resting order is thus `(tko.inbound_tkn, tko.outbound_tkn)`
      // the call below will fill the memory data `res`.
      fund =
        postRestingOrder({tko: tko, outbound_tkn: tko.inbound_tkn, inbound_tkn: tko.outbound_tkn, res: res, fund: fund});
      // POST (case `postRestingOrder` succeeded):
      // * (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // * (NAT_THIS, OUT_THIS, IN_THIS)
      // * `fund == 0`
      // * `ownerData[tko.inbound_tkn][tko.outbound_tkn][res.offerId].owner == msg.sender`.
      // * Mangrove emitted an `OfferWrite` log whose `maker` field is `address(this)` and `offerId` is `res.offerId`.

      // POST (case `postRestingOrder` failed):
      // * (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // * (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS, IN_THIS)
      // * `fund == msg.value + res.bounty`.
      // * `res.offerId == 0`
    }

    if (fund > 0) {
      // NB this calls gives reentrancy power to callee, but OK since:
      // 1. callee is `msg.sender` so no griefing risk of making this call fail for out of gas
      // 2. w.r.t reentrancy for profit:
      // * from POST above a reentrant call would entail either:
      //   - `fund == 0` (no additional funds transferred)
      //   - or `fund == msg.value + res.bounty` with `msg.value` being from reentrant call and `res.bounty` from a second resting order.
      // Thus no additional fund can be redeemed by caller using reentrancy.
      (bool noRevert,) = msg.sender.call{value: fund}("");
      require(noRevert, "mgvOrder/refundFail");
    }
    // POST (case `postRestingOrder` succeeded)
    // * (NAT_USER, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
    // * (NAT_THIS, OUT_THIS, IN_THIS)
    // POST (else)
    // * (NAT_USER+`res.bounty`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
    // * (NAT_THIS, OUT_THIS, IN_THIS)
    logOrderData(tko, res);
    return res;
  }

  //@inheritdoc IOrderLogic
  //@param tko TakerOrder struct
  //@return TakerOrderResult Result of the take call
  function take(TakerOrder calldata tko) external payable returns (TakerOrderResult memory) {
    return __take__(tko);
  }

  //@notice call permit2 permit and then call take, this can be used to first approve and then take
  //@param tko TakerOrder struct
  //@param permit The permit data signed over by the owner
  //@param signature The signature to verify
  //@return TakerOrderResult Result of the take call
  function takeWithPermit(
    TakerOrder calldata tko,
    IAllowanceTransfer.PermitSingle memory permit,
    bytes calldata signature
  ) external payable returns (TakerOrderResult memory) {
    Permit2Router(address(router())).permit2().permit(msg.sender, permit, signature);
    return __take__(tko);
  }

  ///@notice logs `OrderSummary`
  ///@param tko the arguments in memory of the taker order
  ///@param res the result of the taker order.
  ///@dev this function avoids loading too many variables on the stack
  function logOrderData(TakerOrder memory tko, TakerOrderResult memory res) internal {
    emit OrderSummary({
      mangrove: MGV,
      outbound_tkn: tko.outbound_tkn,
      inbound_tkn: tko.inbound_tkn,
      taker: msg.sender,
      fillOrKill: tko.fillOrKill,
      takerWants: tko.takerWants,
      takerGives: tko.takerGives,
      fillWants: tko.fillWants,
      restingOrder: tko.restingOrder,
      expiryDate: tko.expiryDate,
      takerGot: res.takerGot,
      takerGave: res.takerGave,
      bounty: res.bounty,
      fee: res.fee,
      restingOrderId: res.offerId
    });
  }

  ///@notice posts a maker order on the (`outbound_tkn`, `inbound_tkn`) offer list.
  ///@param tko the arguments in memory of the taker order
  ///@param outbound_tkn the outbound token of the offer to post
  ///@param inbound_tkn the inbound token of the offer to post
  ///@param fund amount of WEIs used to cover for the offer bounty (covered gasprice is derived from `fund`).
  ///@param res the result of the taker order.
  ///@return refund the amount to refund to the taker of the fund.
  ///@dev entailed price that should be preserved for the maker order are:
  /// * `tko.takerGives/tko.takerWants` for buy orders (i.e `fillWants==true`)
  /// * `tko.takerWants/tko.takerGives` for sell orders (i.e `fillWants==false`)
  function postRestingOrder(
    TakerOrder calldata tko,
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    TakerOrderResult memory res,
    uint fund
  ) internal returns (uint refund) {
    uint residualWants;
    uint residualGives;
    if (tko.fillWants) {
      // partialFill => tko.takerWants > res.takerGot + res.fee
      residualWants = tko.takerWants - (res.takerGot + res.fee);
      // adapting residualGives to match initial price
      residualGives = (residualWants * tko.takerGives) / tko.takerWants;
    } else {
      // partialFill => tko.takerGives > res.takerGave
      residualGives = tko.takerGives - res.takerGave;
      // adapting residualGives to match initial price
      residualWants = (residualGives * tko.takerWants) / tko.takerGives;
    }
    (res.offerId,) = _newOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: residualWants,
        gives: residualGives,
        gasreq: offerGasreq(), // using default gasreq of the strat
        gasprice: 0, // ignored
        pivotId: tko.pivotId,
        fund: fund,
        noRevert: true // returns 0 when MGV reverts
      }),
      msg.sender
    );
    if (res.offerId == 0) {
      // either:
      // - residualGives is below current density
      // - `fund` is too low and would yield a gasprice that is lower than Mangrove's
      // - `fund` is too high and would yield a gasprice overflow
      // - offer list is not active (Mangrove is not dead otherwise market order would have reverted)
      // reverting when partial fill is not an option
      require(!tko.fillOrKill, "mgvOrder/partialFill");
      // `fund` is no longer needed so sending it back to `msg.sender`
      refund = fund;
    } else {
      // offer was successfully posted
      // `fund` was used and we leave `refund` at 0.

      // setting expiry date for the resting order
      if (tko.expiryDate > 0) {
        setExpiry(outbound_tkn, inbound_tkn, res.offerId, tko.expiryDate);
      }
      // if one wants to maintain an inverse mapping owner => offerIds
      __logOwnershipRelation__({
        owner: msg.sender,
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        offerId: res.offerId
      });
    }
  }

  /**
   * @notice This is invoked for each new offer created for resting orders, e.g., to maintain an inverse mapping from owner to offers.
   * @param owner the owner of the new offer
   * @param outbound_tkn the outbound token used to identify the order book
   * @param inbound_tkn the inbound token used to identify the order book
   * @param offerId the id of the new offer
   */
  function __logOwnershipRelation__(address owner, IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId)
    internal
    virtual
  {
    owner; //ssh
    outbound_tkn; //ssh
    inbound_tkn; //ssh
    offerId; //ssh
  }
}
