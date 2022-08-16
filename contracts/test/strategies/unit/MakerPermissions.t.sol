// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/Fork.sol";

import "mgv_src/strategies/single_user/SimpleMaker.sol";
import "mgv_src/strategies/routers/AbstractRouter.sol";

contract MakerPermissionTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  SimpleMaker makerContract;
  IOfferLogic.MakerOrder mko;

  function setUp() public virtual override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;

    super.setUp();
    // rename for convenience
    weth = base;
    usdc = quote;
    // ask 2000 USDC for 1 ETH
    mko = IOfferLogic.MakerOrder({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10**6,
      gives: 1 * 10**18,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0,
      offerId: 0
    });
    maker = freshAddress("maker");
    deal(maker, 1 ether);
    makerContract = new SimpleMaker({
      _MGV: IMangrove($(mgv)), // TODO: remove IMangrove dependency?
      deployer: maker
    });
    vm.prank(maker);
    makerContract.activate(tkn_pair(weth, usdc));
  }

  function testCannot_setAdmin() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.set_admin(freshAddress());
  }

  function testCannot_setReserve() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.set_reserve(freshAddress());
  }

  function testCannot_setRouter() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.set_router(AbstractRouter(freshAddress()));
  }

  function testCannot_PostNewOffer() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.newOffer{value: 0.1 ether}(mko);
  }

  function testCannot_RetractOffer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}(mko);
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.retractOffer(
      mko.outbound_tkn,
      mko.inbound_tkn,
      offerId,
      true
    );
  }

  function testCannot_UpdateOffer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}(mko);
    mko.offerId = offerId;
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.updateOffer(mko);
  }

  function testCannot_WithdrawTokens() public {
    // mockup of trade success
    deal($(weth), makerContract.reserve(), 1 ether);

    vm.expectRevert("AccessControlled/Invalid");
    makerContract.withdrawToken(weth, maker, 1 ether);
  }
}
