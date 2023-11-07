// SPDX-License-Identifier: BUSL-1.1

/* `MgvCommon` and its descendants describe an orderbook-based exchange ("Mangrove") where market makers *do not have to provision their offer*. In a nutshell: each offer created by a maker specifies an address (`maker`) to call upon offer execution by a taker. When an offer is executed, Mangrove transfers the amount to be paid by the taker to the maker, calls the maker, attempts to transfer the amount promised by the maker to the taker, and reverts if it cannot.
 */

pragma solidity ^0.8.10;

import "@mgv/src/core/MgvLib.sol";

/* `MgvCommon` contains state variables used everywhere in the operation of Mangrove and related gatekeeping functions. The main `Mangrove` contract inherits from `MgvCommon`, and the auxiliary `MgvAppendix` contract inherits from `MgvCommon` as well. This way, when `Mangrove` delegatecalls to `MgvAppendix`, the storage slots match. */
contract MgvCommon is HasMgvEvents {
  /* # State variables */
  //+clear+

  /* The `governance` address. Governance is the only address that can configure parameters. */
  address public governance;

  /* Global mgv configuration, encoded in a 256 bits word. The information encoded is detailed in [`structs.js`](#structs.js). */
  Global internal internal_global;

  /* `OfferData` contains all the information related to an offer. Each field contains packed information such as the volumes and the gas required. See [`structs.js`](#structs.js) for more information. */
  struct OfferData {
    Offer offer;
    OfferDetail detail;
  }

  /* `OfferList` contains all data specific to an offer list. */
  struct OfferList {
    /* `local` is the Mangrove configuration specific to the `outbound,inbound,tickSpacing` offer list. It contains e.g. the minimum offer `density`. It contains packed information, see [`structs.js`](#structs.js) for more.*/
    Local local;
    /* `level1s` maps a level1 index to a (dirty) field. Each field holds 64 bits marking the (non)empty state of 64 level2 fields. */
    mapping(int => DirtyField) level1s;
    /* `level2s` maps a level2 index to a (dirty) field. Each field holds 64 bits marking the (non)empty state of 64 level3 fields. */
    mapping(int => DirtyField) level2s;
    /* `level3s` maps a level3 index to a (dirty) field. Each field holds 64 bits marking the (non)empty state of 64 leaves. */
    mapping(int => DirtyField) level3s;
    /* `leafs` (intentionally not `leaves` for clarity) maps a leaf index to a leaf. Each leaf holds the first&last offer id of 4 bins. */
    mapping(int => DirtyLeaf) leafs;
    /* OfferData maps an offer id to a struct that holds the two storage words where the packed offer information resides. For more information see `Offer` and `OfferDetail`. */
    mapping(uint => OfferData) offerData;
  }

  /* OLKeys (see `MgvLib.sol`) are hashed to a bytes32 OLKey identifier, which get mapped to an `OfferList` struct. Having a single mapping instead of one mapping per field in `OfferList` means we can pass around a storage reference to that struct. */
  mapping(bytes32 => OfferList) internal offerLists;
  /* For convenience, and to enable future functions that access offer lists by directly supplying an OLKey identifier, Mangrove maintains an inverse `id -> key` mapping. */
  mapping(bytes32 => OLKey) internal _olKeys;

  /* Makers provision their possible penalties in the `balanceOf` mapping.

       Offers specify the amount of gas they require for successful execution ([`gasreq`](#structs.js/gasreq)). To minimize book spamming, market makers must provision an amount of native tokens that depends on their `gasreq` and on the offer list's [`offer_gasbase`](#structs.js/gasbase). This provision is deducted from their `balanceOf`. If an offer fails, part of that provision is given to the taker as a `penalty`. The exact amount depends on the gas used by the offer before failing and during the execution of its posthook.

       Mangrove keeps track of available balances in the `balanceOf` map, which is decremented every time a maker creates a new offer, and may be modified on offer updates/cancellations/takings.
     */
  mapping(address maker => uint balance) internal _balanceOf;

  /*
  # Gatekeeping

  Gatekeeping functions are safety checks called in various places.
  */

  /* `unlockedOfferListOnly` protects modifying the offer list while an order is in progress. Since external contracts are called during orders, allowing reentrancy would, for instance, let a market maker replace offers currently on the book with worse ones. Note that the external contracts _will_ be called again after the order is complete, this time without any lock on the offer list.  */
  function unlockedOfferListOnly(Local local) internal pure {
    require(!local.lock(), "mgv/reentrancyLocked");
  }

  /* <a id="Mangrove/definition/liveMgvOnly"></a>
     In case of emergency, Mangrove can be `kill`ed. It cannot be resurrected. When a Mangrove is dead, the following operations are disabled :
       * Executing an offer
       * Sending ETH to Mangrove the normal way. Usual [shenanigans](https://medium.com/@alexsherbuck/two-ways-to-force-ether-into-a-contract-1543c1311c56) are possible.
       * Creating a new offer
   */
  function liveMgvOnly(Global _global) internal pure {
    require(!_global.dead(), "mgv/dead");
  }

  /* When Mangrove is deployed, all offer lists are inactive by default (since `locals[outbound_tkn][inbound_tkn]` is 0 by default). Offers on inactive offer lists cannot be taken or created. They can be updated and retracted. */
  function activeOfferListOnly(Global _global, Local _local) internal pure {
    liveMgvOnly(_global);
    require(_local.active(), "mgv/inactive");
  }

  /* _config is the lower-level variant which opportunistically returns a pointer to the storage offer list induced by (`outbound_tkn,inbound_tkn,tickSpacing`). */
  function _config(OLKey memory olKey)
    internal
    view
    returns (Global _global, Local _local, OfferList storage offerList)
  {
    unchecked {
      offerList = offerLists[olKey.hash()];
      _global = internal_global;
      _local = offerList.local;
      if (_global.useOracle()) {
        (uint gasprice, Density density) = IMgvMonitor(_global.monitor()).read(olKey);
        /* Gas gasprice can be ignored by making sure the oracle's set gasprice does not pass the check below. */
        if (GlobalLib.gasprice_check(gasprice)) {
          _global = _global.gasprice(gasprice);
        }
        /* Oracle density can be ignored by making sure the oracle's set density does not pass the checks below. */

        /* Checking the size of `density` is necessary to prevent overflow when `density` is used in calculations. */

        if (LocalLib.density_check(density)) {
          _local = _local.density(density);
        }
      }
    }
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

  /* # Permit-related functionality */

  /* Takers may provide allowances on specific offer lists, so other addresses can execute orders in their name. Allowance may be set using the usual `approve` function, or through an [EIP712](https://eips.ethereum.org/EIPS/eip-712) `permit`.

  The mapping is `outbound_tkn => inbound_tkn => owner => spender => allowance`. There is no `tickSpacing` specified since we assume the natural semantics of a permit are "`spender` has the right to trade token A against token B at any tickSpacing". */
  mapping(
    address outbound_tkn
      => mapping(address inbound_tkn => mapping(address owner => mapping(address spender => uint allowance)))
  ) internal _allowance;
  /* Storing nonces avoids replay attacks. */
  mapping(address owner => uint nonce) internal _nonces;

  /* Following [EIP712](https://eips.ethereum.org/EIPS/eip-712), structured data signing has `keccak256("Permit(address outbound_tkn,address inbound_tkn,address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")` in its prefix. */
  bytes32 internal constant _PERMIT_TYPEHASH = 0xf0ea0a7146fb6eedb561d97b593d57d9b7df3c94d689372dc01302e5780248f4;
  /* If you are looking for `DOMAIN_SEPARATOR`, it is defined in `MgvOfferTakingWithPermit`.

  If you define an immutable C, you must initialize it in the constructor of C, unless you use solidity >= 0.8.21. Then you can initialize it in the constructor of a contract that inherits from C. At the time of the writing 0.8.21 is too recent so we move `DOMAIN_SEPARATOR` to `MgvOfferTakingWithPermit`, which has a constructor and also initializes `DOMAIN_SEPARATOR`. */
}
