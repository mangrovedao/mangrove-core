// SPDX-License-Identifier: Unlicense

/* `MgvLib` contains data structures returned by external calls to Mangrove and the interfaces it uses for its own external calls. */

pragma solidity ^0.8.10;

import {IMangrove} from "mgv_src/IMangrove.sol";
import "mgv_lib/TickLib.sol";

library MgvHelpers {
  // Converts snipe targets from volume-based [id,wants,gives,gasreq] tick-based [id,tick,volume,gasreq]. volume will be wants if fillWsants is true, volume will be gives otherwise.
  function convertSnipeTargetsToTicks(uint[4][] memory targets, bool fillWants)
    internal
    pure
    returns (uint[4][] memory)
  {
    uint[4][] memory newTargets = new uint[4][](targets.length);
    // convert targets from [id,wants,gives,gasreq] to [id,tick,volume,gasreq]
    uint volumeIndex = fillWants ? 1 : 2;
    for (uint i = 0; i < targets.length; i++) {
      newTargets[i][0] = targets[i][0];
      newTargets[i][1] = uint(Tick.unwrap(TickLib.tickFromTakerVolumes(targets[i][2], targets[i][1])));
      newTargets[i][2] = targets[i][volumeIndex];
      newTargets[i][3] = targets[i][3];
    }
    return newTargets;
  }

  function snipesForByVolume(
    address mgv,
    address outbound_tkn,
    address inbound_tkn,
    uint[4][] memory targets,
    bool fillWants,
    address taker
  ) internal returns (uint, uint, uint, uint, uint) {
    uint[4][] memory newTargets = convertSnipeTargetsToTicks(targets, fillWants);
    return IMangrove(payable(mgv)).snipesFor(outbound_tkn, inbound_tkn, newTargets, fillWants, taker);
  }

  function snipesByVolume(
    address mgv,
    address outbound_tkn,
    address inbound_tkn,
    uint[4][] calldata targets,
    bool fillWants
  ) external returns (uint, uint, uint, uint, uint) {
    unchecked {
      uint[4][] memory newTargets = convertSnipeTargetsToTicks(targets, fillWants);
      return IMangrove(payable(mgv)).snipes(outbound_tkn, inbound_tkn, newTargets, fillWants);
    }
  }
}
