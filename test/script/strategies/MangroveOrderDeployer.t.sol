// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/lib/MangroveDeployer.sol";

import {Test2, Test} from "mgv_lib/Test2.sol";

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {MangroveOrderDeployer, MangroveOrderEnriched} from "mgv_script/strategies/MangroveOrderDeployer.s.sol";

contract MangroveDeployerTest is Deployer, Test2 {
  MangroveOrderDeployer mgoDeployer;
  address chief;
  uint gasprice;
  uint gasmax;

  function setUp() public {
    mgoDeployer = new MangroveOrderDeployer();

    chief = freshAddress("admin");
    gasprice = 42;
    gasmax = 8_000_000;
    (new MangroveDeployer()).innerRun(chief, gasprice, gasmax);
  }

  function test_normal_deploy() public {
    // MangroveOrderEnriched - verify mgv is used and admin is chief
    vm.setEnv("MANGROVE", ""); // make sure env MANGROVE not usable
    address mgv = fork.get("Mangrove");
    mgoDeployer.run();
    MangroveOrderEnriched mgoe = MangroveOrderEnriched(fork.get("MangroveOrderEnriched"));

    assertEq(mgoe.admin(), broadcaster());
    assertEq(address(mgoe.MGV()), mgv);
  }

  function test_with_env_var_deploy() public {
    // MangroveOrderEnriched - verify mgv is used and admin is chief
    address mgv = freshAddress("fakeMangrove");
    vm.setEnv("MANGROVE", vm.toString(mgv));
    mgoDeployer.run();
    MangroveOrderEnriched mgoe = MangroveOrderEnriched(fork.get("MangroveOrderEnriched"));
    assertEq(address(mgoe.MGV()), mgv);
  }
}
