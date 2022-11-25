// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";
import "mgv_src/toy_strategies/offer_forwarder/AmplifierForwarder.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";

//import {console} from "forge-std/console.sol";

contract AmplifierForwarderTest is MangroveTest {
  IERC20 weth;
  IERC20 dai;
  IERC20 usdc;

  PolygonFork fork;

  address payable taker;
  address payable maker;
  AmplifierForwarder strat;

  receive() external payable virtual {}

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork(); // use polygon fork, to use dai, usdc, weth addresses
    fork.setUp();

    // use convenience helpers to setup Mangrove
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));

    // setup tokens, markets and approve them
    dai = IERC20(fork.get("DAI"));
    weth = IERC20(fork.get("WETH"));
    usdc = IERC20(fork.get("USDC"));

    setupMarket(dai, weth);
    setupMarket(usdc, weth);

    // setup separate taker/maker and give some native token (for gas)
    taker = freshAddress("taker");
    maker = freshAddress("maker");
    deal(taker, 1 ether);
    deal(maker, 1 ether);

    // mint usdc and dai to taker
    deal($(usdc), taker, cash(usdc, 10_000));
    deal($(dai), taker, cash(dai, 10_000));

    // approve DAI and USDC on Mangrove for taker
    vm.startPrank(taker);
    dai.approve($(mgv), type(uint).max);
    vm.stopPrank();
  }

  function deployStrat() public {
    strat = new AmplifierForwarder({
      mgv: IMangrove($(mgv)),
      base: weth,
      stable1: usdc, 
      stable2: dai,
      deployer: $(this),
      gasreq: 250000
      });

    // allow (the router to) pull of WETH from Amplifier (i.e., strat) to Mangrove
    strat.approve(weth, $(mgv), type(uint).max);

    // The test address need to approve the router to use the base token
    weth.approve($(strat.router()), type(uint).max);

    // NOTE:
    // For this test, we're locking base, ie WETH, in the vault of the contract
    // - so Amplifier is not really used for amplified liquidity, in this example.
    // However, to employ actual amplified liquidity it is simply a matter of
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
    //Find missing provision for both markets
    uint prov1 = strat.getMissingProvision(weth, usdc, type(uint).max, 0, 0);
    uint prov2 = strat.getMissingProvision(weth, dai, type(uint).max, 0, 0);

    (offerId1, offerId2) = strat.newAmplifiedOffers{value: prov1 + prov2}({
      gives: makerGivesAmount, // WETH
      wants1: makerWantsAmountUSDC, // USDC
      wants2: makerWantsAmountDAI, // DAI
      pivot1: 0,
      pivot2: 0,
      fund1: prov1,
      fund2: prov2
    });
  }

  function takeOffer(uint makerGivesAmount, uint makerWantsAmount, IERC20 makerWantsToken, uint offerId)
    public
    returns (uint takerGot, uint takerGave, uint bounty)
  {
    // try to snipe one of the offers (using the separate taker account)
    vm.startPrank(taker);
    (, takerGot, takerGave, bounty,) = mgv.snipes({
      outbound_tkn: $(weth),
      inbound_tkn: $(makerWantsToken),
      targets: wrap_dynamic([offerId, makerGivesAmount, makerWantsAmount, type(uint).max]),
      fillWants: true
    });
    vm.stopPrank();
  }

  struct offerPair {
    uint daiOffer;
    uint usdcOffer;
  }

  struct gotGaveBounty {
    uint got;
    uint gave;
    uint bounty;
  }

  function execTraderStratWithPartialFillSuccess() public {
    uint makerGivesAmount = cash(weth, 15, 2); //WETH has same decimal as native token
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    deal($(weth), $(this), cash(weth, 5));
    deal($(weth), maker, cash(weth, 5));

    // post offers with Amplifier liquidity with test account
    offerPair memory testOffer;
    (testOffer.daiOffer, testOffer.usdcOffer) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);

    vm.startPrank(maker);
    weth.approve($(strat.router()), type(uint).max);
    offerPair memory makerOffer;
    (makerOffer.daiOffer, makerOffer.usdcOffer) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);
    vm.stopPrank();

    //only take half of the tester offer
    gotGaveBounty memory takerFromTester;
    (takerFromTester.got, takerFromTester.gave,) =
      takeOffer(makerGivesAmount / 2, makerWantsAmountDAI / 2, dai, testOffer.daiOffer);

    // take the full offer from maker
    gotGaveBounty memory takerFromMaker;
    (takerFromMaker.got, takerFromMaker.gave,) =
      takeOffer(makerGivesAmount, makerWantsAmountDAI, dai, makerOffer.daiOffer);

    // assert that
    assertEq(
      takerFromTester.got,
      reader.minusFee($(dai), $(weth), makerGivesAmount / 2),
      "taker got wrong amount: testOffer.daiOffer"
    );
    assertEq(takerFromTester.gave, makerWantsAmountDAI / 2, "taker gave wrong amount: testOffer.daiOffer");

    // assert that
    assertEq(
      takerFromMaker.got,
      reader.minusFee($(dai), $(weth), makerGivesAmount),
      "taker got wrong amount: makerOffer.daiOffer"
    );
    assertEq(takerFromMaker.gave, makerWantsAmountDAI, "taker gave wrong amount: makerOffer.daiOffer");

    // assert that neither offer posted by Amplifier are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_dai1 = mgv.offers($(weth), $(dai), testOffer.daiOffer);
    MgvStructs.OfferPacked offer_on_usdc1 = mgv.offers($(weth), $(usdc), testOffer.usdcOffer);
    MgvStructs.OfferPacked offer_on_dai2 = mgv.offers($(weth), $(dai), makerOffer.daiOffer);
    MgvStructs.OfferPacked offer_on_usdc2 = mgv.offers($(weth), $(usdc), makerOffer.usdcOffer);
    assertTrue(mgv.isLive(offer_on_dai1), "weth->dai offer should not have been retracted: testOffer.daiOffer");
    assertTrue(mgv.isLive(offer_on_usdc1), "weth->usdc offer should not have been retracted: testOffer.usdcOffer");
    assertTrue(!mgv.isLive(offer_on_dai2), "weth->dai offer should have been retracted: makerOffer.daiOffer");
    assertTrue(!mgv.isLive(offer_on_usdc2), "weth->usdc offer should have been retracted: makerOffer.usdcOffer");
  }

  function execTraderStratWithSuccess() public {
    uint makerGivesAmount = cash(weth, 15, 2); //WETH has same decimal as native token
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    deal($(weth), $(this), cash(weth, 5));
    deal($(weth), maker, cash(weth, 5));

    // post offers with Amplifier liquidity with test account
    offerPair memory testOffer;
    (testOffer.daiOffer, testOffer.usdcOffer) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);

    // post offers with Amplifier liquidity with test account
    vm.startPrank(maker);
    weth.approve($(strat.router()), type(uint).max);
    offerPair memory makerOffer;
    (makerOffer.daiOffer, makerOffer.usdcOffer) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);
    vm.stopPrank();

    //only take half of the tester offer
    gotGaveBounty memory takerFromTester;
    (takerFromTester.got, takerFromTester.gave,) =
      takeOffer(makerGivesAmount, makerWantsAmountDAI, dai, testOffer.daiOffer);

    // take the full offer from maker
    gotGaveBounty memory takerFromMaker;
    (takerFromMaker.got, takerFromMaker.gave,) =
      takeOffer(makerGivesAmount, makerWantsAmountDAI, dai, makerOffer.daiOffer);

    // assert that
    assertEq(
      takerFromTester.got,
      reader.minusFee($(dai), $(weth), makerGivesAmount),
      "taker got wrong amount: testOffer.daiOffer"
    );
    assertEq(takerFromTester.gave, makerWantsAmountDAI, "taker gave wrong amount: testOffer.daiOffer");

    // assert that
    assertEq(
      takerFromMaker.got,
      reader.minusFee($(dai), $(weth), makerGivesAmount),
      "taker got wrong amount: makerOffer.daiOffer"
    );
    assertEq(takerFromMaker.gave, makerWantsAmountDAI, "taker gave wrong amount: makerOffer.daiOffer");

    // assert that neither offer posted by Amplifier are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_dai1 = mgv.offers($(weth), $(dai), testOffer.daiOffer);
    MgvStructs.OfferPacked offer_on_usdc1 = mgv.offers($(weth), $(usdc), testOffer.usdcOffer);
    MgvStructs.OfferPacked offer_on_dai2 = mgv.offers($(weth), $(dai), makerOffer.daiOffer);
    MgvStructs.OfferPacked offer_on_usdc2 = mgv.offers($(weth), $(usdc), makerOffer.usdcOffer);
    assertTrue(!mgv.isLive(offer_on_dai1), "weth->dai offer should have been retracted: testOffer.daiOffer");
    assertTrue(!mgv.isLive(offer_on_usdc1), "weth->usdc offer should have been retracted: testOffer.usdcOffer");
    assertTrue(!mgv.isLive(offer_on_dai2), "weth->dai offer should have been retracted: makerOffer.daiOffer");
    assertTrue(!mgv.isLive(offer_on_usdc2), "weth->usdc offer should have been retracted: makerOffer.usdcOffer");
  }

  function execTraderStratWithFallback() public {
    uint makerGivesAmount = cash(weth, 15, 2); //WETH has same decimal as native token
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    // post offers with Amplifier liquidity with test account
    offerPair memory testOffer;
    (testOffer.daiOffer, testOffer.usdcOffer) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);

    vm.startPrank(maker);
    offerPair memory makerOffer;
    (makerOffer.daiOffer, makerOffer.usdcOffer) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);
    vm.stopPrank();

    //only take half of the tester offer
    gotGaveBounty memory takerFromTester;
    (takerFromTester.got, takerFromTester.gave, takerFromTester.bounty) =
      takeOffer(makerGivesAmount, makerWantsAmountDAI, dai, testOffer.daiOffer);

    // take the full offer from maker
    gotGaveBounty memory takerFromMaker;
    (takerFromMaker.got, takerFromMaker.gave, takerFromMaker.bounty) =
      takeOffer(makerGivesAmount, makerWantsAmountDAI, dai, makerOffer.daiOffer);

    // assert that
    assertEq(takerFromTester.got, 0, "taker got wrong amount: testOffer.daiOffer");
    assertEq(takerFromTester.gave, 0, "taker gave wrong amount: testOffer.daiOffer");
    assertTrue(takerFromTester.bounty > 0, "taker should get bounty for failing offer: testerOffer.daiOffer");

    // assert that
    assertEq(takerFromMaker.got, 0, "taker got wrong amount: makerOffer.daiOffer");
    assertEq(takerFromMaker.gave, 0, "taker gave wrong amount: makerOffer.daiOffer");
    assertTrue(takerFromMaker.bounty > 0, "taker should get bounty for failing offer: makerOffer.daiOffer");

    // assert that neither offer posted by Amplifier are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_dai1 = mgv.offers($(weth), $(dai), testOffer.daiOffer);
    MgvStructs.OfferPacked offer_on_usdc1 = mgv.offers($(weth), $(usdc), testOffer.usdcOffer);
    MgvStructs.OfferPacked offer_on_dai2 = mgv.offers($(weth), $(dai), makerOffer.daiOffer);
    MgvStructs.OfferPacked offer_on_usdc2 = mgv.offers($(weth), $(usdc), makerOffer.usdcOffer);
    assertTrue(!mgv.isLive(offer_on_dai1), "weth->dai offer should have been retracted: testOffer.daiOffer");
    assertTrue(!mgv.isLive(offer_on_usdc1), "weth->usdc offer should have been retracted: testOffer.usdcOffer");
    assertTrue(!mgv.isLive(offer_on_dai2), "weth->dai offer should have been retracted: makerOffer.daiOffer");
    assertTrue(!mgv.isLive(offer_on_usdc2), "weth->usdc offer should have been retracted: makerOffer.usdcOffer");
  }

  function execTraderStratOfferAlreadyActive() public {
    uint makerGivesAmount = cash(weth, 15, 2); //WETH has same decimal as native token
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    deal($(weth), $(this), cash(weth, 5));
    deal($(weth), maker, cash(weth, 5));

    // post offers with Amplifier liquidity with test account
    offerPair memory testOffer;
    (testOffer.daiOffer, testOffer.usdcOffer) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);
    //Find missing provision for both markets
    uint prov1Tester = strat.getMissingProvision(weth, usdc, type(uint).max, 0, 0);
    uint prov2Tester = strat.getMissingProvision(weth, dai, type(uint).max, 0, 0);

    vm.expectRevert("AmplifierForwarder/offer1AlreadyActive");

    strat.newAmplifiedOffers{value: prov1Tester + prov2Tester}({
      gives: makerGivesAmount, // WETH
      wants1: makerWantsAmountUSDC, // USDC
      wants2: makerWantsAmountDAI, // DAI
      pivot1: 0,
      pivot2: 0,
      fund1: prov1Tester,
      fund2: prov2Tester
    });

    // post offers with Amplifier liquidity with test account
    vm.startPrank(maker);
    weth.approve($(strat.router()), type(uint).max);
    offerPair memory makerOffer;
    (makerOffer.daiOffer, makerOffer.usdcOffer) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);

    strat.retractOffer(weth, usdc, makerOffer.usdcOffer, false);

    uint prov1Maker = strat.getMissingProvision(weth, usdc, type(uint).max, 0, 0);
    uint prov2Maker = strat.getMissingProvision(weth, dai, type(uint).max, 0, 0);

    vm.expectRevert("AmplifierForwarder/offer2AlreadyActive");

    strat.newAmplifiedOffers{value: prov1Maker + prov2Maker}({
      gives: makerGivesAmount, // WETH
      wants1: makerWantsAmountUSDC, // USDC
      wants2: makerWantsAmountDAI, // DAI
      pivot1: 0,
      pivot2: 0,
      fund1: prov1Maker,
      fund2: prov2Maker
    });
    vm.stopPrank();

    // assert that neither offer posted by Amplifier are live (= have been retracted)
    MgvStructs.OfferPacked offer_on_dai1 = mgv.offers($(weth), $(dai), testOffer.daiOffer);
    MgvStructs.OfferPacked offer_on_usdc1 = mgv.offers($(weth), $(usdc), testOffer.usdcOffer);
    MgvStructs.OfferPacked offer_on_dai2 = mgv.offers($(weth), $(dai), makerOffer.daiOffer);
    MgvStructs.OfferPacked offer_on_usdc2 = mgv.offers($(weth), $(usdc), makerOffer.usdcOffer);
    assertTrue(mgv.isLive(offer_on_dai1), "weth->dai offer should not have been retracted: testOffer.daiOffer");
    assertTrue(mgv.isLive(offer_on_usdc1), "weth->usdc offer should not have been retracted: testOffer.usdcOffer");
    assertTrue(mgv.isLive(offer_on_dai2), "weth->dai offer should not have been retracted: makerOffer.daiOffer");
    assertTrue(!mgv.isLive(offer_on_usdc2), "weth->usdc offer should have been retracted: makerOffer.usdcOffer");
  }

  function execTraderStratDeprovisionDeadOffers() public {
    uint makerGivesAmount = cash(weth, 15, 2); //WETH has same decimal as native token
    uint makerWantsAmountDAI = cash(dai, 300);
    uint makerWantsAmountUSDC = cash(usdc, 300);

    deal($(weth), $(this), cash(weth, 5));
    deal($(weth), maker, cash(weth, 5));

    // post offers with Amplifier liquidity with test account
    offerPair memory testOffer;
    (testOffer.daiOffer, testOffer.usdcOffer) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);

    // post offers with Amplifier liquidity with test account
    vm.startPrank(maker);
    weth.approve($(strat.router()), type(uint).max);
    offerPair memory makerOffer;
    (makerOffer.daiOffer, makerOffer.usdcOffer) =
      postAndFundOffers(makerGivesAmount, makerWantsAmountDAI, makerWantsAmountUSDC);
    vm.stopPrank();

    //only take half of the tester offer
    gotGaveBounty memory takerFromTester;
    (takerFromTester.got, takerFromTester.gave,) =
      takeOffer(makerGivesAmount, makerWantsAmountDAI, dai, testOffer.daiOffer);

    // take the full offer from maker
    gotGaveBounty memory takerFromMaker;
    (takerFromMaker.got, takerFromMaker.gave,) =
      takeOffer(makerGivesAmount, makerWantsAmountDAI, dai, makerOffer.daiOffer);

    // check native balance before retracting offers
    uint nativeBalanceBeforeRetract1 = $(this).balance;
    uint nativeBalanceBeforeRetract2 = maker.balance;

    vm.prank(maker);
    strat.retractOffers(true);

    strat.retractOffers(true);

    assertTrue(nativeBalanceBeforeRetract1 < $(this).balance, "provison for this was not returned");
    assertTrue(nativeBalanceBeforeRetract2 < maker.balance, "provison for maker was not returned");
  }

  function test_success_partialFill() public {
    deployStrat();

    execTraderStratWithPartialFillSuccess();
  }

  function test_success() public {
    deployStrat();

    execTraderStratWithSuccess();
  }

  function test_fallback() public {
    deployStrat();

    execTraderStratWithFallback();
  }

  function test_offerAlreadyActive() public {
    deployStrat();

    execTraderStratOfferAlreadyActive();
  }

  function test_deprovisionDeadOffers() public {
    deployStrat();

    execTraderStratDeprovisionDeadOffers();
  }
}
