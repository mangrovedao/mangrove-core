// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {OfferMaker, IMangrove, IERC20} from "mgv_src/strategies/offer_maker/OfferMaker.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";

contract OfferMakerTest is MangroveTest {
  address payable internal deployer;
  OfferMaker internal makerContract;

  function setUp() public override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6; //default is 18
    options.defaultFee = 30; // fee in bp

    // calls MangroveTest's setUp.
    // this populates `base`,`quote` and `mgv` and `mgvReader`
    // opens base/quote market on mangrove with no offers and 0.03% fee
    // admin of mangrove is the testRunner i.e address(this)
    super.setUp();

    deployer = freshAddress("deployer");

    // using deployer as admin
    //vm.prank(deployer);
    //    vm.startPrank(deployer);
    makerContract = new OfferMaker({
      mgv: IMangrove($(mgv)),
      router_: AbstractRouter(address(0)), // no router
      deployer: deployer,
      gasreq: 50_000,
      owner: deployer
    });
    //   vm.stopPrank();

    // activation of OfferMaker
    deal(deployer, 10 ether);
    vm.prank(deployer);
    makerContract.activate(dynamic([IERC20(base), quote]));
  }

  function test_Admin_is_deployer() public {
    assertEq(makerContract.admin(), deployer, "invalid admin address");
  }

  function test_post_bid() public {
    vm.startPrank(deployer);
    uint id = makerContract.newOffer{value: 0.1 ether}(quote, base, 1 ether, cash(quote, 2000), 0);
    vm.stopPrank();
    assertTrue(id != 0, "invalid offer id");
  }

  function test_post_ask() public {}
}
