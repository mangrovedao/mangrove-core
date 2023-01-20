// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {PolygonFork, PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {MetaPLUsDAOToken} from "mgv_src/usual/MetaPLUsDAOToken.sol";
import {UsualTokenInterface} from "mgv_src/usual/UsualTokenInterface.sol";
import {LockedWrapperToken} from "mgv_src/usual/test/LockedWrapperToken.sol";
import {PLUsMgvStrat, IMangrove} from "mgv_src/usual/PLUsMgvStrat.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {console} from "forge-std/console.sol";
import {PLUsTakerProxy} from "mgv_src/usual/PLUsTakerProxy.sol";
import {UsualDapp} from "mgv_src/usual/test/UsualDapp.sol";

contract PLUsMgvStratTest is MangroveTest {
  IERC20 usUSDToken;
  MetaPLUsDAOToken metaToken;
  LockedWrapperToken pLUsDAOToken;
  LockedWrapperToken lUsDAOToken;
  TestToken usDAOToken;
  PLUsTakerProxy pLUsTakerProxy;
  UsualDapp usualDapp;

  PolygonFork fork;

  address payable taker;
  address payable seller;
  PLUsMgvStrat strat;

  receive() external payable virtual {}

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork(); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();

    usUSDToken = new TestToken({ admin: address(this), name: "Usual USD stable coin", symbol: "UsUSD", _decimals: 18 });
    fork.set("UsUSD", address(usUSDToken));

    usDAOToken = new TestToken({ admin: address(this), name: "Usual governance token", symbol: "UsDAO", _decimals: 18 });
    fork.set("UsDAO", address(usDAOToken));

    lUsDAOToken =
    new LockedWrapperToken({ admin: address(this), name: "Locked Usual governance token", symbol: "LUsDAO", _underlying: usDAOToken });
    fork.set("LUsDAO", address(lUsDAOToken));

    pLUsDAOToken =
    new LockedWrapperToken({ admin: address(this), name: "Price-locked Usual governance token", symbol: "PLUsDAO", _underlying: lUsDAOToken });
    fork.set("PLUsDAO", address(pLUsDAOToken));

    mgv = setupMangrove();
    reader = new MgvReader($(mgv));

    metaToken =
    new MetaPLUsDAOToken({ admin: address(this), _name: "Meta Price-locked Usual governance token", _symbol: "Meta-PLUsDAO", pLUsDAOToken: pLUsDAOToken, mangrove: address(mgv) });
    fork.set("Meta-PLUsDAO", address(metaToken));

    pLUsTakerProxy = new PLUsTakerProxy( {mgv: IMangrove($(mgv)), metaPLUsDAOToken: metaToken, usUSD:usUSDToken });
    fork.set("PLUsTakerProxy", address(pLUsTakerProxy));

    usualDapp = new UsualDapp( address(this));
    fork.set("UsualDapp", address(usualDapp));

    mgv.activate(address(metaToken), address(usUSDToken), options.defaultFee, 10, 20_000); // only opne one side of the market

    taker = freshAddress("taker");
    deal(taker, 10_000_000);

    seller = freshAddress("seller");
    deal(seller, 10 ether);
  }

  function deployStrat() public {
    strat = new PLUsMgvStrat({
      admin: address(this),
      mgv: IMangrove($(mgv)),
      pLUsDAOToken: pLUsDAOToken,
      metaPLUsDAOToken: metaToken,
      usUSD: usUSDToken
      });
    fork.set("PLUsMgvStrat", address(strat));

    usualDapp.setPLUsMgvStrat(strat);
    strat.setUsualDapp(address(usualDapp));

    metaToken.setPLUsMgvStrat(address(strat)); // needed in order for metaToken to know the address of the strat
    metaToken.setPLUsTakerProxy(pLUsTakerProxy); // needed in order for metaToken to know the address of the taker proxy
    pLUsDAOToken.addToWhitelist(address(metaToken)); // need in order for metaToken to transfer PLUsDAO Token
    pLUsDAOToken.addToWhitelist(address(strat)); // need in order for the strat to transfer PLUsDAO Token

    deal($(usUSDToken), taker, cash(usUSDToken, 10_000)); // This is done by Usual, this is only done for testing
    usDAOToken.addAdmin(address(lUsDAOToken)); // This is done by Usual, this is only done for testing
    lUsDAOToken.addAdmin(address(pLUsDAOToken)); // This is done by Usual, this is only done for testing
    pLUsDAOToken.mint(seller, cash(pLUsDAOToken, 10)); // This is done by Usual, this is only done for testing

    vm.startPrank(taker);
    usUSDToken.approve(address(pLUsTakerProxy), type(uint).max); // the taker always has to approve mgv for the inbound token
    vm.stopPrank();

    vm.startPrank(seller);
    pLUsDAOToken.approve($(strat), type(uint).max); // When offer is taken, the strat need to be able to transfer PLUsDAO token from seller to strat
    vm.stopPrank();

    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = usUSDToken;
    tokens[1] = metaToken;

    vm.expectRevert("mgvOffer/LogicMustApproveMangrove");
    strat.checkList(tokens); // checks that the tokens are activated, they are not, and will revert
    strat.activate(tokens); // activates the tokens on the strat
  }

  function postAndFundOffer(uint wants, uint gives, address owner) public returns (uint offerId) {
    vm.startPrank(owner);
    offerId = usualDapp.newOffer{value: 2 ether}({wants: wants, gives: gives, pivotId: 0});
    vm.stopPrank();
  }

  function takeOfferDirectlyOnMgv(uint wants, uint gives) public returns (uint takerGot, uint takerGave, uint bounty) {
    (takerGot, takerGave, bounty,) = mgv.marketOrder({
      outbound_tkn: address(metaToken),
      inbound_tkn: address(usUSDToken),
      takerWants: wants,
      takerGives: gives,
      fillWants: true
    });
  }

  function takeOfferWithProxy(uint wants, uint gives) public returns (uint takerGot, uint takerGave, uint bounty) {
    (takerGot, takerGave, bounty,) = pLUsTakerProxy.marketOrder({takerWants: wants, takerGives: gives});
  }

  function test_postOfferAndTakeOfferWithProxy() public {
    deployStrat();
    uint takerWants = cash(usUSDToken, 4);
    uint takerGives = cash(metaToken, 2);
    postAndFundOffer(takerGives, takerWants, seller);

    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty) = takeOfferWithProxy(takerWants, takerGives);
    vm.stopPrank();

    assertEq(takerGot, takerWants, "taker got wrong amount");
    assertEq(takerGave, takerGives, "taker gave wrong amount");
    assertEq(bounty, 0, "bounty should be zero");
  }

  function test_postOfferAndTakeOfferDirectlyOnMgv() public {
    deployStrat();

    uint takerWants = cash(metaToken, 2); // same as the seller gives
    uint takerGives = cash(usUSDToken, 4); // same as the seller wants
    postAndFundOffer(takerGives, takerWants, seller);

    vm.startPrank(taker);
    usUSDToken.approve(address(mgv), type(uint).max); // the taker always has to approve mgv for the inbound token
    vm.expectRevert("mgv/MgvFailToPayTaker");
    (uint takerGot, uint takerGave, uint bounty) = takeOfferDirectlyOnMgv(takerWants, takerGives);
    vm.stopPrank();

    assertEq(takerGot, 0, "taker should not get anything");
    assertEq(takerGave, 0, "taker should not give anything");
    assertEq(bounty, 0, "bounty should be zero");
  }

  function test_post2OffersAndTakeOffersWithProxy() public {
    deployStrat();
    uint takerWants = cash(usUSDToken, 4);
    uint takerGives = cash(metaToken, 2);
    postAndFundOffer(takerGives, takerWants, seller);
    postAndFundOffer(takerGives, takerWants, seller);

    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty) = takeOfferWithProxy(takerWants * 2, takerGives * 2);
    vm.stopPrank();

    assertEq(takerGot, takerWants * 2, "taker got wrong amount");
    assertEq(takerGave, takerGives * 2, "taker gave wrong amount");
    assertEq(bounty, 0, "bounty should be zero");
  }

  function test_postOfferAndTakeOfferPartiallyWithProxy() public {
    deployStrat();
    uint takerWants = cash(usUSDToken, 4);
    uint takerGives = cash(metaToken, 2);
    uint offerId = postAndFundOffer(takerGives * 2, takerWants * 2, seller);

    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty) = takeOfferWithProxy(takerWants, takerGives);
    vm.stopPrank();

    assertEq(takerGot, takerWants, "taker got wrong amount");
    assertEq(takerGave, takerGives, "taker gave wrong amount");
    assertEq(bounty, 0, "bounty should be zero");

    MgvStructs.OfferPacked offer = mgv.offers(address(metaToken), address(usUSDToken), offerId);
    assertTrue(mgv.isLive(offer), "offer should still be live");
  }

  // test dust, provision, offerList closed
  function test_posthookBelowDensity() public {
    deployStrat();
    uint wants = cash(metaToken, 2);
    uint gives = cash(usUSDToken, 40, 1);
    uint offerId = postAndFundOffer(wants, gives, seller);
    mgv.setDensity($(metaToken), $(usUSDToken), cash(metaToken, 1, 1));

    uint takerWants = cash(usUSDToken, 39, 1);
    uint takerGives = cash(metaToken, 2);
    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty) = takeOfferWithProxy(takerWants, takerGives);
    vm.stopPrank();

    assertEq(takerGot, takerWants, "taker got wrong amount");
    assertEq(takerGave, cash(metaToken, 195, 2), "taker gave wrong amount");
    assertEq(bounty, 0, "bounty should be zero");

    MgvStructs.OfferPacked offer = mgv.offers(address(metaToken), address(usUSDToken), offerId);
    assertTrue(!mgv.isLive(offer), "offer should not be live");
  }

  function test_updateOfferThroughStrat() public {
    deployStrat();
    uint wants = cash(metaToken, 2);
    uint gives = cash(usUSDToken, 4);
    uint offerId = postAndFundOffer(wants, gives, seller);

    vm.startPrank(seller);
    vm.expectRevert("PLUsMgvStrat/onlyAdminOrMgvOrDapp");
    strat.updateOffer(wants + 1, gives + 1, offerId, offerId, seller);
    vm.stopPrank();
  }

  function test_retractOfferThroughStrat() public {
    deployStrat();
    uint wants = cash(metaToken, 2);
    uint gives = cash(usUSDToken, 4);
    uint offerId = postAndFundOffer(wants, gives, seller);

    vm.startPrank(seller);
    vm.expectRevert("AccessControlled/Invalid");
    strat.retractOffer({outbound_tkn: metaToken, inbound_tkn: usUSDToken, offerId: offerId, deprovision: false});
    vm.stopPrank();
  }

  function test_retractOfferThroughStrat_asDapp() public {
    deployStrat();
    uint wants = cash(metaToken, 2);
    uint gives = cash(usUSDToken, 4);
    uint offerId = postAndFundOffer(wants, gives, seller);

    vm.startPrank(address(usualDapp));
    strat.retractOffer({outbound_tkn: metaToken, inbound_tkn: usUSDToken, offerId: offerId, deprovision: false});
    vm.stopPrank();

    MgvStructs.OfferPacked offer = mgv.offers(address(metaToken), address(usUSDToken), offerId);
    assertTrue(!mgv.isLive(offer), "offer should not be live");
  }

  function test_postOfferAndSnipeOffer() public {
    deployStrat();

    uint takerWants = cash(metaToken, 2); // same as the seller gives
    uint takerGives = cash(usUSDToken, 4); // same as the seller wants
    uint offerId = postAndFundOffer(takerGives, takerWants, seller);

    vm.startPrank(taker);
    usUSDToken.approve(address(mgv), type(uint).max); // the taker always has to approve mgv for the inbound token
    vm.expectRevert("mgv/MgvFailToPayTaker");
    mgv.snipes({
      outbound_tkn: $(metaToken),
      inbound_tkn: $(usUSDToken),
      targets: wrap_dynamic([offerId, takerWants, takerGives, type(uint).max]),
      fillWants: true
    });
    vm.stopPrank();
  }

  function test_postBid() public {
    deployStrat();
    uint wants = cash(metaToken, 2);
    uint gives = cash(usUSDToken, 4);
    vm.startPrank(seller);
    vm.expectRevert("mgv/inactive");
    mgv.newOffer{value: 2 ether}({
      outbound_tkn: address(usUSDToken),
      inbound_tkn: address(metaToken),
      wants: wants,
      gives: gives,
      gasreq: 1_000_000,
      gasprice: 0,
      pivotId: 0
    });
    vm.stopPrank();
  }

  function test_postDirectlyOnMgvAndTakeOffer() public {
    deployStrat();
    uint wants = cash(metaToken, 2);
    uint gives = cash(usUSDToken, 4);
    vm.startPrank(seller);
    metaToken.approve(address(mgv), type(uint).max);
    mgv.newOffer{value: 2 ether}({
      outbound_tkn: address(metaToken),
      inbound_tkn: address(usUSDToken),
      wants: wants,
      gives: gives,
      gasreq: 1_000_000,
      gasprice: 0,
      pivotId: 0
    });
    vm.stopPrank();

    uint oldBalance = taker.balance;
    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty) = takeOfferWithProxy(gives, wants);
    vm.stopPrank();

    assertEq(takerGot, 0, "taker should not get anything");
    assertEq(takerGave, 0, "taker should not give anything");
    assertEq(bounty, 0.000832 ether, "bounty should be zero");
    assertEq(taker.balance, oldBalance + bounty, "takers balance should increase the same amount as bounty");
  }

  function test_postOfferRemoveTokensAndTakeOfferWithProxy() public {
    deployStrat();
    uint takerWants = cash(usUSDToken, 4);
    uint takerGives = cash(metaToken, 2);
    postAndFundOffer(takerGives, takerWants, seller);
    pLUsDAOToken.addToWhitelist(address(seller));
    vm.startPrank(seller);
    pLUsDAOToken.transfer(address(this), cash(pLUsDAOToken, 10));
    vm.stopPrank();
    uint oldBalance = taker.balance;
    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty) = takeOfferWithProxy(takerWants, takerGives);
    vm.stopPrank();

    assertEq(takerGot, 0, "taker got wrong amount");
    assertEq(takerGave, 0, "taker gave wrong amount");
    assertEq(bounty, 0.0024436 ether, "bounty should be zero");
    assertEq(taker.balance, oldBalance + bounty, "takers balance should increase the same amount as bounty");
  }

  function test_postOfferRemoveTokensPartiallyAndTakeOfferWithProxy() public {
    deployStrat();
    uint takerWants = cash(usUSDToken, 4);
    uint takerGives = cash(metaToken, 2);
    postAndFundOffer(takerGives, takerWants, seller);
    pLUsDAOToken.addToWhitelist(address(seller));
    vm.startPrank(seller);
    pLUsDAOToken.transfer(address(this), cash(pLUsDAOToken, 9));
    vm.stopPrank();
    uint oldBalance = taker.balance;
    vm.startPrank(taker);
    (uint takerGot, uint takerGave, uint bounty) = takeOfferWithProxy(takerWants, takerGives);
    vm.stopPrank();

    assertEq(takerGot, 0, "taker got wrong amount");
    assertEq(takerGave, 0, "taker gave wrong amount");
    assertEq(bounty, 0.0024436 ether, "bounty should be zero");
    assertEq(taker.balance, oldBalance + bounty, "takers balance should increase the same amount as bounty");
  }
}
