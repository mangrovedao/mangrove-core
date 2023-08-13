// SPDX-License-Identifier: BUSL-1.1

/* `MgvRoot` and its descendants describe an orderbook-based exchange ("Mangrove") where market makers *do not have to provision their offer*. See `structs.js` for a longer introduction. In a nutshell: each offer created by a maker specifies an address (`maker`) to call upon offer execution by a taker. In the normal mode of operation, Mangrove transfers the amount to be paid by the taker to the maker, calls the maker, attempts to transfer the amount promised by the maker to the taker, and reverts if it cannot.

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

import {MgvLib, HasMgvEvents, IMgvMonitor, MgvStructs, IERC20, Leaf, Field, Density, OLKey} from "./MgvLib.sol";
import "mgv_lib/Debug.sol";

/* `MgvRoot` contains state variables used everywhere in the operation of Mangrove and their related function. */
contract MgvRoot is HasMgvEvents {
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
  }

  /* `offerLists` maps offer list id to offer list. */
  mapping(bytes32 => OfferList) internal offerLists;

  function leafs(OLKey memory olKey, int index) external view returns (Leaf) {
    return offerLists[olKey.hash()].leafs[index];
  }

  function level0(OLKey memory olKey, int index) external view returns (Field) {
    OfferList storage offerList = offerLists[olKey.hash()];
    MgvStructs.LocalPacked local = offerList.local;

    if (local.tick().level0Index() == index) {
      return local.level0();
    } else {
      return offerList.level0[index];
    }
  }

  function level1(OLKey memory olKey, int index) external view returns (Field) {
    OfferList storage offerList = offerLists[olKey.hash()];
    MgvStructs.LocalPacked local = offerList.local;

    if (local.tick().level1Index() == index) {
      return local.level1();
    } else {
      return offerList.level1[index];
    }
  }

  function level2(OLKey memory olKey) external view returns (Field) {
    return offerLists[olKey.hash()].local.level2();
  }

  /* Checking the size of `gasprice` is necessary to prevent a) data loss when `gasprice` is copied to an `OfferDetail` struct, and b) overflow when `gasprice` is used in calculations. */
  function checkGasprice(uint gasprice) internal pure returns (bool) {
    unchecked {
      return uint16(gasprice) == gasprice;
    }
  }

  /* # Configuration Reads */
  /* Reading the configuration for an offer list involves reading the config global to all offerLists and the local one. In addition, a global parameter (`gasprice`) and a local one (`density`) may be read from the oracle. */
  function config(OLKey memory olKey)
    public
    view
    returns (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local)
  {
    unchecked {
      (_global, _local,) = _config(olKey);
    }
  }

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
        if (checkGasprice(gasprice)) {
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

  /* Returns the configuration in an ABI-compatible struct. Should not be called internally, would be a huge memory copying waste. Use `config` instead. */
  function configInfo(OLKey memory olKey)
    external
    view
    returns (MgvStructs.GlobalUnpacked memory global, MgvStructs.LocalUnpacked memory local)
  {
    unchecked {
      (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local) = config(olKey);
      global = _global.to_struct();
      local = _local.to_struct();
    }
  }

  /* Convenience function to check whether given an offer list is locked */
  function locked(OLKey memory olKey) external view returns (bool) {
    return offerLists[olKey.hash()].local.lock();
  }

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
}
