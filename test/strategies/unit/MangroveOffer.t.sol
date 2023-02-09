// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {DirectTester, IMangrove, IERC20} from "mgv_src/strategies/offer_maker/DirectTester.sol";
import {SimpleRouter, AbstractRouter} from "mgv_src/strategies/routers/SimpleRouter.sol";

contract MangroveOfferTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable deployer;
  DirectTester makerContract;

  // tracking IOfferLogic logs
  event LogIncident(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 makerData,
    bytes32 mgvData
  );

  event SetAdmin(address);
  event SetRouter(address);

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

    deployer = payable(new TestSender());
    vm.prank(deployer);
    makerContract = new DirectTester({
      mgv: IMangrove($(mgv)),
      router_: AbstractRouter(address(0)), // no router
      deployer: deployer,
      gasreq: 50_000
    });
  }

  function test_Admin_is_deployer() public {
    assertEq(makerContract.admin(), deployer, "Incorrect admin");
  }

  function testCannot_activate_if_not_admin() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.activate(dynamic([IERC20(weth), usdc]));
  }

  function test_a_checkList_with_router() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    vm.expectRevert("mgvOffer/LogicMustApproveMangrove");
    makerContract.checkList(tokens);
  }

  function test_b_checkList_router_not_bound() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    // passes a
    makerContract.approve(weth, $(mgv), type(uint).max);
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    vm.expectRevert("Router/callerIsNotBoundToRouter");
    makerContract.checkList(tokens);
  }

  function test_c_checkList_router_not_approved() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    // passes a
    makerContract.approve(weth, $(mgv), type(uint).max);
    // passes b
    router.bind(address(makerContract));
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    vm.expectRevert("Router/NotApprovedByMakerContract");
    makerContract.checkList(tokens);
  }

  function test_d_checkList_router_not_approved_by_reserve() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    // passes a
    makerContract.approve(weth, $(mgv), type(uint).max);
    // passes b
    router.bind(address(makerContract));
    // passes c
    makerContract.approve(weth, address(makerContract.router()), type(uint).max);
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    vm.expectRevert("SimpleRouter/NotApprovedByOwner");
    makerContract.checkList(tokens);
  }

  function test_e_checkList_completes() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    // passes a
    makerContract.approve(weth, $(mgv), type(uint).max);
    // passes b
    router.bind(address(makerContract));
    // passes c
    makerContract.approve(weth, address(makerContract.router()), type(uint).max);
    // passes d
    weth.approve(address(makerContract.router()), type(uint).max);
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    makerContract.checkList(tokens);
    // ^^ should not throw
  }

  function test_activate_completes_checkList_for_deployer() public {
    IERC20[] memory tokens = dynamic([IERC20(weth), usdc]);
    // reserve approves router for weth transfer
    address toApprove =
      makerContract.router() == makerContract.NO_ROUTER() ? address(makerContract) : address(makerContract.router());

    vm.startPrank(deployer);
    weth.approve(toApprove, type(uint).max);
    usdc.approve(toApprove, type(uint).max);

    makerContract.activate(tokens);
    makerContract.checkList(tokens);
    vm.stopPrank();
  }

  function test_activate_throws_if_approve_mangrove_fails() public {
    // asks weth contract to return false to approve and transfer calls
    weth.failSoftly(true);
    vm.expectRevert("mgvOffer/approveMangrove/Fail");
    vm.prank(deployer);
    makerContract.activate(dynamic([IERC20(weth)]));
  }

  function test_offerGasreq_with_no_router_is_constant() public {
    assertEq(makerContract.OFFER_GASREQ(), makerContract.offerGasreq(), "Incorrect gasreq for offer");
  }

  // makerExecute and makerPosthook guards
  function testCannot_call_makerExecute_if_not_Mangrove() public {
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = address(weth);
    order.inbound_tkn = address(usdc);
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.makerExecute(order);
    vm.prank(address(mgv));
    bytes32 ret = makerContract.makerExecute(order);
    assertEq(ret, "lastlook/testdata", "Incorrect returned data");
  }

  function testCannot_call_makerPosthook_if_not_Mangrove() public {
    MgvLib.SingleOrder memory order;
    MgvLib.OrderResult memory result;
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.makerPosthook(order, result);
    vm.prank(address(mgv));
    makerContract.makerPosthook(order, result);
  }

  function test_failed_trade_is_logged() public {
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

  function test_failed_to_repost_is_logged() public {
    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockBuyOrder({
      takerGives: 1500 * 10 ** 6,
      takerWants: 1 ether,
      partialFill: 2, // half of offer is consummed
      base_: weth,
      quote_: usdc,
      makerData: "whatever"
    });
    expectFrom(address(makerContract));
    emit LogIncident(IMangrove($(mgv)), weth, usdc, 0, "whatever", "mgv/updateOffer/unauthorized");
    vm.expectRevert("posthook/failed");
    /// since order.offerId is 0, updateOffer will revert. This revert should be caught and logged
    vm.prank($(mgv));
    makerContract.makerPosthook(order, result);
  }

  function test_lastLook_returned_value_is_passed() public {
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = $(weth);
    order.inbound_tkn = $(usdc);
    vm.prank(address(mgv));
    bytes32 data = makerContract.makerExecute(order);
    assertEq(data, "lastlook/testdata");
  }

  function test_admin_can_withdrawFromMangrove() public {
    assertEq(mgv.balanceOf(address(makerContract)), 0, "incorrect balance");
    mgv.fund{value: 1 ether}(address(makerContract));
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.withdrawFromMangrove(0.5 ether, deployer);
    uint balMaker = deployer.balance;
    vm.prank(deployer);
    makerContract.withdrawFromMangrove(0.5 ether, deployer);
    assertEq(mgv.balanceOf(address(makerContract)), 0.5 ether, "incorrect balance");
    assertEq(deployer.balance, balMaker + 0.5 ether, "incorrect balance");
  }

  function test_admin_can_WithdrawAllFromMangrove() public {
    mgv.fund{value: 1 ether}(address(makerContract));
    vm.prank(deployer);
    makerContract.withdrawFromMangrove(type(uint).max, deployer);
    assertEq(mgv.balanceOf(address(makerContract)), 0 ether, "incorrect balance");
    assertEq(deployer.balance, 1 ether, "incorrect balance");
  }

  function test_offerGasreq_takes_new_router_into_account() public {
    uint gasreq = makerContract.offerGasreq();
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    router.setAdmin(address(makerContract));
    makerContract.setRouter(router);
    assertEq(makerContract.offerGasreq(), gasreq + router.routerGasreq(), "incorrect gasreq");
    vm.stopPrank();
  }

  function test_get_fail_reverts() public {
    MgvLib.SingleOrder memory order;
    deal($(usdc), $(this), 0);
    order.outbound_tkn = address(usdc);
    order.wants = 10 ** 6;
    vm.expectRevert("mgvOffer/abort/getFailed");
    vm.prank($(mgv));
    makerContract.makerExecute(order);
  }

  function test_withdrawFromMangrove_reverts_with_good_reason_if_caller_cannot_receive() public {
    TestSender(deployer).refuseNative();
    mgv.fund{value: 0.1 ether}(address(makerContract));
    vm.expectRevert("mgvOffer/weiTransferFail");
    vm.prank(deployer);
    makerContract.withdrawFromMangrove(0.1 ether, $(this));
  }

  function test_setRouter_logs_SetRouter() public {
    vm.expectEmit(true, true, true, false, address(makerContract));
    emit SetRouter(address(0));
    vm.startPrank(deployer);
    makerContract.setRouter(AbstractRouter(address(0)));
  }

  function test_setAdmin_logs_SetAdmin() public {
    vm.expectEmit(true, true, true, false, address(makerContract));
    emit SetAdmin(deployer);
    vm.startPrank(deployer);
    makerContract.setAdmin(deployer);
  }
}
