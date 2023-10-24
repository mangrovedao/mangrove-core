// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import "@mgv/src/core/MgvLib.sol";
import "@mgv/src/core/MgvCommon.sol";

/* Contains view functions, to reduce Mangrove contract size */
contract MgvView is MgvCommon {
  /* # Configuration Reads */
  /* Reading the configuration for an offer list involves reading the config global to all offer lists and the local one. In addition, a global parameter (`gasprice`) and a local one (`density`) may be read from the oracle. */
  function config(OLKey memory olKey) external view returns (Global _global, Local _local) {
    unchecked {
      (_global, _local,) = _config(olKey);
      unlockedOfferListOnly(_local);
    }
  }

  /* Sugar for getting only local config */
  function local(OLKey memory olKey) external view returns (Local _local) {
    unchecked {
      (, _local,) = _config(olKey);
      unlockedOfferListOnly(_local);
    }
  }

  /* Reading the global configuration. In addition, a parameter (`gasprice`) may be read from the oracle. */
  function global() external view returns (Global _global) {
    unchecked {
      (_global,,) = _config(OLKey(address(0), address(0), 0));
    }
  }

  function balanceOf(address maker) external view returns (uint balance) {
    unchecked {
      balance = _balanceOf[maker];
    }
  }

  /* # Tick tree view functions */

  function leafs(OLKey memory olKey, int index) external view returns (Leaf) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      unlockedOfferListOnly(offerList.local);
      return offerList.leafs[index].clean();
    }
  }

  function level3s(OLKey memory olKey, int index) external view returns (Field) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      Local _local = offerList.local;
      unlockedOfferListOnly(_local);

      if (_local.bestBin().level3Index() == index) {
        return _local.level3();
      } else {
        return offerList.level3s[index].clean();
      }
    }
  }

  function level2s(OLKey memory olKey, int index) external view returns (Field) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      Local _local = offerList.local;
      unlockedOfferListOnly(_local);

      if (_local.bestBin().level2Index() == index) {
        return _local.level2();
      } else {
        return offerList.level2s[index].clean();
      }
    }
  }

  function level1s(OLKey memory olKey, int index) external view returns (Field) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      Local _local = offerList.local;
      unlockedOfferListOnly(_local);

      if (_local.bestBin().level1Index() == index) {
        return _local.level1();
      } else {
        return offerList.level1s[index].clean();
      }
    }
  }

  function root(OLKey memory olKey) external view returns (Field) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      Local _local = offerList.local;
      unlockedOfferListOnly(_local);
      return _local.root();
    }
  }

  /* # Offer list view functions */

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
      Local _local = offerList.local;
      unlockedOfferListOnly(_local);
      return offerList.leafs[_local.bestBin().leafIndex()].clean().bestOfferId();
    }
  }

  /* Get the olKey that corresponds to a hash, only works for offer lists that have been activated > 0 times */
  function olKeys(bytes32 olKeyHash) external view returns (OLKey memory olKey) {
    unchecked {
      olKey = _olKeys[olKeyHash];
    }
  }

  /* # Offer view functions */

  /* Get an offer in packed format */
  function offers(OLKey memory olKey, uint offerId) external view returns (Offer offer) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      unlockedOfferListOnly(offerList.local);
      return offerList.offerData[offerId].offer;
    }
  }

  /* Get an offer detail in packed format */
  function offerDetails(OLKey memory olKey, uint offerId) external view returns (OfferDetail offerDetail) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      unlockedOfferListOnly(offerList.local);
      return offerList.offerData[offerId].detail;
    }
  }

  /* Get both offer and offer detail in packed format */
  function offerData(OLKey memory olKey, uint offerId) external view returns (Offer offer, OfferDetail offerDetail) {
    unchecked {
      OfferList storage offerList = offerLists[olKey.hash()];
      unlockedOfferListOnly(offerList.local);
      OfferData storage _offerData = offerList.offerData[offerId];
      return (_offerData.offer, _offerData.detail);
    }
  }

  /* Permit-related view functions */

  function allowance(address outbound_tkn, address inbound_tkn, address owner, address spender)
    external
    view
    returns (uint amount)
  {
    unchecked {
      amount = _allowance[outbound_tkn][inbound_tkn][owner][spender];
    }
  }

  function nonces(address owner) external view returns (uint nonce) {
    unchecked {
      nonce = _nonces[owner];
    }
  }

  /* Note: the accessor for `DOMAIN_SEPARATOR` is defined in `MgvOfferTakingWithPermit` */
  function PERMIT_TYPEHASH() external pure returns (bytes32) {
    unchecked {
      return _PERMIT_TYPEHASH;
    }
  }
}
