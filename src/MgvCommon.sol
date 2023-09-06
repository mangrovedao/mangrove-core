// SPDX-License-Identifier: BUSL-1.1

/* `MgvCommon` and its descendants describe an orderbook-based exchange ("Mangrove") where market makers *do not have to provision their offer*. See `structs.js` for a longer introduction. In a nutshell: each offer created by a maker specifies an address (`maker`) to call upon offer execution by a taker. In the normal mode of operation, Mangrove transfers the amount to be paid by the taker to the maker, calls the maker, attempts to transfer the amount promised by the maker to the taker, and reverts if it cannot.

   There is one Mangrove contract that manages all tradeable offerLists. This reduces deployment costs for new offerLists and lets market makers have all their provision for all offerLists in the same place.

   The interaction map between the different actors is as follows:
   <img src="./contactMap.png" width="190%"></img>

   The sequence diagram of a market order is as follows:
   <img src="./sequenceChart.png" width="190%"></img>

   There is a secondary mode of operation in which the _maker_ flashloans the sold amount to the taker.

   The Mangrove contract is `abstract` and accomodates both modes. Two contracts, `Mangrove` and `InvertedMangrove` inherit from it, one per mode of operation.

   The contract structure is as follows:
   <img src="./modular_mangrove.svg" width="180%"> </img>
 */

pragma solidity ^0.8.10;

import {MgvStructs, Field, OLKey, HasMgvEvents, Density, IMgvMonitor, IERC20, Leaf} from "./MgvLib.sol";

/* `MgvRoot` contains state variables used everywhere in the operation of Mangrove and their related function. */
contract MgvCommon is HasMgvEvents {
  /* The `governance` address. Governance is the only address that can configure parameters. */
  address public governance;

  /* # State variables */
  //+clear+

  /* Global mgv configuration, encoded in a 256 bits word. The information encoded is detailed in [`structs.js`](#structs.js). */
  MgvStructs.GlobalPacked internal internal_global;
  /* `OfferData` contains all the information related to an offer. Each field contains packed information such as the volumes and the gas requried. See [`structs.js`](#structs.js) for more information. */

  struct OfferData {
    MgvStructs.OfferPacked offer;
    MgvStructs.OfferDetailPacked detail;
  }
  /* `OfferList` contains the information specific to an oriented `outbound_tkn,inbound_tkn`, `tickScale` offerList:

    * `local` is the Mangrove configuration specific to the `outbound,inbound,tickScale` offerList. It contains e.g. the minimum offer `density`. It contains packed information, see [`structs.js`](#structs.js) for more.
    * `offerData` maps from offer ids to offer data.
  */

  /* Note that offers are structured into a tree with linked lists at its leves.
     The root is level2, has 256 level1 node children, each has 256 level0 node children, each has 256 leaves, each has 4 ticks (it holds the first and last offer of each tick's linked list).
     level2, level1 and level0 nodes are bitfield, a bit is set iff there is a tick set below them.
  */
  // FIXME rename OfferList to OLD (means OfferListData) or such
  struct OfferList {
    MgvStructs.LocalPacked local;
    mapping(uint => OfferData) offerData;
    mapping(int => Leaf) leafs;
    mapping(int => Field) level0;
    mapping(int => Field) level1;
    Field level2;
  }

  /* `offerLists` maps offer list id to offer list. */
  mapping(bytes32 => OfferList) internal offerLists;

  /* # State variables */
  /* Makers provision their possible penalties in the `balanceOf` mapping.

       Offers specify the amount of gas they require for successful execution ([`gasreq`](#structs.js/gasreq)). To minimize book spamming, market makers must provision a *penalty*, which depends on their `gasreq` and on the offerList's [`offer_gasbase`](#structs.js/gasbase). This provision is deducted from their `balanceOf`. If an offer fails, part of that provision is given to the taker, as retribution. The exact amount depends on the gas used by the offer before failing.

       The Mangrove keeps track of their available balance in the `balanceOf` map, which is decremented every time a maker creates a new offer, and may be modified on offer updates/cancellations/takings.
     */
  mapping(address maker => uint balance) internal _balanceOf;

  /*
  # Gatekeeping

  Gatekeeping functions are safety checks called in various places.
  */

  /* `unlockedMarketOnly` protects modifying the market while an order is in progress. Since external contracts are called during orders, allowing reentrancy would, for instance, let a market maker replace offers currently on the book with worse ones. Note that the external contracts _will_ be called again after the order is complete, this time without any lock on the market.  */
  function unlockedMarketOnly(MgvStructs.LocalPacked local) internal pure {
    require(!local.lock(), "mgv/reentrancyLocked");
  }

  /* <a id="Mangrove/definition/liveMgvOnly"></a>
     In case of emergency, Mangrove can be `kill`ed. It cannot be resurrected. When a Mangrove is dead, the following operations are disabled :
       * Executing an offer
       * Sending ETH to Mangrove the normal way. Usual [shenanigans](https://medium.com/@alexsherbuck/two-ways-to-force-ether-into-a-contract-1543c1311c56) are possible.
       * Creating a new offer
   */
  function liveMgvOnly(MgvStructs.GlobalPacked _global) internal pure {
    require(!_global.dead(), "mgv/dead");
  }

  /* When Mangrove is deployed, all offerLists are inactive by default (since `locals[outbound_tkn][inbound_tkn]` is 0 by default). Offers on inactive offerLists cannot be taken or created. They can be updated and retracted. */
  function activeMarketOnly(MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local) internal pure {
    liveMgvOnly(_global);
    require(_local.active(), "mgv/inactive");
  }

  /* This code exists in 2 copies one in Mangrove and one in MgvViewFns.
     We could have it only in Mangrove and get MgvViewFns to always call mgv.config but would be an extra call to mangrove for a lot of view functions, which can be avoided by just duplicating the code.
  */
  /* _config is the lower-level variant which opportunistically returns a pointer to the storage offer list induced by `outbound_tkn`,`inbound_tkn`. */
  function _config(OLKey memory olKey)
    internal
    view
    returns (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local, OfferList storage offerList)
  {
    unchecked {
      offerList = offerLists[olKey.hash()];
      _global = internal_global;
      _local = offerList.local;
      if (_global.useOracle()) {
        (uint gasprice, Density density) = IMgvMonitor(_global.monitor()).read(olKey);
        /* Gas gasprice can be ignored by making sure the oracle's set gasprice does not pass the check below. */
        if (MgvStructs.Global.gasprice_check(gasprice)) {
          _global = _global.gasprice(gasprice);
        }
        /* Oracle density can be ignored by making sure the oracle's set density does not pass the checks below. */

        /* Checking the size of `density` is necessary to prevent overflow when `density` is used in calculations. */

        if (MgvStructs.Local.density_check(density)) {
          _local = _local.density(density);
        }
      }
    }
  }
  // Also duplicated because MgvAppendix uses transferToken & we want to keep them together

  /* # Token transfer functions */
  /* `transferTokenFrom` is adapted from [existing code](https://soliditydeveloper.com/safe-erc20) and in particular avoids the
    "no return value" bug. It never throws and returns true iff the transfer was successful according to `tokenAddress`.

      Note that any spurious exception due to an error in Mangrove code will be falsely blamed on `from`.
    */
  function transferTokenFrom(address tokenAddress, address from, address to, uint value) internal returns (bool) {
    unchecked {
      bytes memory cd = abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value);
      (bool noRevert, bytes memory data) = tokenAddress.call(cd);
      return (noRevert && (data.length == 0 || abi.decode(data, (bool))));
    }
  }

  function transferToken(address tokenAddress, address to, uint value) internal returns (bool) {
    unchecked {
      bytes memory cd = abi.encodeWithSelector(IERC20.transfer.selector, to, value);
      (bool noRevert, bytes memory data) = tokenAddress.call(cd);
      return (noRevert && (data.length == 0 || abi.decode(data, (bool))));
    }
  }

  /* Permit-related functionality */

  /* Takers may provide allowances on specific offerLists, so other addresses can execute orders in their name. Allowance may be set using the usual `approve` function, or through an [EIP712](https://eips.ethereum.org/EIPS/eip-712) `permit`.

  The mapping is `outbound_tkn => inbound_tkn => owner => spender => allowance` */
  mapping(
    address outbound_tkn
      => mapping(address inbound_tkn => mapping(address owner => mapping(address spender => uint allowance)))
  ) internal _allowances;
  /* Storing nonces avoids replay attacks. */
  mapping(address owner => uint nonce) internal _nonces;

  /* Following [EIP712](https://eips.ethereum.org/EIPS/eip-712), structured data signing has `keccak256("Permit(address outbound_tkn,address inbound_tkn,address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")` in its prefix. */
  bytes32 internal constant _PERMIT_TYPEHASH = 0xf0ea0a7146fb6eedb561d97b593d57d9b7df3c94d689372dc01302e5780248f4;
  // If you are looking for DOMAIN_SEPARATOR, it is defined in MgvOfferTakingWithPermit
  // If you define an immutable C, you must initialize it in the constructor of C, unless you use solidity >= 0.8.21. Then you can initialize it in the constructor of a contract that inherits from C. At the time of the writing 0.8.21 is too recent so we move DOMAIN_SEPARATOR to the contract with a constructor that initializes DOMAIN_SEPARATOR.
}
