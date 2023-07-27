// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "../OfferLogic.t.sol";
import "mgv_src/strategies/routers/Permit2Router.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";

contract Permit2RouterTest is OfferLogicTest, DeployPermit2 {
  Permit2Router router;

  IPermit2 permit2;

  function setupLiquidityRouting() internal override {
    // OfferMaker has no router, replacing 0x router by a Permit2Router
    permit2 = IPermit2(deployPermit2());
    router = new Permit2Router(permit2);
    router.bind(address(makerContract));
    // maker must approve router
    vm.prank(deployer);
    makerContract.setRouter(router);

    vm.startPrank(owner);
    weth.approve(address(permit2), type(uint).max);
    usdc.approve(address(permit2), type(uint).max);
    permit2.approve(address(weth), address(router), type(uint160).max, type(uint48).max);
    permit2.approve(address(usdc), address(router), type(uint160).max, type(uint48).max);
    vm.stopPrank();
  }

  function fundStrat() internal virtual override {
    deal($(weth), owner, 1 ether);
    deal($(usdc), owner, cash(usdc, 2000));
  }

  event MakerBind(address indexed maker);
  event MakerUnbind(address indexed maker);

  function test_admin_can_unbind() public {
    expectFrom(address(router));
    emit MakerUnbind(address(makerContract));
    router.unbind(address(makerContract));
  }

  function test_maker_can_unbind() public {
    expectFrom(address(router));
    emit MakerUnbind(address(makerContract));
    vm.prank(address(makerContract));
    router.unbind();
  }
}
