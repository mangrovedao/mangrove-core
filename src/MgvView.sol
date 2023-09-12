// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvStructs, IERC20, Leaf, Field, OLKey} from "./MgvLib.sol";
import "mgv_src/MgvCommon.sol";

// Contains view functions, to reduce Mangrove contract size
contract MgvView is MgvCommon {
  /* # Configuration Reads */
  /* Reading the configuration for an offer list involves reading the config global to all offerLists and the local one. In addition, a global parameter (`gasprice`) and a local one (`density`) may be read from the oracle. */
  function config(OLKey memory olKey)
    external
    view
    returns (MgvStructs.GlobalPacked _global, MgvStructs.LocalPacked _local)
  {
    unchecked {
      (_global, _local,) = _config(olKey);
      unlockedMarketOnly(_local);
    }
  }

  /* Sugar for getting only local config */
  function local(OLKey memory olKey) external view returns (MgvStructs.LocalPacked _local) {
    unchecked {
      (, _local,) = _config(olKey);
      unlockedMarketOnly(_local);
    }
  }

  /* Reading the global configuration. In addition, a parameter (`gasprice`) may be read from the oracle. */
  function global() external view returns (MgvStructs.GlobalPacked _global) {
    unchecked {
      (_global,,) = _config(OLKey(address(0), address(0), 0));
    }
  }

  function balanceOf(address maker) external view returns (uint balance) {
    unchecked {
      balance = _balanceOf[maker];
    }
  }

  // # Tick tree view functions

  function leafs(OLKey memory olKey, int index) external view returns (Leaf) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      unlockedMarketOnly(offerList.local);
      return offerList.leafs[index].clean();
    }
  }

  function level0(OLKey memory olKey, int index) external view returns (Field) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      MgvStructs.LocalPacked _local = offerList.local;
      unlockedMarketOnly(_local);

      if (_local.bestTick().level0Index() == index) {
        return _local.level0();
      } else {
        return offerList.level0[index];
      }
    }
  }

  function level1(OLKey memory olKey, int index) external view returns (Field) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      MgvStructs.LocalPacked _local = offerList.local;
      unlockedMarketOnly(_local);

      if (_local.bestTick().level1Index() == index) {
        return _local.level1();
      } else {
        return offerList.level1[index];
      }
    }
  }

  function level2(OLKey memory olKey) external view returns (Field) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      MgvStructs.LocalPacked _local = offerList.local;
      unlockedMarketOnly(_local);
      return _local.level2();
    }
  }

  // # Offer list view functions

  /* Function to check whether given an offer list is locked. Contrary to other offer list view functions, this does not revert if the offer list is locked. */
  function locked(OLKey memory olKey) external view returns (bool) {
    unchecked {
      return offerLists[olKey.hash()].local.lock();
    }
  }

  /* Convenience function to get best offer of the given offerList */
  function best(OLKey memory olKey) external view returns (uint offerId) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      MgvStructs.LocalPacked _local = offerList.local;
      unlockedMarketOnly(_local);
      return offerList.leafs[_local.bestTick().leafIndex()].clean().getNextOfferId();
    }
  }

  /* Get the olKey that corresponds to a hash, only works for offerLists that have been activated > 0 times */
  function olKeys(bytes32 olKeyHash) external view returns (OLKey memory olKey) {
    unchecked {
      olKey = _olKeys[olKeyHash];
    }
  }

  // # Offer view functions

  /* Get an offer in packed format */
  function offers(OLKey memory olKey, uint offerId) external view returns (MgvStructs.OfferPacked offer) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      unlockedMarketOnly(offerList.local);
      return offerList.offerData[offerId].offer;
    }
  }

  /* Get an offer detail in packed format */
  function offerDetails(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferDetailPacked offerDetail)
  {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      unlockedMarketOnly(offerList.local);
      return offerList.offerData[offerId].detail;
    }
  }

  /* Get both offer and offer detail in packed format */
  function offerData(OLKey memory olKey, uint offerId)
    external
    view
    returns (MgvStructs.OfferPacked offer, MgvStructs.OfferDetailPacked offerDetail)
  {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      unlockedMarketOnly(offerList.local);
      OfferData storage _offerData = offerList.offerData[offerId];
      return (_offerData.offer, _offerData.detail);
    }
  }

  /* Permit-related view functions */

  function allowances(address outbound_tkn, address inbound_tkn, address owner, address spender)
    external
    view
    returns (uint allowance)
  {
    unchecked {
      allowance = _allowances[outbound_tkn][inbound_tkn][owner][spender];
    }
  }

  function nonces(address owner) external view returns (uint nonce) {
    unchecked {
      nonce = _nonces[owner];
    }
  }

  // Note: the accessor for DOMAIN_SEPARATOR is defined in MgvStorage
  function PERMIT_TYPEHASH() external pure returns (bytes32) {
    unchecked {
      return _PERMIT_TYPEHASH;
    }
  }
}
