// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {SimpleRouter} from "mgv_src/strategies/routers/SimpleRouter.sol";
import {OfferLogicTest, console} from "mgv_test/strategies/unit/OfferLogic.t.sol";
import {OfferForwarder, IMakerLogic} from "mgv_src/strategies/offer_forwarder/OfferForwarder.sol";
import {IForwarder, IMangrove, IERC20} from "mgv_src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {MgvStructs, MgvLib} from "mgv_src/MgvLib.sol";

contract OfferForwarderTest is OfferLogicTest {
  IForwarder forwarder;

  function setUp() public virtual override {
    deployer = freshAddress("deployer");
    vm.deal(deployer, 10 ether);
    super.setUp();
  }

  event NewOwnedOffer(
    IMangrove mangrove, IERC20 indexed outbound_tkn, IERC20 indexed inbound_tkn, uint indexed offerId, address owner
  );

  event ReserveApproval(address indexed reserve_, address indexed maker, bool isApproved);

  function setupMakerContract() internal virtual override {
    vm.prank(deployer);
    forwarder = new OfferForwarder({
      mgv: IMangrove($(mgv)),
      deployer: deployer
    });
    makerContract = IMakerLogic(address(forwarder)); // to use for all non `IForwarder` specific tests.
    // reserve (which is maker here) approves contract's router
    vm.startPrank(maker);
    usdc.approve(address(makerContract.router()), type(uint).max);
    weth.approve(address(makerContract.router()), type(uint).max);
    vm.stopPrank();
  }

  function test_derived_gasprice_is_accurate_enough(uint fund) public {
    vm.assume(fund >= makerContract.getMissingProvision(weth, usdc, type(uint).max, 0, 0));
    vm.assume(fund < 5 ether); // too high provision would yield a gasprice overflow
    uint contractOldBalance = mgv.balanceOf(address(makerContract));
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: fund}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    uint derived_gp = mgv.offerDetails(address(weth), address(usdc), offerId).gasprice();
    uint gasbase = mgv.offerDetails(address(weth), address(usdc), offerId).offer_gasbase();
    uint gasreq = makerContract.offerGasreq();
    uint locked = derived_gp * (gasbase + gasreq) * 10 ** 9;
    uint leftover = fund - locked;
    assertEq(mgv.balanceOf(address(makerContract)), contractOldBalance + leftover, "Invalid contract balance");
    console.log("counterexample:", locked, fund, (locked * 1000) / fund);
    assertTrue((locked * 10) / fund >= 9, "rounding exceeds admissible error");
  }

  function test_updateOffer_with_funds_updates_gasprice() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    uint old_gasprice = mgv.offerDetails(address(weth), address(usdc), offerId).gasprice();
    vm.prank(maker);
    makerContract.updateOffer{value: 0.2 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0,
      offerId: offerId
    });
    assertTrue(
      old_gasprice < mgv.offerDetails(address(weth), address(usdc), offerId).gasprice(),
      "Gasprice not updated as expected"
    );
  }

  function test_updateOffer_with_more_gasreq_reduces_gasprice_when_no_fund_is_added() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: makerContract.offerGasreq(),
      gasprice: 0,
      pivotId: 0
    });
    uint old_gasprice = mgv.offerDetails(address(weth), address(usdc), offerId).gasprice();
    vm.prank(maker);
    makerContract.updateOffer({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: makerContract.offerGasreq()*2,
      gasprice: 0,
      pivotId: 0,
      offerId: offerId
    });
    assertTrue(
      old_gasprice > mgv.offerDetails(address(weth), address(usdc), offerId).gasprice(),
      "Gasprice not updated as expected"
    );
  }

  function test_updateOffer_with_less_gasreq_increases_gasprice() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: makerContract.offerGasreq(),
      gasprice: 0,
      pivotId: 0
    });
    uint old_gasprice = mgv.offerDetails(address(weth), address(usdc), offerId).gasprice();
    uint old_makerBalance = mgv.balanceOf(address(makerContract));
    vm.prank(maker);
    makerContract.updateOffer({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: makerContract.offerGasreq()/2,
      gasprice: 0,
      pivotId: 0,
      offerId: offerId
    });
    assertTrue(
      old_gasprice < mgv.offerDetails(address(weth), address(usdc), offerId).gasprice(),
      "Gasprice not updated as expected"
    );
    assertEq(
      old_makerBalance,
      mgv.balanceOf(address(makerContract)),
      "Maker balance should not increase"
    );
  }

  function test_failed_offer_reaches_posthookFallback() public {
    MgvLib.SingleOrder memory order;
    MgvLib.OrderResult memory result;
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    result.mgvData = "anythingButSuccess";
    result.makerData = "failReason";
    order.offerId = offerId;
    order.outbound_tkn = $(weth);
    order.inbound_tkn = $(usdc);
    order.offer = mgv.offers($(weth), $(usdc), offerId);
    order.offerDetail = mgv.offerDetails($(weth), $(usdc), offerId);
    // this should reach the posthookFallback and computes released provision, assuming offer has failed for half gasreq
    // as a result the amount of provision that can be redeemed by retracting offerId should increase.
    vm.startPrank($(mgv));
    makerContract.makerPosthook{gas: makerContract.offerGasreq() / 2}(order, result);
    vm.stopPrank();
    assertTrue(makerContract.provisionOf(weth, usdc, offerId) > 1 ether, "fallback was not reached");
  }

  function test_failed_offer_credits_owner(uint fund) public {
    vm.assume(fund >= makerContract.getMissingProvision(weth, usdc, type(uint).max, 0, 0));
    vm.assume(fund < 5 ether);
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: fund}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    // revoking Mangrove's approvals to make `offerId` fail
    vm.prank(deployer);
    makerContract.approve(weth, address(mgv), 0);
    uint provision = makerContract.provisionOf(weth, usdc, offerId);
    console.log("provision before fail:", provision);

    // taker has approved mangrove in the setUp
    vm.startPrank(taker);
    (uint takergot,, uint bounty,) = mgv.marketOrder({
      outbound_tkn: address(weth),
      inbound_tkn: address(usdc),
      takerWants: 0.5 ether,
      takerGives: cash(usdc, 1000),
      fillWants: true
    });
    vm.stopPrank();
    assertTrue(bounty > 0 && takergot == 0, "trade should have failed");
    uint provision_after_fail = makerContract.provisionOf(weth, usdc, offerId);
    console.log("provision after fail:", provision_after_fail);
    console.log("bounty", bounty);
    // checking that approx is small in front a storage write (approx < write_cost / 10)
    uint approx_bounty = provision - provision_after_fail;
    assertTrue((approx_bounty * 10000) / bounty > 9990, "Approximation of offer owner's credit is too coarse");
    assertTrue(provision_after_fail < mgv.balanceOf(address(makerContract)), "Incorrect approx");
  }

  function test_ownership() public {
    vm.startPrank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    assertEq(forwarder.ownerOf(weth, usdc, offerId), address(maker), "Invalid ownership relation");
  }

  function test_NewOwnedOffer_logging() public {
    (, MgvStructs.LocalPacked local) = mgv.config($(weth), $(usdc));
    uint next_id = local.last() + 1;
    vm.expectEmit(true, true, true, false, address(forwarder));
    emit NewOwnedOffer(IMangrove($(mgv)), weth, usdc, next_id, maker);

    vm.startPrank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    assertEq(next_id, offerId, "Unexpected offer id");
  }

  function test_provision_too_high_reverts() public {
    vm.expectRevert("Forwarder/provisionTooHigh");

    vm.startPrank(maker);
    makerContract.newOffer{value: 10 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    vm.stopPrank();
  }

  function test_updateOffer_with_no_funds_preserves_gasprice() public {
    vm.startPrank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    vm.stopPrank();
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(weth), $(usdc), offerId);
    uint old_gasprice = detail.gasprice();

    vm.startPrank(maker);
    makerContract.updateOffer({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1.1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0,
      offerId: offerId
    });
    vm.stopPrank();
    detail = mgv.offerDetails($(weth), $(usdc), offerId);
    assertEq(old_gasprice, detail.gasprice(), "Gas price was changed");
  }

  function test_updateOffer_with_funds_increases_gasprice() public {
    vm.startPrank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    vm.stopPrank();
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(weth), $(usdc), offerId);
    uint old_gasprice = detail.gasprice();
    vm.startPrank(maker);
    makerContract.updateOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1.1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0,
      offerId: offerId
    });
    vm.stopPrank();
    detail = mgv.offerDetails($(weth), $(usdc), offerId);
    assertTrue(old_gasprice < detail.gasprice(), "Gas price was not increased");
  }

  function test_different_maker_can_post_offers() public {
    vm.startPrank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    vm.stopPrank();
    address new_maker = freshAddress("New maker");
    vm.deal(new_maker, 1 ether);
    vm.prank(new_maker);
    uint offerId_ = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
    assertEq(forwarder.ownerOf(weth, usdc, offerId_), new_maker, "Incorrect owner");
    assertEq(forwarder.ownerOf(weth, usdc, offerId), maker, "Incorrect owner");
  }

  function test_default_reserve_for_maker_is_maker() public {
    assertEq(makerContract.reserve(maker), maker, "Incorrect default reserve");
  }

  function test_unnaproved_maker_cannot_set_non_0x_reserve() public {
    address new_reserve = freshAddress();
    vm.expectRevert("mgvOffer/makerNotApproved");
    vm.prank(maker);
    makerContract.setReserve(maker, new_reserve);
  }

  function test_maker_can_set_0x_reserve() public {
    vm.prank(maker);
    makerContract.setReserve(maker, address(0));
    assertEq(makerContract.reserve(maker), maker, "Reserve was not set");
  }

  function test_reserve_can_approveMaker() public {
    address new_reserve = freshAddress();
    vm.prank(new_reserve);
    forwarder.approvePooledMaker(maker);
    assertTrue(forwarder.reserveApprovals(new_reserve, maker), "approval failed");
  }

  function test_approve_maker_logs_ReserveApproval() public {
    address new_reserve = freshAddress();
    vm.expectEmit(true, true, true, false, address(forwarder));
    emit ReserveApproval(new_reserve, maker, true);
    vm.prank(new_reserve);
    forwarder.approvePooledMaker(maker);
  }

  function test_reserve_can_revoke_maker() public {
    address new_reserve = freshAddress();
    vm.startPrank(new_reserve);
    forwarder.approvePooledMaker(maker);
    forwarder.revokePooledMaker(maker);
    vm.stopPrank();
    assertTrue(!forwarder.reserveApprovals(new_reserve, maker), "revoke failed");
  }

  function test_revoke_maker_logs_ReserveApproval() public {
    address new_reserve = freshAddress();
    vm.expectEmit(true, true, true, false, address(forwarder));
    emit ReserveApproval(new_reserve, maker, false);
    vm.prank(new_reserve);
    forwarder.revokePooledMaker(maker);
  }

  function test_approved_maker_can_set_reserve() public {
    address new_reserve = freshAddress();
    vm.prank(new_reserve);
    forwarder.approvePooledMaker(maker);
    vm.prank(maker);
    makerContract.setReserve(maker, new_reserve);
    assertEq(makerContract.reserve(maker), new_reserve, "Reserve was not set");
  }

  function test_revokePooledMaker_sets_maker_reserve_to_0x() public {
    address new_reserve = freshAddress();
    vm.prank(new_reserve);
    forwarder.approvePooledMaker(maker);
    vm.prank(maker);
    makerContract.setReserve(maker, new_reserve);
    vm.prank(new_reserve);
    forwarder.revokePooledMaker(maker);
    assertEq(makerContract.reserve(maker), maker, "Reserve was not updated");
  }

  function test_put_fail_reverts_with_expected_reason() public {
    MgvLib.SingleOrder memory order;
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });

    vm.startPrank(maker);
    usdc.approve($(makerContract.router()), 0);
    vm.stopPrank();

    order.inbound_tkn = address(usdc);
    order.outbound_tkn = address(weth);
    order.gives = 10 ** 6;
    order.offerId = offerId;
    vm.expectRevert("mgvOffer/abort/putFailed");
    vm.prank($(mgv));
    makerContract.makerExecute(order);
  }

  function test_trade_succeeds_with_new_reserve() public {
    address new_reserve = freshAddress("new_reserve");
    vm.prank(new_reserve);
    forwarder.approvePooledMaker(maker);

    vm.prank(maker);
    makerContract.setReserve(maker, new_reserve);

    deal($(weth), new_reserve, 0.5 ether);
    deal($(weth), address(makerContract), 0);
    deal($(usdc), address(makerContract), 0);

    address toApprove = address(makerContract.router());
    toApprove = toApprove == address(0) ? address(makerContract) : toApprove;
    vm.startPrank(new_reserve);
    usdc.approve(toApprove, type(uint).max); // to push
    weth.approve(toApprove, type(uint).max); // to pull
    vm.stopPrank();
    (, uint takerGave,,) = performTrade(true, 70_000);
    vm.startPrank(maker);
    assertEq(takerGave, makerContract.tokenBalance(usdc, maker), "Incorrect reserve usdc balance");
    assertEq(makerContract.tokenBalance(weth, maker), 0, "Incorrect reserve weth balance");
    vm.stopPrank();
  }

  function test_owner_is_unchanged_when_mangrove_does_updateOffer() public {
    uint offerId = test_mangrove_can_updateOffer();
    assertEq(forwarder.ownerOf(weth, usdc, offerId), maker, "Invalid offer owner");
  }
}
