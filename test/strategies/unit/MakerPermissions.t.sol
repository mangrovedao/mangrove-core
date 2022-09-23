// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
// import "mgv_test/lib/Fork.sol";

import "mgv_src/strategies/offer_maker/OfferMaker.sol";
import "mgv_src/strategies/routers/AbstractRouter.sol";

contract MakerPermissionTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  OfferMaker makerContract;

  // PolygonFork fork = new PolygonFork();

  function setUp() public virtual override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;

    super.setUp();
    // rename for convenience
    weth = base;
    usdc = quote;

    maker = freshAddress("maker");
    deal(maker, 1 ether);
    makerContract = new OfferMaker({
      mgv: IMangrove($(mgv)),
      router_: AbstractRouter(address(0)),
      deployer: maker
    });
    vm.prank(maker);
    makerContract.activate(dynamic([IERC20(weth), usdc]));
  }

  function testCannot_setAdmin() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.setAdmin(freshAddress());
  }

  function testCannot_setReserve() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.setReserve(freshAddress());
  }

  function testCannot_setRouter() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.setRouter(AbstractRouter(freshAddress()));
  }

  function testCannot_PostNewOffer() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
  }

  function testCannot_RetractOffer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.retractOffer(weth, usdc, offerId, true);
  }

  function testCannot_UpdateOffer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.updateOffer({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0,
      offerId: offerId
    });
  }

  function testCannot_WithdrawTokens() public {
    // mockup of trade success
    deal($(weth), makerContract.reserve(), 1 ether);

    vm.expectRevert("AccessControlled/Invalid");
    makerContract.withdrawToken(weth, maker, 1 ether);
  }
}
