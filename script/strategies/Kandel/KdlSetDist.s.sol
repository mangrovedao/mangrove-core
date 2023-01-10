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
 * @notice Updates Kandel's distribution without populating. This assumes an extensional representation of both distribution in the form of arrays of values.
 */

contract KdlSetDist is Deployer {
  function run() public {
    innerRun({
      kdl: Kandel(envAddressOrName("KANDEL")),
      baseDist: vm.envUint("BASEDIST", ","),
      quoteDist: vm.envUint("QUOTEDIST", ","),
      from: vm.envUint("FROM"),
      to: vm.envUint("TO")
    });
  }

  ///@notice updates/creates a volume and price distribution on Kandel
  ///@param kdl the kandel instance
  ///@param baseDist `baseDist[i]` the amount of base tokens that Kandel must want/give at index `i+from`
  ///@param quoteDist `quoteDist[i]` the amount of quote tokens that Kandel must want/give at index `i+from`
  ///@param from the start index of Kandel one wishes to set
  ///@param to the last index of Kandel one wishes to set
  function innerRun(Kandel kdl, uint[] memory baseDist, uint[] memory quoteDist, uint from, uint to) public {
    require(baseDist.length == quoteDist.length, "Distribution must have same length");
    require(
      from < to && to < kdl.NSLOTS() && baseDist.length == (to - from), "interval must be of the form [from,...,to["
    );
    prettyLog("Setting distribution on Kandel...");
    broadcast();
    kdl.setDistribution(from, to, [baseDist, quoteDist]);
  }
}
