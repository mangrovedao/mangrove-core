// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "src/strategies/offer_maker/OfferMaker.sol";
import "src/strategies/routers/SimpleRouter.sol";
import {t_of_struct as packOffer} from "src/preprocessed/MgvOffer.post.sol";

contract MangroveOfferTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable deployer;
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

  event SetAdmin(address);
  event SetRouter(address);
  event SetReserve(address, address);

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

    deployer = freshAddress("deployer");
    vm.prank(deployer);
    makerContract = new OfferMaker({
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

  function test_activate_passes_checkList_for_deployer() public {
    IERC20[] memory tokens = dynamic([IERC20(weth), usdc]);
    vm.startPrank(deployer);
    makerContract.activate(tokens);
    makerContract.checkList(tokens);
    vm.stopPrank();
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

  function test_checkList_takes_new_router_into_account() public {
    vm.startPrank(deployer);
    SimpleRouter router = new SimpleRouter();
    makerContract.setRouter(router);
    router.bind($(makerContract));

    IERC20[] memory tokens = dynamic([IERC20(weth), usdc]);
    vm.expectRevert("mgvOffer/LogicMustApproveMangrove");
    makerContract.checkList(tokens);

    makerContract.activate(tokens);
    vm.expectRevert("SimpleRouter/NotApprovedByReserve");
    makerContract.checkList(tokens);

    weth.approve($(router), type(uint).max);
    usdc.approve($(router), type(uint).max);
    makerContract.checkList(tokens);

    vm.stopPrank();
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
    // getting a contract that reverts on `receive()` call
    TestTaker maker_ = new TestTaker(mgv, weth, usdc);
    maker_.refuseNative();
    vm.prank(deployer);
    makerContract.setAdmin(address(maker_));
    mgv.fund{value: 0.1 ether}(address(makerContract));
    vm.expectRevert("mgvOffer/withdrawFromMgvFail");
    vm.prank(address(maker_));
    makerContract.withdrawFromMangrove(0.1 ether, $(this));
  }

  function test_setRouter_logs_SetRouter() public {
    vm.expectEmit(true, true, true, false, address(makerContract));
    emit SetRouter(address(0));
    vm.startPrank(deployer);
    makerContract.setRouter(AbstractRouter(address(0)));
  }

  function test_setReserve_logs_SetReserve() public {
    vm.expectEmit(true, true, true, false, address(makerContract));
    emit SetReserve(deployer, address(0));
    vm.startPrank(deployer);
    makerContract.setReserve(deployer, address(0));
  }

  function test_setAdmin_logs_SetAdmin() public {
    vm.expectEmit(true, true, true, false, address(makerContract));
    emit SetAdmin(deployer);
    vm.startPrank(deployer);
    makerContract.setAdmin(deployer);
  }
}
