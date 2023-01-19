// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {PolygonFork, PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {MetaPLUsDAOToken, IERC20, LockedWrapperToken} from "mgv_src/usual/MetaPLUsDAOToken.sol";
import {PLUsMgvStrat, IMangrove} from "mgv_src/usual/PLUsMgvStrat.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {console} from "forge-std/console.sol";

contract PLUsMgvStratTest is MangroveTest {
  IERC20 usUSDToken;
  MetaPLUsDAOToken metaToken;
  LockedWrapperToken pLUsDAOToken;
  LockedWrapperToken lUsDAOToken;
  TestToken usDAOToken;

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
    new MetaPLUsDAOToken({ admin: address(this), _name: "Meta Price-locked Usual governance token", _symbol: "Meta-PLUsDAO", lUsDAOToken: lUsDAOToken, pLUsDAOToken: pLUsDAOToken, mangrove: address(mgv) });
    fork.set("Meta-PLUsDAO", address(metaToken));

    setupMarket(usUSDToken, metaToken);

    taker = freshAddress("taker");
    deal(taker, 10_000_000);

    seller = freshAddress("seller");
    deal(seller, 10 ether);
  }

  function deployStrat() public {
    vm.startPrank(seller);
    strat = new PLUsMgvStrat({
      mgv: IMangrove($(mgv)),
      pLUsDAOToken: pLUsDAOToken,
      metaPLUsDAOToken: metaToken
      });
    vm.stopPrank();
    fork.set("PLUsMgvStrat", address(strat));

    metaToken.setPLUsMgvStrat(address(strat));
    usDAOToken.addAdmin(address(lUsDAOToken));
    lUsDAOToken.addToWhitelist(address(pLUsDAOToken));
    pLUsDAOToken.addToWhitelist(address(metaToken));
    pLUsDAOToken.addToWhitelist(address(strat));
    metaToken.addToWhitelist(address(strat));
    metaToken.addToWhitelist(address(mgv));

    deal($(usUSDToken), taker, cash(usUSDToken, 10_000));
    deal($(lUsDAOToken), seller, cash(lUsDAOToken, 10));

    // approve usUSD on Mangrove for taker
    vm.startPrank(taker);
    usUSDToken.approve($(mgv), type(uint).max);
    vm.stopPrank();

    vm.startPrank(seller);
    lUsDAOToken.approve($(pLUsDAOToken), type(uint).max); // Posting a new offer requires that PLUsDAO contract can transfer LUsDAO token on behalf of the seller
    pLUsDAOToken.approve($(strat), type(uint).max); // When offer is taken, the strat need to be able to transfer PLUsDAO token from seller to strat
    metaToken.approve($(strat), type(uint).max); // Strat needs to be able to handle outbound and inbound for reserve
    usUSDToken.approve($(strat), type(uint).max); // Strat needs to be able to handle outbound and inbound for reserve
    vm.stopPrank();

    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = usUSDToken;
    tokens[1] = metaToken;

    vm.startPrank(seller);
    vm.expectRevert("mgvOffer/LogicMustApproveMangrove");
    strat.checkList(tokens);

    // and now activate them
    strat.activate(tokens);
    vm.stopPrank();
  }

  function postAndFundOffer(uint wants, uint gives) public returns (uint offerId) {
    offerId = strat.newOffer{value: 2 ether}({
      outbound_tkn: metaToken,
      inbound_tkn: usUSDToken,
      wants: wants,
      gives: gives,
      pivotId: 0
    });
  }

  function test_postOfferAndTakeOffer() public {
    deployStrat();

    vm.startPrank(seller);
    postAndFundOffer(cash(usUSDToken, 4), cash(metaToken, 2));
    vm.stopPrank();

    vm.startPrank(taker);
    takeOffer(cash(metaToken, 2), cash(usUSDToken, 4));
    vm.stopPrank();
  }

  function takeOffer(uint wants, uint gives) public returns (uint takerGot, uint takerGave, uint bounty) {
    // try to snipe one of the offers (using the separate taker account)
    (takerGot, takerGave, bounty,) = mgv.marketOrder({
      outbound_tkn: address(metaToken),
      inbound_tkn: address(usUSDToken),
      takerWants: wants,
      takerGives: gives,
      fillWants: true
    });
  }
}
