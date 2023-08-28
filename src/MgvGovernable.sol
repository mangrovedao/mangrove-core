// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {HasMgvEvents, MgvStructs, DensityLib} from "./MgvLib.sol";
import {MgvRoot} from "./MgvRoot.sol";

contract MgvGovernable is MgvRoot {
  /* The `governance` address. Governance is the only address that can configure parameters. */
  address public governance;

  constructor(address _governance, uint _gasprice, uint gasmax) MgvRoot() {
    unchecked {
      emit NewMgv();

      /* Initially, governance is open to anyone. */

      /* Set initial gasprice and gasmax. */
      setGasprice(_gasprice);
      setGasmax(gasmax);
      /* Without optimizer enabled it fails above 79. Set default a bit lower to be safe. */
      setMaxRecursionDepth(75);
      /* Initialize governance to `_governance` after parameter setting. */
      setGovernance(_governance);
    }
  }

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
  function activate(address outbound_tkn, address inbound_tkn, uint fee, uint densityFixed, uint offer_gasbase) public {
    unchecked {
      authOnly();
      Pair storage pair = pairs[outbound_tkn][inbound_tkn];
      pair.local = pair.local.active(true);
      emit SetActive(outbound_tkn, inbound_tkn, true);
      setFee(outbound_tkn, inbound_tkn, fee);
      setDensityFixed(outbound_tkn, inbound_tkn, densityFixed);
      setGasbase(outbound_tkn, inbound_tkn, offer_gasbase);
    }
  }

  function deactivate(address outbound_tkn, address inbound_tkn) public {
    authOnly();
    Pair storage pair = pairs[outbound_tkn][inbound_tkn];
    pair.local = pair.local.active(false);
    emit SetActive(outbound_tkn, inbound_tkn, false);
  }

  /* ### `fee` */
  function setFee(address outbound_tkn, address inbound_tkn, uint fee) public {
    unchecked {
      authOnly();
      /* `fee` is in basis points, i.e. in percents of a percent. */
      require(MgvStructs.Local.fee_check(fee), MgvStructs.Local.fee_size_error);
      Pair storage pair = pairs[outbound_tkn][inbound_tkn];
      pair.local = pair.local.fee(fee);
      emit SetFee(outbound_tkn, inbound_tkn, fee);
    }
  }

  /* ### `density` */
  /* Useless if `global.useOracle != 0` and oracle returns a valid density. */
  /* Density is given as a 96.32 fixed point number. It will be stored as a 9-bit float and be approximated towards 0. The maximum error is 20%. See `DensityLib` for more information. */
  function setDensityFixed(address outbound_tkn, address inbound_tkn, uint densityFixed) public {
    unchecked {
      authOnly();

      //+clear+
      Pair storage pair = pairs[outbound_tkn][inbound_tkn];
      /* Checking the size of `density` is necessary to prevent overflow before storing density as a float. */
      require(DensityLib.checkFixedDensity(densityFixed), "mgv/config/density/128bits");

      pair.local = pair.local.densityFromFixed(densityFixed);
      emit SetDensityFixed(outbound_tkn, inbound_tkn, densityFixed);
    }
  }

  // FIXME Temporary, remove once all tooling has adapted to setDensityFixed
  function setDensity(address outbound_tkn, address inbound_tkn, uint density) external {
    setDensityFixed(outbound_tkn, inbound_tkn, density << DensityLib.FIXED_FRACTIONAL_BITS);
  }

  /* ### `gasbase` */
  function setGasbase(address outbound_tkn, address inbound_tkn, uint offer_gasbase) public {
    unchecked {
      authOnly();
      /* Checking the size of `offer_gasbase` is necessary to prevent a) data loss when copied to an `OfferDetail` struct, and b) overflow when used in calculations. */
      require(
        MgvStructs.Local.kilo_offer_gasbase_check(offer_gasbase / 1e3), MgvStructs.Local.kilo_offer_gasbase_size_error
      );
      // require(uint24(offer_gasbase) == offer_gasbase, "mgv/config/offer_gasbase/24bits");
      //+clear+
      Pair storage pair = pairs[outbound_tkn][inbound_tkn];
      pair.local = pair.local.offer_gasbase(offer_gasbase);
      emit SetGasbase(outbound_tkn, inbound_tkn, offer_gasbase);
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
