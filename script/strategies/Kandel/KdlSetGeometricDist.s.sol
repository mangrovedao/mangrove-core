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
 * @notice Updates Kandel's distribution without populating.
 *  This uses an intensional representation of both distribution in the form of geometric progressions which is then discretized.
 */

contract KdlSetGeometricDist is Deployer {
  function run() public {
    Kandel kdl = Kandel(envAddressOrName("KANDEL"));

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

  ///@notice fills and array with a discretized geometric progression
  ///@param startValue the first value of the series
  ///@param ratio of the progression
  ///@param from the start index of the array that contains the first value of the progression
  ///@param to the end index of the array (excluded)
  ///@param dist the array that is to be filled starting at `from` and until `to-1` is filled.
  function fillGeometricDist(uint startValue, uint ratio, uint from, uint to, uint[] memory dist) internal pure {
    dist[from] = startValue;
    for (uint i = from + 1; i < to; i++) {
      dist[i] = (dist[i - 1] * ratio) / 100;
    }
  }

  ///@notice Updates Kandel's price and volume distributions, using geometric progression parameters.
  ///@param kdl Kandel's instance
  ///@param from the start index of the distributions one wishes to update
  ///@param to the last index (excluded) of the distributions one wishes to update
  ///@param baseFrom the first value of the volume progression (in base token amounts)
  ///@param quoteFrom the first value of the price progression (in quote token amounts per units of base)
  function innerRun(Kandel kdl, uint from, uint to, uint baseFrom, uint quoteFrom, uint baseRatio, uint quoteRatio)
    public
  {
    require(from < to && to <= kdl.NSLOTS(), "interval must be of the form [from,...,to[");
    require(uint96(baseFrom) == baseFrom, "BASE0 is too high");
    require(uint96(quoteFrom) == quoteFrom, "QUOTE0 is too high");
    uint[] memory baseDist = new uint[](kdl.NSLOTS());
    uint[] memory quoteDist = new uint[](kdl.NSLOTS());

    prettyLog("Generating distributions...");
    uint baseDecimals = kdl.BASE().decimals();
    fillGeometricDist(baseFrom, baseRatio, from, to, baseDist);
    fillGeometricDist(quoteFrom, quoteRatio, from, to, quoteDist);
    //turning price distribution into quote volumes
    for (uint i = from; i < to; i++) {
      quoteDist[i] = (quoteDist[i] * baseDist[i]) / (10 ** baseDecimals);
    }

    prettyLog("Setting distribution on Kandel...");
    broadcast();
    kdl.setDistribution(from, to, [baseDist, quoteDist]);
    console.log("Interval [", from, to, "[ initialized.");
  }
}
