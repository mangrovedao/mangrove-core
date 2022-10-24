// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {GenericFork} from "mgv_test/lib/forks/Generic.sol";
import "src/strategies/offer_maker/OfferMaker.sol";

// unit tests for (single /\ multi) user strats (i.e unit tests that are non specific to either single or multi user feature

contract OfferLogicTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  address payable taker;
  address payable deployer;
  address reserve;
  IMakerLogic makerContract; // can be either OfferMaker or OfferForwarder
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
    mgv.setVault(freshAddress("MgvTreasury"));
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
    makerContract = new OfferMaker({
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
      gasreq: type(uint).max,
      gasprice: 0,
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
      gasreq: type(uint).max,
      gasprice: 0,
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
      gasreq: type(uint).max,
      gasprice: 0,
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
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });
  }

  function test_maker_can_deprovision_Offer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: type(uint).max,
      gasprice: 0,
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
      gasreq: type(uint).max,
      gasprice: 0,
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
      gasreq: type(uint).max,
      gasprice: 0,
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
      gasreq: type(uint).max,
      gasprice: 0,
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
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });

    vm.prank(maker);
    makerContract.updateOffer({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: offerId,
      offerId: offerId
    });
  }

  function test_mangrove_can_updateOffer() public returns (uint) {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });

    vm.prank(address(mgv));
    makerContract.updateOffer({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: offerId,
      offerId: offerId
    });
    return offerId;
  }

  function test_updateOffer_fails_when_provision_is_too_low() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: type(uint).max,
      gasprice: 0,
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
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: offerId,
      offerId: offerId
    });
  }

  function performTrade(bool success) internal returns (uint, uint, uint, uint) {
    return performTrade(success, 0);
  }

  function performTrade(bool success, uint add_gasreq)
    internal
    returns (uint takergot, uint takergave, uint bounty, uint fee)
  {
    vm.startPrank(maker);
    // ask 2000 USDC for 1 weth
    makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: makerContract.offerGasreq() + add_gasreq,
      gasprice: 0,
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
    // for multi user contract `tokenBalance` returns the balance of msg.sender's reserve
    // so one needs to impersonate maker to obtain the correct balance
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

  function test_maker_can_withdrawTokens() public {
    // note in order to be routing strategy agnostic one cannot easily mockup a trade
    // for aave routers reserve will hold overlying while for simple router reserve will hold the asset
    uint balusdc = usdc.balanceOf(maker);

    (, uint takergave,,) = performTrade(true);
    vm.prank(maker);
    // this will be a noop when maker == reserve
    makerContract.withdrawToken(usdc, maker, takergave);
    assertEq(usdc.balanceOf(maker), balusdc + takergave, "withdraw failed");
  }

  function test_withdraw_0_token_skips_transfer() public {
    vm.prank(maker);
    require(makerContract.withdrawToken(usdc, maker, 0), "unexpected fail");
  }

  function test_withdrawToken_to_0x_fails() public {
    vm.expectRevert("mgvOffer/withdrawToken/0xReceiver");
    vm.prank(maker);
    makerContract.withdrawToken(usdc, address(0), 1);
  }
}
