// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {SimpleRouter} from "src/strategies/routers/SimpleRouter.sol";
import {OfferLogicTest, console} from "mgv_test/strategies/unit/OfferLogic.t.sol";
import {
  OfferForwarder, IForwarder, IMangrove, IERC20, IMakerLogic
} from "src/strategies/offer_forwarder/OfferForwarder.sol";
import {MgvStructs, MgvLib} from "src/MgvLib.sol";

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

  function test_derivedGaspriceIsAccurateEnough(uint fund) public {
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

  function test_updateOfferWithFundsUpdatesGasprice() public {
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

  function test_failedOfferCreditsOwner(uint fund) public {
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

  function test_logging() public {
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

  function test_provisionTooHighReverts() public {
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

  function test_updateOfferWithNoFundsPreservesGasprice() public {
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

  function test_updateOfferWithFundsIncreasesGasprice() public {
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

  function test_putFailRevertsWithExpectedReason() public {
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
}
