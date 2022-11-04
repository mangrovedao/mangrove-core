// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
// import "mgv_test/lib/Fork.sol";

import "mgv_src/strategies/offer_maker/OfferMaker.sol";
import "mgv_src/strategies/routers/AbstractRouter.sol";

contract AccessControlTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable admin;
  OfferMaker makerContract;

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
    makerContract = new OfferMaker({
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

  function testCannot_withdrawTokens() public {
    // mockup of trade success
    deal($(weth), makerContract.reserve(admin), 1 ether);

    vm.expectRevert("AccessControlled/Invalid");
    makerContract.withdrawToken(weth, $(this), 1 ether);
  }

  function test_admin_can_withdrawTokens() public {
    // mockup of trade success
    deal($(weth), makerContract.reserve(admin), 1 ether);
    uint oldBal = weth.balanceOf($(this));
    vm.prank(admin);
    makerContract.withdrawToken(weth, $(this), 1 ether);
    assertEq(weth.balanceOf($(this)), oldBal + 1 ether, "incorrect balance");
  }
}
