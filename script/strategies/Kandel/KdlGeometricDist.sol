// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {
  ExplicitKandel as Kandel,
  IERC20,
  IMangrove
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice Populate Kandel's distribution on Mangrove
 */

contract KdlGeometricDist is Deployer {
  uint[] baseDist;
  uint[] quoteDist;

  function run() public {
    Kandel kdl = Kandel(envAddressOrName("KANDEL"));
    baseDist = new uint[](kdl.NSLOTS());
    quoteDist = new uint[](kdl.NSLOTS());

    innerRun({
      kdl: kdl,
      from: vm.envUint("FROM"),
      to: vm.envUint("TO"),
      baseFrom: vm.envUint("BASE0"),
      quoteFrom: vm.envUint("QUOTE0"),
      baseRatio: vm.envUint("BASERATIO"),
      quoteRatio: vm.envUint("QUOTERATIO")
    });
  }

  function fillGeometricDist(uint startValue, uint ratio, uint from, uint to, uint[] storage dist) internal {
    dist[from] = startValue;
    for (uint i = from + 1; i < to; i++) {
      dist[i] = (dist[i - 1] * ratio) / 100;
    }
  }

  function innerRun(Kandel kdl, uint from, uint to, uint baseFrom, uint quoteFrom, uint baseRatio, uint quoteRatio)
    public
  {
    require(from < to && to < kdl.NSLOTS(), "interval must be of the form [from,...,to[");
    require(uint96(baseFrom) == baseFrom, "BASE0 is too high");
    require(uint96(quoteFrom) == quoteFrom, "QUOTE0 is too high");

    prettyLog("Generating distributions...");
    uint baseDecimals = kdl.BASE().decimals();
    fillGeometricDist(baseFrom, baseRatio, from, to, baseDist);
    fillGeometricDist(quoteFrom, quoteRatio, from, to, quoteDist);
    //turning price distribution into quote volumes
    for (uint i = from; i < to; i++) {
      quoteDist[i] = (quoteDist[i] * baseDist[i]) / (10 ** baseDecimals);
      console.log(toUnit(quoteDist[i], 6), toUnit(baseDist[i], 18));
    }

    prettyLog("Setting distribution on Kandel...");
    vm.broadcast();
    kdl.setDistribution(from, to, [baseDist, quoteDist]);
  }
}
