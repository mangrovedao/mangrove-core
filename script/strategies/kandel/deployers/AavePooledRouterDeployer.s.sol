// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {AavePooledRouter, IERC20} from "mgv_src/strategies/routers/integrations/AavePooledRouter.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

///@title  AavePooledRouter deployer
contract AavePooledRouterDeployer is Deployer {
  function run() public {
    innerRun({
      addressProvider: envAddressOrName("AAVE_ADDRESS_PROVIDER", "AaveAddressProvider"),
      overhead: vm.envUint("GASREQ")
    });
  }

  function innerRun(address addressProvider, uint overhead) public {
    broadcast();
    AavePooledRouter router = new AavePooledRouter(addressProvider, overhead);

    smokeTest(router);
  }

  function smokeTest(AavePooledRouter router) internal {
    IERC20 usdc = IERC20(fork.get("USDC"));
    usdc.approve(address(router), 1);

    vm.startPrank(broadcaster());
    router.bind(address(this));
    router.activate(usdc);
    vm.stopPrank();

    router.checkList(usdc, address(router));
  }
}
