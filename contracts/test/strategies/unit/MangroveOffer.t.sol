// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_src/strategies/single_user/SimpleMaker.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";

contract MangroveOfferTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  address payable taker;
  SimpleMaker makerContract;

  // tracking IOfferLogic logs
  event LogIncident(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 reason
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

    vm.prank(maker);
    makerContract = new SimpleMaker({
      _MGV: IMangrove($(mgv)), // TODO: remove IMangrove dependency?
      deployer: maker
    });
  }

  function test_AdminIsDeployer() public {
    assertEq(makerContract.admin(), maker, "Incorrect admin");
  }

  function test_DefaultGasReq() public {
    assertEq(
      makerContract.ofr_gasreq(),
      50_000,
      "Incorrect default gasreq for simple maker"
    );
  }

  function test_CheckList() public {
    IERC20[] memory tokens = tkn_pair(weth, usdc);
    vm.expectRevert("MangroveOffer/AdminMustApproveMangrove");
    makerContract.checkList(tokens);
    vm.prank(maker);
    makerContract.approveMangrove(weth);
    makerContract.approveMangrove(usdc);
    // after approval, checkList should no longer revert
    makerContract.checkList(tokens);
  }

  function testCannot_ActivateIfNotAdmin() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.activate(tkn_pair(weth, usdc));
  }

  function test_ActivatePassesCheckList() public {
    IERC20[] memory tokens = tkn_pair(weth, usdc);
    vm.prank(maker);
    makerContract.activate(tokens);
    makerContract.checkList(tokens);
  }

  function test_HasNoRouter() public {
    assertTrue(!makerContract.has_router());
    vm.expectRevert("mgvOffer/0xRouter");
    // accessing router throws if no router is defined for makerContract
    makerContract.router();
  }

  function testCannot_callMakerExecuteIfNotMangrove() public {
    MgvLib.SingleOrder memory order;
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.makerExecute(order);
    vm.prank(address(mgv));
    bytes32 ret = makerContract.makerExecute(order);
    assertEq(ret, "", "Incorrect returned data");
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
      IMangrove(payable(mgv)),
      IERC20(address(0)),
      IERC20(address(0)),
      0,
      "failReason"
    );
    vm.prank(address(mgv));
    makerContract.makerPosthook(order, result);
  }

  function test_AdminCanWithdrawFunds() public {
    assertEq(mgv.balanceOf(address(makerContract)), 0, "incorrect balance");
    mgv.fund{value: 1 ether}(address(makerContract));
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.withdrawFromMangrove(0.5 ether, maker);
    uint balMaker = maker.balance;
    vm.prank(maker);
    makerContract.withdrawFromMangrove(0.5 ether, maker);
    assertEq(
      mgv.balanceOf(address(makerContract)),
      0.5 ether,
      "incorrect balance"
    );
    assertEq(maker.balance, balMaker + 0.5 ether, "incorrect balance");
  }

  function test_GetMissingProvisionTakesBalanceIntoAccount() public {
    uint missing = makerContract.getMissingProvision(
      weth,
      usdc,
      type(uint).max,
      0,
      0
    );
    mgv.fund{value: missing - 1}(address(makerContract));
    uint missing_ = makerContract.getMissingProvision(
      weth,
      usdc,
      type(uint).max,
      0,
      0
    );
    assertEq(missing_, 1, "incorrect missing provision");
  }

  function test_AdminCanSetRouter() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.set_router(SimpleRouter(freshAddress()));

    vm.startPrank(maker);
    SimpleRouter router = new SimpleRouter();
    router.set_admin(address(makerContract));
    makerContract.set_router(router);
    assertEq(
      address(makerContract.router()),
      address(router),
      "Router was not set"
    );
    vm.stopPrank();
  }

  function test_CheckListTakesNewRouterIntoAccount() public {
    vm.startPrank(maker);
    SimpleRouter router = new SimpleRouter();
    router.set_admin(address(makerContract));
    makerContract.set_router(router);

    IERC20[] memory tokens = tkn_pair(weth, usdc);
    vm.expectRevert("Router/NotApprovedByMakerContract");
    makerContract.checkList(tokens);

    makerContract.activate(tokens);
    makerContract.checkList(tokens);
  }

  function test_GasReqTakesNewRouterIntoAccount() public {
    uint gasreq = makerContract.ofr_gasreq();
    vm.startPrank(maker);
    SimpleRouter router = new SimpleRouter();
    router.set_admin(address(makerContract));
    makerContract.set_router(router);
    assertEq(
      makerContract.ofr_gasreq(),
      gasreq + router.gas_overhead(),
      "incorrect gasreq"
    );
  }
}
