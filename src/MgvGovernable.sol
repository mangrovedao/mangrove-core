// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {MgvLib, IMgvMonitor, MgvStructs, IERC20, Leaf, Field, Density, DensityLib, OLKey} from "./MgvLib.sol";
import "mgv_src/MgvCommon.sol";

// Contains gov functions, to reduce Mangrove contract size
contract MgvGovernable is MgvCommon {
  /* Admin functions */
  /* ## `authOnly` check */

  function authOnly() internal view {
    unchecked {
      require(msg.sender == governance || msg.sender == address(this) || governance == address(0), "mgv/unauthorized");
    }
  }

  /* ## Transfer ERC20 tokens to governance.

    If this function is called while an order is executing, the reentrancy may prevent a party (taker in normal Mangrove, maker in inverted Mangrove) from receiving their tokens. This is fine as the order execution will then fail, and the tx will revert. So the most a malicious governance can do is render Mangrove unusable.
  */
  function withdrawERC20(address tokenAddress, uint value) external {
    authOnly();
    require(transferToken(tokenAddress, governance, value), "mgv/withdrawERC20Fail");
  }

  /* # Set configuration and Mangrove state */

  /* ## Locals */
  /* ### `active` */
  function activate(OLKey memory olKey, uint fee, uint densityFixed, uint offer_gasbase) public {
    unchecked {
      authOnly();
      bytes32 olKeyHash = olKey.hash();
      // save hash->key mapping
      _olKeys[olKeyHash] = olKey;
      OfferList storage offerList = offerLists[olKeyHash];
      // activate market
      offerList.local = offerList.local.active(true);
      emit SetActive(olKey.hash(), olKey.outbound, olKey.inbound, olKey.tickScale, true);
      setFee(olKey, fee);
      setDensityFixed(olKey, densityFixed);
      setGasbase(olKey, offer_gasbase);
    }
  }

  function deactivate(OLKey memory olKey) public {
    authOnly();
    OfferList storage offerList = offerLists[olKey.hash()];
    offerList.local = offerList.local.active(false);
    emit SetActive(olKey.hash(), olKey.outbound, olKey.inbound, olKey.tickScale, false);
  }

  /* ### `fee` */
  function setFee(OLKey memory olKey, uint fee) public {
    unchecked {
      authOnly();
      /* `fee` is in basis points, i.e. in percents of a percent. */
      require(MgvStructs.Local.fee_check(fee), MgvStructs.Local.fee_size_error);
      OfferList storage offerList = offerLists[olKey.hash()];
      offerList.local = offerList.local.fee(fee);
      emit SetFee(olKey.hash(), fee);
    }
  }

  /* ### `density` */
  /* Useless if `global.useOracle != 0` and oracle returns a valid density. */
  /* Density is given as a 96.32 fixed point number. It will be stored as a 9-bit float and be approximated towards 0. The maximum error is 20%. See `DensityLib` for more information. */
  function setDensityFixed(OLKey memory olKey, uint densityFixed) public {
    unchecked {
      authOnly();

      //+clear+
      OfferList storage offerList = offerLists[olKey.hash()];
      /* Checking the size of `density` is necessary to prevent overflow before storing density as a float. */
      require(DensityLib.checkFixedDensity(densityFixed), "mgv/config/density/128bits");

      offerList.local = offerList.local.densityFromFixed(densityFixed);
      emit SetDensityFixed(olKey.hash(), densityFixed);
    }
  }

  // FIXME Temporary, remove once all tooling has adapted to setDensityFixed
  function setDensity(OLKey memory olKey, uint density) external {
    setDensityFixed(olKey, density << DensityLib.FIXED_FRACTIONAL_BITS);
  }

  /* ### `gasbase` */
  function setGasbase(OLKey memory olKey, uint offer_gasbase) public {
    unchecked {
      authOnly();
      /* Checking the size of `offer_gasbase` is necessary to prevent a) data loss when copied to an `OfferDetail` struct, and b) overflow when used in calculations. */
      require(
        MgvStructs.Local.kilo_offer_gasbase_check(offer_gasbase / 1e3), MgvStructs.Local.kilo_offer_gasbase_size_error
      );
      // require(uint24(offer_gasbase) == offer_gasbase, "mgv/config/offer_gasbase/24bits");
      //+clear+
      OfferList storage offerList = offerLists[olKey.hash()];
      offerList.local = offerList.local.offer_gasbase(offer_gasbase);
      emit SetGasbase(olKey.hash(), offer_gasbase);
    }
  }

  /* ## Globals */
  /* ### `kill` */
  function kill() public {
    unchecked {
      authOnly();
      internal_global = internal_global.dead(true);
      emit Kill();
    }
  }

  /* ### `gasprice` */
  /* Useless if `global.useOracle is != 0` */
  function setGasprice(uint gasprice) public {
    unchecked {
      authOnly();
      require(MgvStructs.Global.gasprice_check(gasprice), MgvStructs.Global.gasprice_size_error);

      //+clear+

      internal_global = internal_global.gasprice(gasprice);
      emit SetGasprice(gasprice);
    }
  }

  /* ### `gasmax` */
  function setGasmax(uint gasmax) public {
    unchecked {
      authOnly();
      /* Since any new `gasreq` is bounded above by `config.gasmax`, this check implies that all offers' `gasreq` is 24 bits wide at most. */
      require(MgvStructs.Global.gasmax_check(gasmax), MgvStructs.Global.gasmax_size_error);
      //+clear+
      internal_global = internal_global.gasmax(gasmax);
      emit SetGasmax(gasmax);
    }
  }

  /* ### `maxRecursionDepth` */
  function setMaxRecursionDepth(uint maxRecursionDepth) public {
    unchecked {
      authOnly();
      require(
        MgvStructs.Global.maxRecursionDepth_check(maxRecursionDepth), MgvStructs.Global.maxRecursionDepth_size_error
      );
      internal_global = internal_global.maxRecursionDepth(maxRecursionDepth);
      emit SetMaxRecursionDepth(maxRecursionDepth);
    }
  }

  /* ### `maxGasreqForFailingOffers` */
  function setMaxGasreqForFailingOffers(uint maxGasreqForFailingOffers) public {
    unchecked {
      authOnly();
      require(
        MgvStructs.Global.maxGasreqForFailingOffers_check(maxGasreqForFailingOffers),
        MgvStructs.Global.maxGasreqForFailingOffers_size_error
      );
      internal_global = internal_global.maxGasreqForFailingOffers(maxGasreqForFailingOffers);
      emit SetMaxGasreqForFailingOffers(maxGasreqForFailingOffers);
    }
  }

  /* ### `governance` */
  function setGovernance(address governanceAddress) public {
    unchecked {
      authOnly();
      require(governanceAddress != address(0), "mgv/config/gov/not0");
      governance = governanceAddress;
      emit SetGovernance(governanceAddress);
    }
  }

  /* ### `monitor` */
  function setMonitor(address monitor) public {
    unchecked {
      authOnly();
      internal_global = internal_global.monitor(monitor);
      emit SetMonitor(monitor);
    }
  }

  /* ### `useOracle` */
  function setUseOracle(bool useOracle) public {
    unchecked {
      authOnly();
      internal_global = internal_global.useOracle(useOracle);
      emit SetUseOracle(useOracle);
    }
  }

  /* ### `notify` */
  function setNotify(bool notify) public {
    unchecked {
      authOnly();
      internal_global = internal_global.notify(notify);
      emit SetNotify(notify);
    }
  }
}
