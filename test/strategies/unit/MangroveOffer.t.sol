// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {DirectTester, IMangrove, IERC20} from "mgv_src/strategies/offer_maker/DirectTester.sol";
import {SimpleRouter, AbstractRouter} from "mgv_src/strategies/routers/SimpleRouter.sol";
import {t_of_struct as packOffer} from "mgv_src/preprocessed/MgvOffer.post.sol";

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
      deployer: deployer
    });
  }

  function test_Admin_is_deployer() public {
    assertEq(makerContract.admin(), deployer, "Incorrect admin");
  }

  function testCannot_activate_if_not_admin() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.activate(dynamic([IERC20(weth), usdc]));
  }

  function test_checkList_fails_if_caller_is_not_admin() public {
    vm.expectRevert("Direct/onlyAdminCanOwnOffers");
    makerContract.checkList(dynamic([IERC20(weth)]));
  }

  function test_checkList_throws_if_reserve_approval_is_missing() public {
    vm.expectRevert("Direct/reserveMustApproveMakerContract");
    vm.prank(deployer);
    makerContract.checkList(dynamic([IERC20(weth)]));
  }

  function test_checkList_throws_if_Mangrove_is_not_approved() public {
    address toApprove =
      makerContract.router() == makerContract.NO_ROUTER() ? address(makerContract) : address(makerContract.router());

    vm.startPrank(makerContract.reserve(deployer));
    weth.approve(toApprove, type(uint).max);
    usdc.approve(toApprove, type(uint).max);
    vm.stopPrank();

    vm.expectRevert("mgvOffer/LogicMustApproveMangrove");
    vm.prank(deployer);
    makerContract.checkList(dynamic([IERC20(weth)]));
  }

  function test_checkList_takes_router_binding_into_account() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);
    vm.prank(deployer);
    makerContract.approve(weth, $(mgv), type(uint).max);

    vm.startPrank($(makerContract));
    weth.approve(address(makerContract.router()), type(uint).max);
    vm.stopPrank();

    vm.expectRevert("Router/CallerIsNotAnApprovedMakerContract");
    vm.prank(deployer);
    makerContract.checkList(tokens);
  }

  function test_checkList_takes_router_approval_into_account() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);

    vm.prank(deployer);
    makerContract.approve(weth, $(mgv), type(uint).max);

    vm.expectRevert("mgvOffer/LogicMustApproveRouter");
    vm.prank(deployer);
    makerContract.checkList(tokens);
  }

  function test_checkList_takes_reserve_approval_into_account() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    router.bind($(makerContract));
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);

    // makerContract approves Mangrove for weth transfer
    vm.prank(deployer);
    makerContract.approve(weth, $(mgv), type(uint).max);

    // makerContract approves its router for weth transfer
    vm.startPrank($(makerContract));
    weth.approve(address(makerContract.router()), type(uint).max);
    vm.stopPrank();

    // missing reserve approves router
    vm.expectRevert("SimpleRouter/NotApprovedByReserve");
    vm.prank(deployer);
    makerContract.checkList(tokens);
  }

  function test_checkList_succeeds_after_all_approvals_are_done() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    router.bind($(makerContract));
    vm.stopPrank();

    IERC20[] memory tokens = dynamic([IERC20(weth)]);

    // makerContract approves Mangrove for weth transfer
    vm.prank(deployer);
    makerContract.approve(weth, $(mgv), type(uint).max);

    // makerContract approves its router for weth transfer
    vm.startPrank($(makerContract));
    weth.approve(address(makerContract.router()), type(uint).max);
    vm.stopPrank();

    // reserve approves router for weth transfer
    vm.startPrank(makerContract.reserve(deployer));
    weth.approve(address(makerContract.router()), type(uint).max);
    vm.stopPrank();

    vm.prank(deployer);
    makerContract.checkList(tokens);
  }

  function test_activate_completes_checkList_for_deployer() public {
    IERC20[] memory tokens = dynamic([IERC20(weth), usdc]);
    // reserve approves router for weth transfer
    address toApprove =
      makerContract.router() == makerContract.NO_ROUTER() ? address(makerContract) : address(makerContract.router());

    vm.startPrank(makerContract.reserve(deployer));
    weth.approve(toApprove, type(uint).max);
    usdc.approve(toApprove, type(uint).max);
    vm.stopPrank();

    vm.startPrank(deployer);
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
    assertEq(ret, "mgvOffer/proceed", "Incorrect returned data");
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

  function test_lastLook_returned_value_is_passed() public {
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = $(weth);
    order.inbound_tkn = $(usdc);
    vm.prank(address(mgv));
    bytes32 data = makerContract.makerExecute(order);
    assertEq(data, "mgvOffer/proceed");
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
    deal($(usdc), makerContract.reserve($(this)), 0);
    order.outbound_tkn = address(usdc);
    order.wants = 10 ** 6;
    console.log(order.wants);
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
