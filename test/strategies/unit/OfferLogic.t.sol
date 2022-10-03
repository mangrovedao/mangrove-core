// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {GenericFork} from "mgv_test/lib/forks/Generic.sol";
import "mgv_src/strategies/offer_maker/OfferMaker.sol";

// unit tests for (single /\ multi) user strats (i.e unit tests that are non specific to either single or multi user feature)

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
    maker = freshAddress("maker");
    vm.deal(maker, 10 ether);
    // for Direct strats, maker is deployer
    deployer = deployer == address(0) ? maker : deployer;

    taker = freshAddress("taker");
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
    setupRouter();
    // dealing 1 eth and 2000$ to maker's reserve on contract
    vm.startPrank(maker);
    deal($(weth), makerContract.reserve(), 1 ether);
    deal($(usdc), makerContract.reserve(), cash(usdc, 2000));
    vm.stopPrank();
    vm.prank(deployer);
    makerContract.activate(dynamic([IERC20(weth), usdc]));
  }

  // override this to use Forwarder strats
  function setupMakerContract() internal virtual prank(deployer) {
    makerContract = new OfferMaker({
      mgv: IMangrove($(mgv)),
      router_: AbstractRouter(address(0)),
      deployer: deployer
    });
  }

  // override this function to use a specific router for the strat
  function setupRouter() internal virtual {}

  function test_checkList() public {
    vm.startPrank(maker);
    makerContract.checkList(dynamic([IERC20(weth), usdc]));
    vm.stopPrank();
  }

  function test_makerCanSetItsReserve() public {
    address new_reserve = freshAddress();
    vm.startPrank(maker);
    makerContract.setReserve(new_reserve);
    assertEq(makerContract.reserve(), new_reserve, "Incorrect reserve");
    vm.stopPrank();
  }

  function test_makerCanPostNewOffer() public {
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

  function test_getMissingProvisionIsEnoughToPostNewOffer() public {
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

  function test_getMissingProvisionIsMinimal() public {
    uint prov = makerContract.getMissingProvision(weth, usdc, type(uint).max, 0, 0);
    vm.startPrank(maker);
    vm.expectRevert("mgv/insufficientProvision");
    makerContract.newOffer{value: prov - 1}({
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

  function test_makerCanDeprovisionOffer() public {
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

  function test_makerCanUpdateOffer() public {
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

  function performTrade(bool success) internal returns (uint takergot, uint takergave, uint bounty, uint fee) {
    vm.prank(maker);
    // ask 2000 USDC for 1 weth
    makerContract.newOffer{value: 0.1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 * 10 ** 18,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0
    });

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

  function test_reserveUpdatedWhenTradeSucceeds() public {
    // for multi user contract `tokenBalance` returns the balance of msg.sender's reserve
    // so one needs to impersonate maker to obtain the correct balance
    vm.startPrank(maker);
    uint balOut = makerContract.tokenBalance(weth);
    uint balIn = makerContract.tokenBalance(usdc);
    vm.stopPrank();

    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade(true);
    assertTrue(bounty == 0 && takergot > 0, "trade failed");

    vm.startPrank(maker);
    assertEq(makerContract.tokenBalance(weth), balOut - (takergot + fee), "incorrect out balance");
    assertEq(makerContract.tokenBalance(usdc), balIn + takergave, "incorrect in balance");
    vm.stopPrank();
  }

  function test_makerCanWithdrawTokens() public {
    // note in order to be routing strategy agnostic one cannot easily mockup a trade
    // for aave routers reserve will hold overlying while for simple router reserve will hold the asset
    uint balusdc = usdc.balanceOf(maker);

    (, uint takergave,,) = performTrade(true);
    vm.prank(maker);
    // this will be a noop when maker == reserve
    makerContract.withdrawToken(usdc, maker, takergave);
    assertEq(usdc.balanceOf(maker), balusdc + takergave, "withdraw failed");
  }

  function test_failingOfferLogsIncident() public {
    // making offer fail for lack of approval
    (, MgvStructs.LocalPacked local) = mgv.config($(weth), $(usdc));
    uint next_id = local.last() + 1;
    vm.expectEmit(true, true, true, false, address(makerContract));
    emit LogIncident(IMangrove($(mgv)), weth, usdc, next_id, "mgvOffer/tradeSuccess", "mgv/makerTransferFail");
    vm.prank(deployer);
    makerContract.approve(weth, $(mgv), 0);
    performTrade({success: false});
  }

  function test_trade_succeeds_with_new_reserve() public {
    address new_reserve = freshAddress("new_reserve");

    vm.prank(maker);
    makerContract.setReserve(new_reserve);

    vm.startPrank(deployer);
    makerContract.setGasreq(makerContract.offerGasreq()+70_000);
    vm.stopPrank();

    deal($(weth), new_reserve, 0.5 ether);
    deal($(weth), address(makerContract), 0);
    deal($(usdc), address(makerContract), 0);
    
    address toApprove = address(makerContract.router());
    toApprove = toApprove == address(0) ? address(makerContract) : toApprove; 
    vm.startPrank(new_reserve);
    usdc.approve(toApprove, type(uint).max); // to push
    weth.approve(toApprove, type(uint).max); // to pull
    vm.stopPrank();
    (, uint takerGave,,) = performTrade(true);
    vm.startPrank(maker);
    assertEq(
      takerGave,
      makerContract.tokenBalance(usdc),
      "Incorrect reserve usdc balance"
    );
    assertEq(
      makerContract.tokenBalance(weth),
      0,
      "Incorrect reserve weth balance"
    );
    vm.stopPrank();
  }


}
