// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {GenericFork} from "mgv_test/lib/forks/Generic.sol";
import {
  ITesterContract as ITester,
  DirectTester,
  IMangrove,
  IERC20,
  AbstractRouter
} from "mgv_src/strategies/offer_maker/DirectTester.sol";

// unit tests for (single /\ multi) user strats (i.e unit tests that are non specific to either single or multi user feature

contract OfferLogicTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  address payable taker;
  address payable deployer;
  address reserve;
  ITester makerContract; // can be either OfferMaker or OfferForwarder
  GenericFork fork;

  // tracking IOfferLogic logs
  event LogIncident(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 makerData,
    bytes32 mgvData
  );

  function setUp() public virtual override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;

    // if a fork is initialized, we set it up and do a manual testing setup
    if (address(fork) != address(0)) {
      fork.setUp();
      mgv = setupMangrove();
      weth = TestToken(fork.get("WETH"));
      usdc = TestToken(fork.get("USDC"));
      setupMarket(weth, usdc);
      // otherwise, a generic local setup works
    } else {
      // deploying mangrove and opening WETH/USDC market.
      super.setUp();
      // rename for convenience
      weth = base;
      usdc = quote;
    }
    maker = payable(new TestSender());
    vm.deal(maker, 10 ether);
    // for Direct strats, maker is deployer
    deployer = deployer == address(0) ? maker : deployer;

    taker = payable(new TestSender());
    vm.deal(taker, 1 ether);
    deal($(weth), taker, cash(weth, 50));
    deal($(usdc), taker, cash(usdc, 100_000));
    // letting taker take bids and asks on mangrove
    vm.startPrank(taker);
    weth.approve(address(mgv), type(uint).max);
    usdc.approve(address(mgv), type(uint).max);
    vm.stopPrank();

    // instanciates makerContract
    setupMakerContract();
    setupLiquidityRouting();
    // dealing 1 eth and 2000$ to maker's reserve on contract
    vm.startPrank(maker);
    deal($(weth), makerContract.reserve(maker), 1 ether);
    deal($(usdc), makerContract.reserve(maker), cash(usdc, 2000));
    vm.stopPrank();
    vm.prank(deployer);
    makerContract.activate(dynamic([IERC20(weth), usdc]));
  }

  // override this to use Forwarder strats
  function setupMakerContract() internal virtual {
    vm.prank(deployer);
    makerContract = new DirectTester({
      mgv: IMangrove($(mgv)),
      router_: AbstractRouter(address(0)),
      deployer: deployer
    });
    vm.prank(maker);
    makerContract.setReserve(maker, address(makerContract));
  }

  // override this function to use a specific router for the strat
  function setupLiquidityRouting() internal virtual {}

  function test_checkList() public {
    vm.startPrank(maker);
    makerContract.checkList(dynamic([IERC20(weth), usdc]));
    vm.stopPrank();
  }

  function testCannot_setReserve() public {
    vm.expectRevert("AccessControlled/Invalid");
    makerContract.setReserve(freshAddress(), freshAddress());
  }

  function test_maker_can_post_newOffer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    assertTrue(offerId != 0);
  }

  function test_getMissingProvision_is_enough_to_post_newOffer() public {
    vm.startPrank(maker);
    uint offerId = makerContract.newOffer{value: makerContract.getMissingProvision(weth, usdc, type(uint).max, 0, 0)}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    vm.stopPrank();
    assertTrue(offerId != 0);
  }

  function test_getMissingProvision_is_strict() public {
    uint minProv = makerContract.getMissingProvision(weth, usdc, type(uint).max, 0, 0);
    vm.expectRevert("mgv/insufficientProvision");
    vm.prank(maker);
    makerContract.newOffer{value: minProv - 1}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
  }

  function test_newOffer_fails_when_provision_is_zero() public {
    vm.expectRevert("mgv/insufficientProvision");
    vm.prank(maker);
    makerContract.newOffer{value: 0}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
  }

  function test_provisionOf_returns_zero_if_offer_does_not_exist() public {
    assertEq(makerContract.provisionOf(weth, usdc, 0), 0, "Invalid returned provision");
  }

  function test_maker_can_deprovision_Offer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    uint makerBalWei = maker.balance;
    uint locked = makerContract.provisionOf(weth, usdc, offerId);
    vm.prank(maker);
    uint deprovisioned = makerContract.retractOffer(weth, usdc, offerId, true);
    // checking WEIs are returned to maker's account
    assertEq(maker.balance, makerBalWei + deprovisioned, "Incorrect WEI balance");
    // checking that the totality of the provisions is returned
    assertEq(deprovisioned, locked, "Deprovision was incomplete");
  }

  function test_mangrove_can_deprovision_offer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    uint makerBalWei = maker.balance;
    uint locked = makerContract.provisionOf(weth, usdc, offerId);
    vm.prank(address(mgv));
    // returned provision is sent to offer owner
    uint deprovisioned = makerContract.retractOffer(weth, usdc, offerId, true);
    // checking WEIs are returned to maker's account
    assertEq(maker.balance, makerBalWei + deprovisioned, "Incorrect WEI balance");
    // checking that the totality of the provisions is returned
    assertEq(deprovisioned, locked, "Deprovision was incomplete");
  }

  function test_deprovision_twice_returns_no_fund() public {
    vm.startPrank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    makerContract.retractOffer(weth, usdc, offerId, true);
    uint received_wei = makerContract.retractOffer(weth, usdc, offerId, true);
    vm.stopPrank();
    assertEq(received_wei, 0, "Unexpected received weis");
  }

  function test_deprovisionOffer_throws_if_wei_transfer_fails() public {
    TestSender(maker).refuseNative();
    vm.startPrank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    vm.expectRevert("mgvOffer/weiTransferFail");
    makerContract.retractOffer(weth, usdc, offerId, true);
    vm.stopPrank();
  }

  function test_maker_can_updateOffer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });

    vm.prank(maker);
    makerContract.updateOffer({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: offerId,
      offerId: offerId
    });
  }

  function test_only_maker_can_updateOffer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(freshAddress());
    makerContract.updateOffer({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: offerId,
      offerId: offerId
    });
  }

  function test_updateOffer_fails_when_provision_is_too_low() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    mgv.setGasprice(type(uint16).max);
    vm.expectRevert("mgv/insufficientProvision");
    vm.prank(maker);
    makerContract.updateOffer({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: offerId,
      offerId: offerId
    });
  }

  function performTrade(bool success) internal returns (uint takergot, uint takergave, uint bounty, uint fee) {
    vm.startPrank(maker);
    // ask 2000 USDC for 1 weth
    makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    vm.stopPrank();

    // taker has approved mangrove in the setUp
    vm.startPrank(taker);
    (takergot, takergave, bounty, fee) = mgv.marketOrder({
      outbound_tkn: address(weth),
      inbound_tkn: address(usdc),
      takerWants: 0.5 ether,
      takerGives: cash(usdc, 1000),
      fillWants: true
    });
    vm.stopPrank();
    assertTrue(!success || (bounty == 0 && takergot > 0), "unexpected trade result");
  }

  function test_reserve_balance_is_updated_when_trade_succeeds() public {
    vm.startPrank(maker);
    uint balOut = makerContract.tokenBalance(weth, maker);
    uint balIn = makerContract.tokenBalance(usdc, maker);
    vm.stopPrank();

    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade(true);
    assertTrue(bounty == 0 && takergot > 0, "trade failed");

    vm.startPrank(maker);
    assertEq(makerContract.tokenBalance(weth, maker), balOut - (takergot + fee), "incorrect out balance");
    assertEq(makerContract.tokenBalance(usdc, maker), balIn + takergave, "incorrect in balance");
    vm.stopPrank();
  }

  function test_reposting_fails_with_expected_reason_when_below_density() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    MgvLib.OrderResult memory result;
    result.mgvData = "mgv/tradeSuccess";
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = $(weth);
    order.inbound_tkn = $(usdc);
    order.offerId = offerId;
    order.wants = 0.999999999999999 ether;
    order.gives = cash(usdc, 2000) - 1;
    /* `offerDetail` is only populated when necessary. */
    order.offerDetail = mgv.offerDetails($(weth), $(usdc), offerId);
    order.offer = mgv.offers($(weth), $(usdc), offerId);
    (order.global, order.local) = mgv.config($(weth), $(usdc));
    vm.expectRevert("mgv/writeOffer/density/tooLow");
    vm.prank($(mgv));
    makerContract.makerPosthook(order, result);
  }

  function test_reposting_fails_with_expected_reason_when_underprovisioned() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    mgv.setGasprice(1000);
    vm.startPrank(deployer);
    makerContract.withdrawFromMangrove(mgv.balanceOf(address(makerContract)), payable(deployer));
    vm.stopPrank();

    MgvLib.OrderResult memory result;
    result.mgvData = "mgv/tradeSuccess";
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = $(weth);
    order.inbound_tkn = $(usdc);
    order.offerId = offerId;
    order.wants = 0.5 ether;
    order.gives = cash(usdc, 1000);
    /* `offerDetail` is only populated when necessary. */
    order.offerDetail = mgv.offerDetails($(weth), $(usdc), offerId);
    order.offer = mgv.offers($(weth), $(usdc), offerId);
    (order.global, order.local) = mgv.config($(weth), $(usdc));
    vm.expectRevert("mgv/insufficientProvision");
    vm.prank($(mgv));
    makerContract.makerPosthook(order, result);
  }

  function test_reposting_fails_with_expected_reason_when_innactive() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      pivotId: 0
    });
    mgv.deactivate($(weth), $(usdc));
    MgvLib.OrderResult memory result;
    result.mgvData = "mgv/tradeSuccess";
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = $(weth);
    order.inbound_tkn = $(usdc);
    order.offerId = offerId;
    order.wants = 0.5 ether;
    order.gives = cash(usdc, 1000);
    /* `offerDetail` is only populated when necessary. */
    order.offerDetail = mgv.offerDetails($(weth), $(usdc), offerId);
    order.offer = mgv.offers($(weth), $(usdc), offerId);
    (order.global, order.local) = mgv.config($(weth), $(usdc));
    vm.expectRevert("posthook/failed");
    vm.prank($(mgv));
    makerContract.makerPosthook(order, result);
  }
}
