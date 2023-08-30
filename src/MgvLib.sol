// SPDX-License-Identifier: Unlicense

/* `MgvLib` contains data structures returned by external calls to Mangrove and the interfaces it uses for its own external calls. */

pragma solidity ^0.8.10;

import "./preprocessed/MgvStructs.post.sol" as MgvStructs;
import {IERC20} from "./IERC20.sol";
import {Density, DensityLib} from "mgv_lib/DensityLib.sol";
import "mgv_lib/TickLib.sol";

using OLLib for OLKey global;
// OLKey is OfferList

struct OLKey {
  address outbound;
  address inbound;
  uint tickScale;
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
    /* `wants`/`gives` mutate over execution. Initially the `wants`/`gives` from the taker's pov, then actual `wants`/`gives` adjusted by offer's price and volume. */
    uint wants;
    uint gives;
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
    int logPrice;
    uint gasreq;
    uint takerWants;
  }
}

/* # Events
The events emitted for use by bots are listed here: */
contract HasMgvEvents {
  /* * Emitted at the creation of the new Mangrove contract */
  event NewMgv();

  /* Mangrove adds or removes wei from `maker`'s account */
  /* * Credit event occurs when an offer is removed from Mangrove or when the `fund` function is called*/
  event Credit(address indexed maker, uint amount);
  /* * Debit event occurs when an offer is posted or when the `withdraw` function is called */
  event Debit(address indexed maker, uint amount);

  /* * Mangrove reconfiguration */
  event SetActive(bytes32 indexed olKeyHash, bool value);
  event SetFee(bytes32 indexed olKeyHash, uint value);
  event SetGasbase(bytes32 indexed olKeyHash, uint offer_gasbase);
  event SetGovernance(address value);
  event SetMonitor(address value);
  event SetUseOracle(bool value);
  event SetNotify(bool value);
  event SetGasmax(uint value);
  event SetDensityFixed(bytes32 indexed olKeyHash, uint value);
  event SetGasprice(uint value);

  /* Clean order execution */
  event CleanStart(bytes32 indexed olKeyHash, address indexed taker);
  event CleanOffer(uint indexed offerId, address indexed taker, int logPrice, uint gasreq, uint takerWants);

  /* Market order execution */
  // FIXME: This provides the basis information for all following events
  // FIXME: Observation: All other events follow from this one + the known state of the book
  event OrderStart(bytes32 indexed olKeyHash, address indexed taker, int maxLogPrice, uint fillVolume, bool fillWants);
  // FIXME: got, gave, bounty, and fee can be derived from previous events.
  // FIXME: Well, fees aren't actually explicitly included in any event... Could be included here or in OfferSuccess
  event OrderComplete(uint fee);

  /* * Offer execution */
  event OfferSuccess( // FIXME: Included since consumers cannot be assumed to know the maker
    // FIXME: id could be inferred by indexing the book and simply walking it.
    // FIXME: The same goes for this and takerGave, since we can simulate the trade.
  address indexed maker, uint id, uint takerGot, uint takerGave);
  // FIXME: Include fee?

  /* Log information when a trade execution reverts or returns a non empty bytes32 word */
  event OfferFail(
    address indexed maker,
    uint id,
    uint takerWants,
    uint takerGives,
    // uint penalty, // FIXME: Putting this here requires emitting the event later, as we don't know the penalty until after the posthook has executed
    // `mgvData` may only be `"mgv/makerRevert"`, `"mgv/makerTransferFail"` or `"mgv/makerReceiveFail"`
    bytes32 mgvData
  );

  event OfferPenalty(uint penalty); // FIXME: The offer id can be inferred from the preceding OfferFail event

  /* Log information when a posthook reverts */
  event PosthookFail(bytes32 posthookData); // FIXME: The offer id can be inferred from the preceding OfferFail event

  /* * After `permit` and `approve` */
  event Approval(address indexed outbound_tkn, address indexed inbound_tkn, address owner, address spender, uint value);

  /* * Mangrove closure */
  event Kill();

  /* * An offer was created or updated.
  A few words about why we include a `prev` field, and why we don't include a
  `next` field: in theory clients should need neither `prev` nor a `next` field.
  They could just 1. Read the order book state at a given block `b`.  2. On
  every event, update a local copy of the orderbook.  But in practice, we do not
  want to force clients to keep a copy of the *entire* orderbook. There may be a
  long tail of spam. Now if they only start with the first $N$ offers and
  receive a new offer that goes to the end of the book, they cannot tell if
  there are missing offers between the new offer and the end of the local copy
  of the book.
  
  So we add a prev pointer so clients with only a prefix of the book can receive
  out-of-prefix offers and know what to do with them. The `next` pointer is an
  optimization useful in Solidity (we traverse fewer memory locations) but
  useless in client code.
  */
  event OfferWrite(
    bytes32 indexed olKeyHash, address indexed maker, int logPrice, uint gives, uint gasprice, uint gasreq, uint id
  );

  /* * `offerId` was present and is now removed from the book. */
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
