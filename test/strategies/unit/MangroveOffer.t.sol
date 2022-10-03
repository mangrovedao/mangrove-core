// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_src/strategies/offer_maker/OfferMaker.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";

contract MangroveOfferTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  address payable taker;
  OfferMaker makerContract;

  // tracking IOfferLogic logs
  event LogIncident(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 makerData,
    bytes32 mgvData
  );

  function setUp() public override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;

    // populates `weth`,`usdc` and `mgv`
    // opens WETH/USDC market on mangrove

    super.setUp();
    // rename for convenience
    weth = base;
    usdc = quote;

    maker = freshAddress("maker");
    taker = freshAddress("taker");
    deal($(weth), taker, cash(weth, 50));
    deal($(usdc), taker, cash(usdc, 100_000));

    makerContract = new OfferMaker({
      mgv: IMangrove($(mgv)),
      router_: SimpleRouter(address(0)), // no router
      deployer: maker
    });
  }

  function test_AdminIsDeployer() public {
    assertEq(makerContract.admin(), maker, "Incorrect admin");
  }

  function testCannot_ActivateIfNotAdmin() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.activate(dynamic([IERC20(weth), usdc]));
  }

  function test_ActivatePassesCheckList() public {
    IERC20[] memory tokens = dynamic([IERC20(weth), usdc]);
    vm.prank(maker);
    makerContract.activate(tokens);
    makerContract.checkList(tokens);
  }

  function test_HasNoRouter() public {
    assertTrue(makerContract.router() == makerContract.NO_ROUTER());
  }

  function testCannot_callMakerExecuteIfNotMangrove() public {
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = address(weth);
    order.inbound_tkn = address(usdc);
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.makerExecute(order);
    vm.prank(address(mgv));
    bytes32 ret = makerContract.makerExecute(order);
    assertEq(ret, "mgvOffer/tradeSuccess", "Incorrect returned data");
  }

  function testCannot_callMakerPosthookIfNotMangrove() public {
    MgvLib.SingleOrder memory order;
    MgvLib.OrderResult memory result;
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.makerPosthook(order, result);
    vm.prank(address(mgv));
    makerContract.makerPosthook(order, result);
  }

  function test_FailedTradeIsLogged() public {
    MgvLib.SingleOrder memory order;
    MgvLib.OrderResult memory result;
    result.mgvData = "anythingButSuccess";
    result.makerData = "failReason";

    vm.expectEmit(true, false, false, true);
    emit LogIncident(
      IMangrove(payable(mgv)), IERC20(address(0)), IERC20(address(0)), 0, result.makerData, result.mgvData
      );
    vm.prank(address(mgv));
    makerContract.makerPosthook(order, result);
  }

  function test_lastLookReturnedValueIsPassed() public {
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = $(weth);
    order.inbound_tkn = $(usdc);
    vm.prank(address(mgv));
    bytes32 data = makerContract.makerExecute(order);
    assertEq(data, "mgvOffer/tradeSuccess");
  }

  function test_AdminCanWithdrawFunds() public {
    assertEq(mgv.balanceOf(address(makerContract)), 0, "incorrect balance");
    mgv.fund{value: 1 ether}(address(makerContract));
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.withdrawFromMangrove(0.5 ether, maker);
    uint balMaker = maker.balance;
    vm.prank(maker);
    makerContract.withdrawFromMangrove(0.5 ether, maker);
    assertEq(mgv.balanceOf(address(makerContract)), 0.5 ether, "incorrect balance");
    assertEq(maker.balance, balMaker + 0.5 ether, "incorrect balance");
  }

  function test_AdminCanSetRouter() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.setRouter(SimpleRouter(freshAddress()));

    vm.startPrank(maker);
    SimpleRouter router = new SimpleRouter();
    router.setAdmin(address(makerContract));
    makerContract.setRouter(router);
    assertEq(address(makerContract.router()), address(router), "Router was not set");
    vm.stopPrank();
  }

  function test_CheckListTakesNewRouterIntoAccount() public {
    vm.startPrank(maker);
    SimpleRouter router = new SimpleRouter();
    router.setAdmin(address(makerContract));
    makerContract.setRouter(router);

    IERC20[] memory tokens = dynamic([IERC20(weth), usdc]);
    vm.expectRevert("MangroveOffer/LogicMustApproveMangrove");
    makerContract.checkList(tokens);

    makerContract.activate(tokens);
    makerContract.checkList(tokens);
    vm.stopPrank();
  }

  function test_GasReqTakesNewRouterIntoAccount() public {
    uint gasreq = makerContract.offerGasreq();
    vm.startPrank(maker);
    SimpleRouter router = new SimpleRouter();
    router.setAdmin(address(makerContract));
    makerContract.setRouter(router);
    assertEq(makerContract.offerGasreq(), gasreq + router.gasOverhead(), "incorrect gasreq");
    vm.stopPrank();
  }
}
