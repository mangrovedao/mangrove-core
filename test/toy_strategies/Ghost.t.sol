// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";
import "src/toy_strategies/offer_maker/Ghost.sol";
import {MgvStructs} from "src/MgvLib.sol";

import {console} from "forge-std/console.sol";

contract GhostTest is MangroveTest {
  IERC20 weth;
  IERC20 dai;
  IERC20 usdc;

  PolygonFork fork;

  address payable taker;
  Ghost strat;

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork();
    fork.setUp();

    // use convenience helpers to setup Mangrove
    mgv = setupMangrove();

    // setup tokens, markets and approve them
    dai = IERC20(fork.get("DAI"));
    weth = IERC20(fork.get("WETH"));
    usdc = IERC20(fork.get("USDC"));

    setupMarket(dai, weth);
    setupMarket(usdc, weth);

    // setup separate taker and give some native token (for gas) + USDC and DAI
    taker = freshAddress("taker");
    deal(taker, 10_000_000);

    deal($(usdc), taker, cash(usdc, 10_000));
    deal($(dai), taker, cash(dai, 10_000));

    // approve DAI and USDC on Mangrove for taker
    vm.startPrank(taker);
    dai.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);
    vm.stopPrank();
  }

  function test_succes_fill() public {
    deployStrat();

    execTraderStratWithFillSucces();
  }

  function test_succes_partialFill() public {
    deployStrat();

    execTraderStratWithPartialFillSucces();
  }

  function test_fallback() public {
    deployStrat();

    execTraderStratWithFallback();
  }

  function deployStrat() public {
    strat = new Ghost({
      mgv: IMangrove($(mgv)),
      base: weth,
      stable1: usdc, 
      stable2: dai,
      admin: $(this) // for ease, set this contract (will be Test runner) as admin for the strat
      });

    // allow (the router to) pull of WETH from Ghost (i.e., strat) to Mangrove
    strat.approve(weth, $(mgv), type(uint).max);
    // allow the router to push the WETH from Ghost (i.e., strat) to $(this) contract
    // (this will happen in the posthook)
    strat.approve(weth, $(strat.router()), type(uint).max);

    // NOTE:
    // For this test, we're locking base, ie WETH, in the vault of the contract
    // - so Ghost is not really used for ghost liqudity, in this example.
    // However, to employ actual ghost liquidity it is simply a matter of
    // setting up a more refined router.
    // check that we actually need to activate for the two 'wants' tokens
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = dai;
    tokens[1] = usdc;

    vm.expectRevert("mgvOffer/LogicMustApproveMangrove");
    strat.checkList(tokens);

    // and now activate them
    strat.activate(tokens);
  }

  function postAndFundOffers(uint makerGivesAmount, uint makerWantsAmountDAI, uint makerWantsAmountUSDC)
    public
    returns (uint offerId1, uint offerId2)
  {
    (offerId1, offerId2) = strat.newGhostOffers{value: 2 ether}({
      gives: makerGivesAmount, // WETH
      wants1: makerWantsAmountUSDC, // USDC
      wants2: makerWantsAmountDAI, // DAI
      pivot1: 0,
      pivot2: 0
    });
  }

  function takeOffer(uint makerGivesAmount, uint makerWantsAmount, IERC20 makerWantsToken, uint offerId)
    public
    returns (uint takerGot, uint takerGave, uint bounty)
  {
    // try to snipe one of the offers (using the separate taker account)
    vm.prank(taker);
    (, takerGot, takerGave, bounty,) = mgv.snipes({
      outbound_tkn: $(weth),
      inbound_tkn: $(makerWantsToken),
      targets: wrap_dynamic([offerId, makerGivesAmount, makerWantsAmount, type(uint).max]),
      fillWants: true
    });
  }

  function execTraderStratWithPartialFillSucces() public {
    uint makerGivesAmount = 0.15 ether;
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    deal($(weth), $(strat), cash(weth, 5));

    // post offers with Ghost liquidity
    (uint offerId1, uint offerId2) = postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);

    //only take half of the offer
    (uint takerGot, uint takerGave,) = takeOffer(makerGivesAmount / 2, makerWantsAmountDAI / 2, dai, offerId1);

    // assert that
    assertEq(takerGot, minusFee($(dai), $(weth), makerGivesAmount / 2), "taker got wrong amount");
    assertEq(takerGave, makerWantsAmountDAI / 2, "taker gave wrong amount");

    // assert that neither offer posted by Ghost are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_dai = mgv.offers($(weth), $(dai), offerId1);
    MgvStructs.OfferPacked offer_on_usdc = mgv.offers($(weth), $(usdc), offerId2);
    assertTrue(mgv.isLive(offer_on_dai), "weth->dai offer should not have been retracted");
    assertTrue(mgv.isLive(offer_on_usdc), "weth->usdc offer should not have been retracted");
  }

  function execTraderStratWithFillSucces() public {
    uint makerGivesAmount = 0.15 ether;
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    deal($(weth), $(strat), cash(weth, 10));

    (uint offerId1, uint offerId2) = postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);

    (uint takerGot, uint takerGave,) = takeOffer(makerGivesAmount, makerWantsAmountDAI, dai, offerId1);

    // assert that
    assertEq(takerGot, minusFee($(dai), $(weth), makerGivesAmount), "taker got wrong amount");
    assertEq(takerGave, makerWantsAmountDAI, "taker gave wrong amount");

    // assert that neither offer posted by Ghost are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_dai = mgv.offers($(weth), $(dai), offerId1);
    MgvStructs.OfferPacked offer_on_usdc = mgv.offers($(weth), $(usdc), offerId2);
    assertTrue(!mgv.isLive(offer_on_dai), "weth->dai offer should have been retracted");
    assertTrue(!mgv.isLive(offer_on_usdc), "weth->usdc offer should have been retracted");
  }

  function execTraderStratWithFallback() public {
    uint makerGivesAmount = 0.15 ether;
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    // not giving the start any WETH, the offer will therefor fail when taken
    (uint offerId1, uint offerId2) = postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);

    (uint takerGot, uint takerGave, uint bounty) = takeOffer(makerGivesAmount, makerWantsAmountUSDC, usdc, offerId2);

    // assert that
    assertEq(takerGot, 0, "taker got wrong amount");
    assertEq(takerGave, 0, "taker gave wrong amount");
    assertTrue(bounty > 0, "taker did not get any bounty");

    // assert that neither offer posted by Ghost are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_dai = mgv.offers($(weth), $(dai), offerId1);
    MgvStructs.OfferPacked offer_on_usdc = mgv.offers($(weth), $(usdc), offerId2);
    assertTrue(!mgv.isLive(offer_on_dai), "weth->dai offer should have been retracted");
    assertTrue(!mgv.isLive(offer_on_usdc), "weth->usdc offer should have been retracted");
  }
}
