// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Keyrocker, IERC20, IMangrove} from "mgv_src/toy_strategies/offer_maker/Keyrocker.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

contract KeyrockerDeployer is Deployer {
  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      admin: broadcaster(),
      gasreq: 400_000,
      addressesProvider: fork.get("Aave")
    });
  }

  function innerRun(IMangrove mgv, address admin, uint gasreq, address addressesProvider) public {
    broadcast();
    Keyrocker maker = new Keyrocker(mgv, admin, gasreq, addressesProvider);
    smokeTest(maker);
  }

  function smokeTest(Keyrocker maker) internal view {
    require(address(maker.POOL()) != address(0), "Invalid pool address");
  }
}
