// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";
import "mgv_src/toy_strategies/offer_maker/Ghost.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

import {console} from "forge-std/console.sol";

contract GhostTest is MangroveTest {
  IERC20 weth;
  IERC20 dai;
  IERC20 usdc;

  PolygonFork fork;

  address payable taker;

  uint offerId1;
  uint offerId2;

  Ghost strat;

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork();
    fork.setUp();

    // use convenience helpers to setup Mangrove
    mgv = setupMangrove();
    mgv.setVault($(mgv));

    // setup tokens, markets and approve them
    dai = IERC20(fork.get("DAI"));
    weth = IERC20(fork.get("WETH"));
    usdc = IERC20(fork.get("USDC"));

    options.defaultFee = 30;
    setupMarket(dai, weth);
    setupMarket(usdc, weth);
    setupMarket(dai, usdc);

    weth.approve($(mgv), type(uint).max);
    dai.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);

    // setup separate taker and give some native token (for gas) + USDC and DAI
    taker = freshAddress("taker");
    vm.deal(taker, 10_000_000);

    deal($(usdc), taker, cash(usdc, 10_000));
    deal($(dai), taker, cash(dai, 10_000));

    // approve DAI and USDC on Mangrove for taker
    vm.startPrank(taker);
    dai.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);
    vm.stopPrank();
  }

  function test_run() public {
    deployStrat();

    execTraderStrat();
  }

  function deployStrat() public {
    strat = new Ghost({
      mgv: IMangrove($(mgv)),
      base: weth,
      stable1: usdc, 
      stable2: dai,
      admin: $(this) // for ease, set this contract (will be Test runner) as admin for the strat
      });

    // set offerGasReq to overapproximate the gas required to handle trade and posthook
    strat.setGasreq(250_000);

    // make sure the strat is funded on MGV
    mgv.fund{value: 2 ether}($(strat));

    vm.startPrank($(strat));
    // allow (the router to) pull of WETH from Ghost (i.e., strat) to Mangrove
    weth.approve($(mgv), type(uint).max);

    // allow the router to push the WETH from Ghost (i.e., strat) to $(this) contract
    // (this will happen in the posthook)
    weth.approve($(strat.router()), type(uint).max);
    vm.stopPrank();

    // give some WETH (i.e., base) to strat
    deal($(weth), $(strat), cash(weth, 10));

    // NOTE:
    // For this test, we're locking base, ie WETH, in the vault of the contract
    // - so Ghost is not really used for ghost liqudity, in this example.
    // However, to employ actual ghost liquidity it is simply a matter of
    // setting up a more refined router.
  }

  function execTraderStrat() public {
    // post offers with Ghost liquidity

    uint makerGivesAmount = 0.15 ether;
    uint makerWantsAmount = 300 ether;

    (offerId1, offerId2) = strat.newGhostOffers({
      gives: makerGivesAmount, // WETH
      wants1: makerWantsAmount, // DAI
      wants2: makerWantsAmount, // USDC
      pivot1: 0,
      pivot2: 0
    });

    // check that we actually need to activate for the two 'wants' tokens
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = dai;
    tokens[1] = usdc;

    vm.expectRevert("MangroveOffer/LogicMustApproveMangrove");
    strat.checkList(tokens);

    // and now activate them
    strat.activate(tokens);

    // try to snipe one of the offers (using the separate taker account)
    vm.startPrank(taker);
    (, uint got, uint gave,,) = mgv.snipes({
      outbound_tkn: $(weth),
      inbound_tkn: $(dai),
      targets: wrap_dynamic([offerId1, 0.15 ether, 300 ether, type(uint).max]),
      fillWants: true
    });
    vm.stopPrank();

    // assert that
    assertEq(got, minusFee($(dai), $(weth), makerGivesAmount), "taker got wrong amount");
    assertEq(gave, makerWantsAmount, "taker gave wrong amount");

    // assert that neither offer posted by Ghost are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_dai = mgv.offers($(weth), $(dai), offerId1);
    MgvStructs.OfferPacked offer_on_usdc = mgv.offers($(weth), $(usdc), offerId2);
    assertTrue(!mgv.isLive(offer_on_dai), "weth->dai offer should have been retracted");
    assertTrue(!mgv.isLive(offer_on_usdc), "weth->usdc offer should have been retracted");
  }
}
