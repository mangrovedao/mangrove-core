// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/lib/MangroveDeployer.sol";

import {Test2, Test, console2 as csl} from "mgv_lib/Test2.sol";

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {MangoDeployer, Mango, IERC20} from "mgv_script/strategies/MangoDeployer.s.sol";

contract MangoDeployerTest is Deployer, Test2 {
  MangoDeployer mgoDeployer;
  IERC20 base;
  IERC20 quote;
  string mangoName;

  function setUp() public {
    mgoDeployer = new MangoDeployer();
    base = IERC20(getRawAddressOrName("WETH"));
    quote = IERC20(getRawAddressOrName("USDC"));
    mangoName = mgoDeployer.getName(base, quote);
    try fork.get(mangoName) returns (address payable mgo) {
      csl.log("A mango instance is already deployed under the name", mangoName, "at address", mgo);
      csl.log("Deploy script will override address if WRITE_DEPLOY=true");
    } catch {
      csl.log("A fresh mango will be deployed");
    }
  }

  function test_normal_deploy() public {
    vm.setEnv("MANGROVE", ""); // make sure env MANGROVE not usable
    address mgv = fork.get("Mangrove");

    mgoDeployer.run();
    Mango mango = Mango(fork.get(mangoName));

    // checking that environment matches current deployment
    assertEq(address(mango), address(mgoDeployer.current()), "deployment address mismatch");

    // checking admin, plus router and Mangrove connection
    assertEq(mango.admin(), broadcaster(), "wrong Mango admin");
    assertEq(address(mango.MGV()), mgv, "wrong Mangrove address");
    assertEq(mango.router().admin(), broadcaster(), "wrong router admin");
    assertTrue(mango.router().makers(address(mango)), "Mango not bound to router");
  }
}
