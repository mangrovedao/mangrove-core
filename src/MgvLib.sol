// SPDX-License-Identifier: Unlicense

/* `MgvLib` contains data structures returned by external calls to Mangrove and the interfaces it uses for its own external calls. */

pragma solidity ^0.8.10;

import "./preprocessed/MgvStructs.post.sol" as MgvStructs;
import {IERC20} from "./IERC20.sol";
import {Density, DensityLib} from "mgv_lib/DensityLib.sol";
import "mgv_lib/BinLib.sol";
import "mgv_lib/TickLib.sol";
import "mgv_lib/TickConversionLib.sol";

using OLLib for OLKey global;
// OLKey is OfferList

struct OLKey {
  address outbound;
  address inbound;
  uint tickSpacing;
}

library OLLib {
  // The id should be keccak256(abi.encode(olKey))
  // To save gas, id() directly hashes the memory (which matches the ABI encoding)
  // If the memory layout changes, this function must be updated
  function hash(OLKey memory olKey) internal pure returns (bytes32 _id) {
    assembly ("memory-safe") {
      _id := keccak256(olKey, 96)
    }
  }

  // Creates a flipped copy of the `olKey` with same `tickSpacing`.
  function flipped(OLKey memory olKey) internal pure returns (OLKey memory) {
    return OLKey(olKey.inbound, olKey.outbound, olKey.tickSpacing);
  }

  // Convert tick to bin according to olKey's tickSpacing
  function nearestBin(OLKey memory olKey, Tick _tick) internal pure returns (Bin) {
    return _tick.nearestBin(olKey.tickSpacing);
  }

  // Convert bin to tick according to olKey's tickSpacing
  function tick(OLKey memory olKey, Bin _bin) internal pure returns (Tick) {
    return _bin.tick(olKey.tickSpacing);
  }
}

/* # Structs
The structs defined in `structs.js` have their counterpart as solidity structs that are easy to manipulate for outside contracts / callers of view functions. */

library MgvLib {
  /*
   Some miscellaneous data types useful to `Mangrove` and external contracts */
  //+clear+

  /* `SingleOrder` holds data about an order-offer match in a struct. Used by `marketOrder` (and some of its nested functions) to avoid stack too deep errors. */
  struct SingleOrder {
    OLKey olKey;
    uint offerId;
    MgvStructs.OfferPacked offer;
    /* `wants`/`gives` mutate over execution. Initially the `wants`/`gives` from the taker's pov, then actual `wants`/`gives` adjusted by offer's ratio and volume. */
    uint takerWants;
    uint takerGives;
    /* `offerDetail` is only populated when necessary. */
    MgvStructs.OfferDetailPacked offerDetail;
    MgvStructs.GlobalPacked global;
    MgvStructs.LocalPacked local;
  }

  /* <a id="MgvLib/OrderResult"></a> `OrderResult` holds additional data for the maker and is given to them _after_ they fulfilled an offer. It gives them their own returned data from the previous call, and an `mgvData` specifying whether Mangrove encountered an error. */

  struct OrderResult {
    /* `makerdata` holds a message that was either returned by the maker or passed as revert message at the end of the trade execution*/
    bytes32 makerData;
    /* `mgvData` is an [internal Mangrove status code](#MgvOfferTaking/statusCodes) code. */
    bytes32 mgvData;
  }

  /* `CleanTarget` holds data about an offer that should be cleaned, i.e. made to fail by executing it with the specified volume. */
  struct CleanTarget {
    uint offerId;
    Tick tick;
    uint gasreq;
    uint takerWants;
  }
}

/* # Events
The events emitted for use by bots are listed here: */
interface HasMgvEvents {
  /* 
    Events in solidity is a hard thing to do in a optimal way. If you look at it as a purely gas efficient issue, you want to emit as few events as possible and with as few fields as possible. But as events also has to be usable for an off chain user, then doing this is not always the best solution.

    We tried to list the main points that we would like to do with events.

    1. Use as little gas as possible
    2. An indexer should be able to keep track of the state of Mangrove.
    3. Doing RPC calls directly, should be able to find offers and other information based on offerList, maker, taker, offer id, etc.

    These 3 points all have there own direction and it is therefore not possible to find a solution that is optimal for all 3 points.
    We have therefore tried to find a solution that is a good balance between the all 3 points.
  */

  /* * Emitted at the creation of the new Mangrove contract */
  event NewMgv();

  /* Mangrove adds or removes wei from `maker`'s account */
  /* 
    * Credit event occurs when an offer is removed from Mangrove or when the `fund` function is called
      This is emitted when a user's account on Mangrove is credited with some native funds, to be used as provision for offers.

      It emits the `maker`'s address and the `amount` credited

      The `maker` address is indexed so that we can filter on it when doing RPC calls.

      These are the scenarios where it can happen:

      - Fund Mangrove directly
      - Fund Mangrove when posting an offer
      - When updating an offer
        - Funding Mangrove or
        - the updated offer needs less provision, than it already has. Meaning the user gets credited the difference.
      - When retracting an offer and deprovisioning it. Meaning the user gets credited the provision that was locked by the offer.
      - When an offer fails. The remaining provision gets credited back to the maker

      A challenge for an indexer is to know how much provision each offer locks. With the current events, an indexer is going to have to know the liveness, gasreq and gasprice of the offer. If the offer is not live, then also know if it has been deprovisioned. And know what the gasbase of the offerList was when the offer was posted. With this information an indexer can calculate the exact provision locked by the offer.

      The indexer also cannot deduce what scenario the credit event happened. E.g., we don't know if the credit event happened because an offer failed or because the user simply funded Mangrove.
  */
  event Credit(address indexed maker, uint amount);
  /* '
    * Debit event occurs when an offer is posted or when the `withdraw` function is called 
      This is emitted when a user's account on Mangrove is debited with some native funds.

      It emits the `maker`'s address and the `amount` debited.

      The `maker` address is indexed so that we can filter on it when doing RPC calls.

      These are the scenarios where it can happen:

      - Withdraw funds from Mangrove directly
      - When posting an offer. The user gets debited the provision that the offer locks.
      - When updating an offer and it requires more provision that it already has. Meaning the user gets debited the difference.

      Same challenges as for Credit
  */
  event Debit(address indexed maker, uint amount);

  /* * Mangrove reconfiguration */
  /*  
  This event is emitted when an offerList is activated or deactivated. Meaning one half of a market is opened.

  It emits the `olKeyHash` and the boolean `value`. By emitting this, an indexer will be able to keep track of what offerLists are active and what their hash is.

  The `olKeyHash` and both token addresses are indexed, so that we can filter on it when doing RPC calls.
  */
  event SetActive(
    bytes32 indexed olKeyHash, address indexed outbound_tkn, address indexed inbound_tkn, uint tickSpacing, bool value
  );

  /*
  This event is emitted when the fee of an offerList is changed.

  It emits the `olKeyHash` and the `value`. By emitting this, an indexer will be able to keep track of what fee each offerList has.

  The `olKeyHash` is indexed, so that we can filter on it when doing RPC calls.
  */

  event SetFee(bytes32 indexed olKeyHash, uint value);

  /*
  This event is emitted when the gasbase of an offerList is changed.

  It emits the `olKeyHash` and the `offer_gasbase`. By emitting this, an indexer will be able to keep track of what gasbase each offerList has.

  The `olKeyHash` is indexed, so that we can filter on it when doing RPC calls.
  */
  event SetGasbase(bytes32 indexed olKeyHash, uint offer_gasbase);

  /*
  This event is emitted when the governance of Mangrove is set.

  It emits the `governance` address. By emitting this, an indexer will be able to keep track of what governance address Mangrove has.

  No fields are indexed as there is no need for RPC calls to filter on this.
  */
  event SetGovernance(address value);

  /*
  This event is emitted when the monitor address of Mangrove is set. Be aware that the address for Monitor is also the address for the oracle.

  It emits the `monitor` / `oralce` address. By emitting this, an indexer will be able to keep track of what monitor/oracle address Mangrove use.

  No fields are indexed as there is no need for RPC calls to filter on this.
  */
  event SetMonitor(address value);

  /*
  This event is emitted when the configuration for whether to use an oracle or not is set.

  It emits the `useOracle`, which is a boolean value, that controls whether or not Mangrove reads its `gasprice` and `density` from an oracle or uses its own local values. By emitting this, an indexer will be able to keep track of if Mangrove is using an oracle.

  No fields are indexed as there is no need for RPC calls to filter on this.
  */
  event SetUseOracle(bool value);

  /*
  This event is emitted when the configuration for notify on Mangrove is set.

  It emits a boolean value, to tell whether or not notify is active. By emitting this, an indexer will be able to keep track of whether or not Mangrove notifies the Monitor/Oracle when and offer is taken, either successfuly or not.

  No fields are indexed as there is no need for RPC calls to filter on this.
  */
  event SetNotify(bool value);

  /*
  This event is emitted when the gasmax of Mangrove is set.

  It emits the `gasmax`. By emitting this, an indexer will be able to keep track of what gasmax Mangrove has. Read more about Mangroves gasmax on [docs.mangrove.exchange](docs.mangrove.exchange)

  No fields are indexed as there is no need for RPC calls to filter on this.
  */
  event SetGasmax(uint value);

  /*
  This event is emitted when the density of an offerList is changed.

  It emits the `olKeyHash` and the `density`. By emitting this, an indexer will be able to keep track of what density each offerList has.

  The `olKeyHash` is indexed, so that we can filter on it when doing RPC calls.
  */
  event SetDensity96X32(bytes32 indexed olKeyHash, uint value);

  /*
  This event is emitted when the max recursion depth of Mangrove is set.

  It emits the max depth `value`. By emitting this, an indexer will be able to keep track of what max recursion depth Mangrove has. Read more about Mangroves max recursion depth on [docs.mangrove.exchange](docs.mangrove.exchange)
  */

  event SetMaxRecursionDepth(uint value);

  /*
  This event is emitted when the max gasreq for failing offers of Mangrove is set.

  It emits the max gasreq for failing offers `value`. By emitting this, an indexer will be able to keep track of what max gasreq for failing offers Mangrove has. Read more about Mangroves max gasreq for failing offers on [docs.mangrove.exchange](docs.mangrove.exchange)
  */
  event SetMaxGasreqForFailingOffers(uint value);

  /*
  This event is emitted when the gasprice of Mangrove is set.

  It emits the `gasprice`. By emitting this, an indexer will be able to keep track of what gasprice Mangrove has. Read more about Mangroves gasprice on [docs.mangrove.exchange](docs.mangrove.exchange)

  No fields are indexed as there is no need for RPC calls to filter on this.
  */
  event SetGasprice(uint value);
  /* Clean order execution */
  /*
  This event is emitted when a user tries to clean offers on Mangrove, using the build in clean functionality.

  It emits the `olKeyHash`, the `taker` address and `offersToBeCleaned`, which is the number of offers that should be cleaned. By emitting this event, an indexer can save what `offerList` the user is trying to clean and what `taker` is being used. 
  This way it can keep a context for the following events being emitted (Just like `OrderStart`). The `offersToBeCleaned` is emitted so that an indexer can keep track of how many offers the user tried to clean. 
  Combining this with the amount of `OfferFail` events emitted, then an indexer can know how many offers the user actually managed to clean. This could be used for analytics.

  The fields `olKeyHash` and `taker` are indexed, so that we can filter on them when doing RPC calls.
  */
  event CleanStart(bytes32 indexed olKeyHash, address indexed taker, uint offersToBeCleaned);

  /*
  This event is emitted when a Clean operation is completed.

  It does not emit any fields. This event is only needed in order to know that the clean operation is completed. This way an indexer can know exactly in what context we are in. 
  It could emit the total bounty received, but in order to know who got the bounty, an indexer would still be needed or we would have to emit the taker address as well, in order for an RPC call to find the data. 
  But an indexer would still be able to find this info, by collecting all the previous events. So we do not emit the bounty.
  */
  event CleanComplete();

  /* Market order execution */
  /*
  This event is emitted when a market order is started on Mangrove.

  It emits the `olKeyHash`, the `taker`, the `maxTick`, `fillVolume` and `fillWants`.

  The fields `olKeyHash` and `taker` are indexed, so that we can filter on them when doing RPC calls.

  By emitting this an indexer can keep track of what context the current market order is in. 
  E.g. if a user starts a market order and one of the offers taken also starts a market order, then we can in an indexer have a stack of started market orders and thereby know exactly what offerList the order is running on and the taker.

  By emitting `maxTick`, `fillVolume` and `fillWants`, we can now also know how much of the market order was filled and if it matches the ratio given. See OrderComplete for more.
  */
  event OrderStart(bytes32 indexed olKeyHash, address indexed taker, Tick maxTick, uint fillVolume, bool fillWants);

  /*
  This event is emitted when a market order is finished.

  It emits `olKeyHash`, the `taker` and the total `fee paid`. We need this event, in order to know that a market order is completed. This way an indexer can know exactly in what context we are in.
  The total `fee paid` for that market order, is needed, as we do not emit this any other places. The fields `olKeyHash` and `taker` is not needed for an indexer, but they are emitted and indexed in order for RPC calls to filter and find the fee.
  */
  event OrderComplete(bytes32 indexed olKeyHash, address indexed taker, uint fee);

  /* * Offer execution */
  /*
  This event is emitted when an offer is successfully taken. Meaning both maker and taker has gotten their funds.

  It emits the `olKeyHash`, `taker` address, the `offerId` and the `takerWants` and `takerGives` that the offer was taken at. 
  Just as for `OfferFail`, the `olKeyHash` and `taker` are not needed for an indexer to work, but are needed for RPC calls. 
  `olKeyHash` `taker` and `id` are indexed so that we can filter on them when doing RPC calls. As `maker` can be a strategy and not the actual owner, then we chose not to emit it here and to mark the field `id` indexed, 
  the strat should emit the relation between maker and offerId. This way you can still by RPC calls find the relevant offer successes
  So they are emitted and indexed for that reason. Just like `OfferFail` this event is emitted during posthook end, so it is emitted in reverse order compared to what order they are taken. 
  This event could be emitted at offer execution, but for consistency we emit it at posthook end.

  If the posthook of the offer fails. Then we emit `OfferSuccessWithPosthookData` instead of just `OfferSuccess`. This event has one extra field, which is the reason for the posthook failure. 
  By emitting the posthook data, an indexer can keep track of the reason posthook fails, this could for example be used for analytics.

  By emitting `offerId`, `wants` and `gives`, an indexer can keep track of whether the offer was partially or fully taken, by looking at the what the offer was posted at.
  */
  event OfferSuccess(
    bytes32 indexed olKeyHash, address indexed taker, uint indexed id, uint takerWants, uint takerGives
  );

  event OfferSuccessWithPosthookData(
    bytes32 indexed olKeyHash,
    address indexed taker,
    uint indexed id,
    uint takerWants,
    uint takerGives,
    bytes32 posthookData
  );

  /*
  This event is emitted when an offer fails, because of a maker error.

  It emits `olKeyHash`, `taker`, the `offerId`, the offers `wants`, `gives`, `penalty` and the `reason` for failure. 
  `olKeyHash` and `taker` are all fields that we do not need, in order for an indexer to work, as an indexer will be able the get that info from the former `OrderStart` and `OfferWrite` events. 
  But in order for RPC call to filter on this, we need to emit them. 
  `olKeyHash` `taker` and `id` are indexed so that we can filter on them when doing RPC calls. As `maker` can be a strategy and not the actual owner, then we chose to not emit it here and to mark the field `id` indexed, 
  the strat should emit the relation between maker and offerId. This way you can still by RPC calls find the relevant offer successes

  If the posthook of the offer fails. Then we emit `OfferFailWithPosthookData` instead of just `OfferFail`. 
  This event has one extra field, which is the reason for the posthook failure. By emitting the posthook data, an indexer can keep track of the reason posthook fails, this could for example be used for analytics.

  This event is emitted doring posthook end, we wait to emit this event to the end, because we need the information of `penalty`, which is only available at the end of the posthook. 
  This means that `OfferFail` events are emitted in reverse order, compared to what order they are taken. This is due to the way we handle posthooks. The same goes for `OfferSuccess`.

  By emitting this event, an indexer can keep track of, if an offer failed and thereby if the offer is live. 
  By emitting the wants and gives that the offer was taken with, then an indexer can keep track of these amounts, which could be useful for e.g. strategy manager, to know if their offers fail at a certain amount.
  */
  event OfferFail(
    bytes32 indexed olKeyHash,
    address indexed taker,
    uint indexed id,
    uint takerWants,
    uint takerGives,
    uint penalty,
    // `mgvData` may only be `"mgv/makerRevert"`, `"mgv/makerTransferFail"` or `"mgv/makerReceiveFail"`
    bytes32 mgvData
  );

  event OfferFailWithPosthookData(
    bytes32 indexed olKeyHash,
    address indexed taker,
    uint indexed id,
    uint takerWants,
    uint takerGives,
    uint penalty,
    // `mgvData` may only be `"mgv/makerRevert"`, `"mgv/makerTransferFail"` or `"mgv/makerReceiveFail"`
    bytes32 mgvData,
    bytes32 posthookData
  );

  /* 
  * After `permit` and `approve` 
    This is emitted when a user permits another address to use a certain amount of its funds to do market orders, or when a user revokes another address to use a certain amount of its funds.

    Approvals are based on the pair of outbound and inbound token. Be aware that it is not offerList bases, as an offerList also holds the tickspacing.

    We emit `outbound` token, `inbound` token, `owner`, msg.sender (`spender`), `value`. Where `owner` is the one who owns the funds, `spender` is the one who is allowed to use the funds and `value` is the amount of funds that is allowed to be used.

    Outbound, inbound and owner is indexed, this way one can filter on these fields when doing RPC calls. If we could somehow combine outbound and inbound into one field, then we could also index the spender.
  */
  event Approval(
    address indexed outbound_tkn, address indexed inbound_tkn, address indexed owner, address spender, uint value
  );

  /* * Mangrove closure */
  event Kill();

  /* * An offer was created or updated.
  This event is emitted when an offer is posted on Mangrove.

  It emits the `olKeyHash`, the `maker` address, the `tick`, the `gives`, the `gasprice`, `gasreq` and the offers `id`.

  By emitting the `olKeyHash` and `id`, an indexer will be able to keep track of each offer, because offerList and id together create a unique id for the offer. By emitting the `maker` address, we are able to keep track of who has posted what offer. The `tick` and `gives`, enables an indexer to know exactly how much an offer is willing to give and at what ratio, this could for example be used to calculate a return. The `gasprice` and `gasreq`, enables an indexer to calculate how much provision is locked by the offer, see `Credit` for more information.

  The fields `olKeyHash` and `maker` are indexed, so that we can filter on them when doing RPC calls.
  */
  event OfferWrite(
    bytes32 indexed olKeyHash, address indexed maker, int tick, uint gives, uint gasprice, uint gasreq, uint id
  );

  /*
  This event is emitted when a user retracts his offer.

  It emits the `olKeyHash`, the `maker` address, `offerId` and whether or not the user chose to `deprovision` the offer.

  By emitting this event an indexer knows whether or not an offer is live. And whether or not an offer is deprovisioned. This is important because we need to know this, when we try to calculate how much an offer locks in provision. See the description of `Credit` for more info.

  The `maker` is not needed for an indexer to work, but is needed for RPC calls, so it is emitted and indexed for that reason. The `olKeyHash` is only indexed because it is needed for RPC calls. 
  */
  event OfferRetract(bytes32 indexed olKeyHash, address indexed maker, uint id, bool deprovision);
}

/* # IMaker interface */
interface IMaker {
  /* Called upon offer execution. 
  - If the call throws, Mangrove will not try to transfer funds and the first 32 bytes of revert reason are passed to `makerPosthook` as `makerData`
  - If the call returns normally, returndata is passed to `makerPosthook` as `makerData` and Mangrove will attempt to transfer the funds.
  */
  function makerExecute(MgvLib.SingleOrder calldata order) external returns (bytes32);

  /* Called after all offers of an order have been executed. Posthook of the last executed order is called first and full reentrancy into Mangrove is enabled at this time. `order` recalls key arguments of the order that was processed and `result` recalls important information for updating the current offer. (see [above](#MgvLib/OrderResult))*/
  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) external;
}

/* # ITaker interface */
interface ITaker {
  /* Inverted mangrove only: call to taker after loans went through */
  function takerTrade(
    OLKey calldata olKey,
    // total amount of outbound_tkn token that was flashloaned to the taker
    uint totalGot,
    // total amount of inbound_tkn token that should be made available
    uint totalGives
  ) external;
}

/* # Monitor interface
If enabled, the monitor receives notification after each offer execution and is read for each offerList's `gasprice` and `density`. */
interface IMgvMonitor {
  function notifySuccess(MgvLib.SingleOrder calldata sor, address taker) external;

  function notifyFail(MgvLib.SingleOrder calldata sor, address taker) external;

  function read(OLKey memory olKey) external view returns (uint gasprice, Density density);
}
