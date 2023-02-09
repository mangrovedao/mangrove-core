// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {SimpleRouter} from "mgv_src/strategies/routers/SimpleRouter.sol";
import {OfferLogicTest, console, TestSender} from "mgv_test/strategies/unit/OfferLogic.t.sol";
import {ForwarderTester, ITesterContract as ITester} from "mgv_src/strategies/offer_forwarder/ForwarderTester.sol";
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
    IMangrove mangrove, IERC20 indexed outbound_tkn, IERC20 indexed inbound_tkn, uint indexed offerId, address maker
  );

  function setupMakerContract() internal virtual override {
    deployer = freshAddress("deployer");
    vm.deal(deployer, 10 ether);

    vm.prank(deployer);
    forwarder = new ForwarderTester({
      mgv: IMangrove($(mgv)),
      deployer: deployer
    });
    owner = payable(address(new TestSender()));
    vm.deal(owner, 10 ether);

    makerContract = ITester(address(forwarder)); // to use for all non `IForwarder` specific tests.
    // reserve (which is maker here) approves contract's router
    vm.startPrank(owner);
    usdc.approve(address(makerContract.router()), type(uint).max);
    weth.approve(address(makerContract.router()), type(uint).max);
    vm.stopPrank();
  }

  function fundStrat() internal virtual override {
    deal($(weth), owner, 1 ether);
    deal($(usdc), owner, cash(usdc, 2000));
  }

  function test_checkList_fails_if_caller_has_not_approved_router() public {
    vm.expectRevert("SimpleRouter/NotApprovedByOwner");
    vm.prank(freshAddress());
    makerContract.checkList(dynamic([IERC20(usdc), weth]));
  }

  function test_derived_gasprice_is_accurate_enough(uint fund) public {
    vm.assume(fund >= makerContract.getMissingProvision(weth, usdc, type(uint).max, 0, 0));
    vm.assume(fund < 5 ether); // too high provision would yield a gasprice overflow
    uint contractOldBalance = mgv.balanceOf(address(makerContract));
    vm.prank(owner);
    uint offerId = makerContract.newOffer{value: fund}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
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
    vm.prank(owner);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      pivotId: 0
    });
    uint old_gasprice = mgv.offerDetails(address(weth), address(usdc), offerId).gasprice();
    vm.prank(owner);
    makerContract.updateOffer{value: 0.2 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      pivotId: 0,
      offerId: offerId
    });
    assertTrue(
      old_gasprice < mgv.offerDetails(address(weth), address(usdc), offerId).gasprice(),
      "Gasprice not updated as expected"
    );
  }

  function test_failed_offer_reaches_posthookFallback() public {
    MgvLib.SingleOrder memory order;
    MgvLib.OrderResult memory result;
    vm.prank(owner);
    uint offerId = makerContract.newOffer{value: 1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
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

  function test_failed_offer_credits_maker(uint fund) public {
    vm.assume(fund >= makerContract.getMissingProvision(weth, usdc, type(uint).max, 0, 0));
    vm.assume(fund < 5 ether);
    vm.prank(owner);
    uint offerId = makerContract.newOffer{value: fund}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
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
    assertTrue((approx_bounty * 10000) / bounty > 9990, "Approximation of offer maker's credit is too coarse");
    assertTrue(provision_after_fail < mgv.balanceOf(address(makerContract)), "Incorrect approx");
  }

  function test_makership() public {
    vm.startPrank(owner);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      pivotId: 0
    });
    assertEq(forwarder.ownerOf(weth, usdc, offerId), owner, "Invalid makership relation");
  }

  function test_NewOwnedOffer_logging() public {
    (, MgvStructs.LocalPacked local) = mgv.config($(weth), $(usdc));
    uint next_id = local.last() + 1;
    vm.expectEmit(true, true, true, false, address(forwarder));
    emit NewOwnedOffer(IMangrove($(mgv)), weth, usdc, next_id, owner);

    vm.startPrank(owner);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      pivotId: 0
    });
    assertEq(next_id, offerId, "Unexpected offer id");
  }

  function test_provision_too_high_reverts() public {
    vm.expectRevert("Forwarder/provisionTooHigh");

    vm.startPrank(owner);
    makerContract.newOffer{value: 10 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      pivotId: 0
    });
    vm.stopPrank();
  }

  function test_updateOffer_with_no_funds_preserves_gasprice() public {
    vm.startPrank(owner);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      pivotId: 0
    });
    vm.stopPrank();
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(weth), $(usdc), offerId);
    uint old_gasprice = detail.gasprice();

    vm.startPrank(owner);
    makerContract.updateOffer({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1.1 ether,
      pivotId: 0,
      offerId: offerId
    });
    vm.stopPrank();
    detail = mgv.offerDetails($(weth), $(usdc), offerId);
    assertEq(old_gasprice, detail.gasprice(), "Gas price was changed");
  }

  function test_updateOffer_with_funds_increases_gasprice() public {
    vm.startPrank(owner);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      pivotId: 0
    });
    vm.stopPrank();
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(weth), $(usdc), offerId);
    uint old_gasprice = detail.gasprice();
    vm.startPrank(owner);
    makerContract.updateOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1.1 ether,
      pivotId: 0,
      offerId: offerId
    });
    vm.stopPrank();
    detail = mgv.offerDetails($(weth), $(usdc), offerId);
    assertTrue(old_gasprice < detail.gasprice(), "Gas price was not increased");
  }

  function test_different_maker_can_post_offers() public {
    vm.startPrank(owner);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
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
      pivotId: 0
    });
    assertEq(forwarder.ownerOf(weth, usdc, offerId_), new_maker, "Incorrect maker");
    assertEq(forwarder.ownerOf(weth, usdc, offerId), owner, "Incorrect maker");
  }

  function test_put_fail_reverts_with_expected_reason() public {
    MgvLib.SingleOrder memory order;
    vm.prank(owner);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      pivotId: 0
    });

    vm.startPrank(owner);
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
}
