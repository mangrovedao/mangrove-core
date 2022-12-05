// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
// import "mgv_test/lib/Fork.sol";

import {
  DirectTester, AbstractRouter, IERC20, IMangrove, IERC20
} from "mgv_src/strategies/offer_maker/DirectTester.sol";

contract AccessControlTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable admin;
  DirectTester makerContract;

  function setUp() public virtual override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;

    super.setUp();
    // rename for convenience
    weth = base;
    usdc = quote;

    admin = freshAddress("admin");
    deal(admin, 1 ether);
    makerContract = new DirectTester({
      mgv: IMangrove($(mgv)),
      router_: AbstractRouter(address(0)),
      deployer: admin
    });
    vm.startPrank(admin);
    makerContract.activate(dynamic([IERC20(weth), usdc]));
    weth.approve(address(makerContract), type(uint).max);
    usdc.approve(address(makerContract), type(uint).max);
    vm.stopPrank();
  }

  function testCannot_setAdmin() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.setAdmin(freshAddress());
  }

  function test_admin_can_set_admin() public {
    address newAdmin = freshAddress("newAdmin");
    vm.prank(admin);
    makerContract.setAdmin(newAdmin);
    assertEq(makerContract.admin(), newAdmin, "Incorrect admin");
  }

  function testCannot_setRouter() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.setRouter(AbstractRouter(freshAddress()));
  }

  function test_admin_can_set_router() public {
    address newRouter = freshAddress("newRouter");
    vm.prank(admin);
    makerContract.setRouter(AbstractRouter(newRouter));
    assertEq(address(makerContract.router()), newRouter, "Incorrect router");
  }

  function testCannot_setReserve() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.setReserve(freshAddress(), freshAddress());
  }

  function test_admin_can_set_reserve() public {
    address reserve = freshAddress();
    address maker = freshAddress();
    vm.prank(admin);
    makerContract.setReserve(maker, reserve);
    assertEq(makerContract.reserve(maker), reserve, "Incorrect reserve");
  }
}
