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

contract KdlMultDist is Deployer {
  function run() public {
    innerRun({
      kdl: Kandel(envAddressOrName("KANDEL")),
      pmin: vm.envUint("PMIN"),
      pmax: vm.envUint("PMAX"),
      ratio: vm.envUint("RATIO")
    });
  }

  struct HeapVars {
    uint96[] baseDist;
    uint96[] quoteDist;
    uint from;
    uint to;
    uint baseDecimals;
    uint[] baseSlice;
    uint[] quoteSlice;
  }

  function innerRun(Kandel kdl, uint pmin, uint pmax, uint ratio) public {
    require(pmin < pmax, " price interval must be of the form [pmin,...,pmax[");

    HeapVars memory vars;
    vm.startPrank(broadcaster());
    vars.baseDist = kdl.baseDist();
    vars.quoteDist = kdl.quoteDist();
    vm.stopPrank();

    vars.baseDecimals = kdl.BASE().decimals();
    uint p;
    uint i;
    // FIXME for large price distribution, dychotomic search would be better here
    while (i < vars.baseDist.length) {
      p = uint(vars.quoteDist[i]) * 10 ** vars.baseDecimals / uint(vars.baseDist[i]);
      vars.from = (p < pmin) ? i : vars.from;
      vars.to = i;
      if (p >= pmax) {
        break;
      }
      i++;
    }
    require(vars.from < vars.to, "could not find pmin in price distribution");
    console.log("Applying changes in the price interval [", vars.from, vars.to, "]...");
    uint N = vars.to - vars.from;
    vars.baseSlice = new uint[](N);
    vars.quoteSlice = new uint[](N);

    for (i = 0; i < N; i++) {
      vars.baseSlice[i] = (vars.baseDist[i + vars.from] * ratio) / 100;
      vars.quoteSlice[i] = (vars.quoteDist[i + vars.from] * ratio) / 100;
    }
    broadcast();
    kdl.setDistribution(vars.from, vars.to, [vars.baseSlice, vars.quoteSlice]);
  }
}
