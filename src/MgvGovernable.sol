// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import {HasMgvEvents, MgvStructs} from "./MgvLib.sol";
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
  function activate(address outbound_tkn, address inbound_tkn, uint fee, uint density, uint offer_gasbase) public {
    unchecked {
      authOnly();
      Pair storage pair = pairs[outbound_tkn][inbound_tkn];
      pair.local = pair.local.active(true);
      emit SetActive(outbound_tkn, inbound_tkn, true);
      setFee(outbound_tkn, inbound_tkn, fee);
      setDensity(outbound_tkn, inbound_tkn, density);
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
      require(fee <= 500, "mgv/config/fee/<=500"); // at most 5%
      Pair storage pair = pairs[outbound_tkn][inbound_tkn];
      pair.local = pair.local.fee(fee);
      emit SetFee(outbound_tkn, inbound_tkn, fee);
    }
  }

  /* ### `density` */
  /* Useless if `global.useOracle != 0` */
  function setDensity(address outbound_tkn, address inbound_tkn, uint density) public {
    unchecked {
      authOnly();

      require(checkDensity(density), "mgv/config/density/112bits");
      //+clear+
      Pair storage pair = pairs[outbound_tkn][inbound_tkn];
      pair.local = pair.local.density(density);
      emit SetDensity(outbound_tkn, inbound_tkn, density);
    }
  }

  /* ### `gasbase` */
  function setGasbase(address outbound_tkn, address inbound_tkn, uint offer_gasbase) public {
    unchecked {
      authOnly();
      /* Checking the size of `offer_gasbase` is necessary to prevent a) data loss when copied to an `OfferDetail` struct, and b) overflow when used in calculations. */
      require(uint24(offer_gasbase) == offer_gasbase, "mgv/config/offer_gasbase/24bits");
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
      require(checkGasprice(gasprice), "mgv/config/gasprice/16bits");

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
      require(uint24(gasmax) == gasmax, "mgv/config/gasmax/24bits");
      //+clear+
      internal_global = internal_global.gasmax(gasmax);
      emit SetGasmax(gasmax);
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
