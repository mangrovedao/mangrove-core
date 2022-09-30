import "mgv_src/strategies/routers/SimpleRouter.sol";

// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import "mgv_src/strategies/offer_forwarder/OfferForwarder.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

contract OfferForwarderTest is OfferLogicTest {
  function setupMakerContract() internal virtual override prank(maker) {
    makerContract = new OfferForwarder({
      mgv: IMangrove($(mgv)),
      deployer: maker
    });
    // reserve (which is maker here) approves contract's router
    usdc.approve(address(makerContract.router()), type(uint).max);
    weth.approve(address(makerContract.router()), type(uint).max);
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
    vm.startPrank(maker);
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
    makerContract.approve(weth, address(mgv), 0);
    vm.stopPrank();
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
  }
}
