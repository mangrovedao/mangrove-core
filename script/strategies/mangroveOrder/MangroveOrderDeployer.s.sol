// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MangroveOrder, IERC20, IMangrove} from "mgv_src/strategies/MangroveOrder.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Deploys a MangroveOrder instance
    First test:
 forge script --fork-url mumbai MangroveOrderDeployer -vvv 
    Then broadcast and verify:
 WRITE_DEPLOY=true forge script --fork-url mumbai MangroveOrderDeployer -vvv --broadcast --verify
    Remember to activate it using ActivateMangroveOrder

  You can specify a mangrove address with the MANGROVE env var.*/
contract MangroveOrderDeployer is Deployer {
  MangroveOrder mgvOrder;

  function run() public {
    address mgv;
    try vm.envAddress("MANGROVE") returns (address _mangrove) {
      mgv = _mangrove;
    } catch (bytes memory) {
      mgv = fork.get("Mangrove");
    }
    address governance;
    try vm.envAddress("MgvGovernance") returns (address _governance) {
      governance = _governance;
    } catch (bytes memory) {
      try fork.get("MgvGovernance") returns (address payable _governance) {
        governance = _governance;
      } catch (bytes memory) {
        governance = broadcaster();
      }
    }

    innerRun({mangrove: mgv, admin: governance});
    outputDeployment();
  }

  /**
   * @param admin address of the admin on MangroveOrder after deployment
   */
  function innerRun(address admin, address mangrove) public {
    broadcast();
    if (forMultisig) {
      mgvOrder = new MangroveOrder{salt:salt}(IMangrove(payable(mangrove)), admin, 30_000);
    } else {
      mgvOrder = new MangroveOrder(IMangrove(payable(mangrove)), admin, 30_000);
    }
    fork.set("MangroveOrder", address(mgvOrder));
    fork.set("MangroveOrder-Router", address(mgvOrder.router()));
  }
}
