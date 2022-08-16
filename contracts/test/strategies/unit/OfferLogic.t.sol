// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/Fork.sol";

import "mgv_src/strategies/single_user/SimpleMaker.sol";

contract OfferLogicTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  address payable taker;
  address reserve;
  SimpleMaker makerContract;
  IOfferLogic.MakerOrder mko;
  bool forked;

  // tracking IOfferLogic logs
  event LogIncident(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 reason
  );

  function setUp() public virtual override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;

    if (forked) {
      Fork.setUp();
      mgv = setupMangrove();
      mgv.setVault($(mgv));
      weth = TestToken(Fork.WETH);
      usdc = TestToken(Fork.USDC);
      setupMarket(weth, usdc);
    } else {
      // deploying mangrove and opening WETH/USDC market.
      super.setUp();
      // rename for convenience
      weth = base;
      usdc = quote;
    }
    // ask 2000 USDC for 1 ETH
    mko = IOfferLogic.MakerOrder({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10**6,
      gives: 1 * 10**18,
      gasreq: type(uint).max,
      gasprice: 0,
      pivotId: 0,
      offerId: 0
    });
    maker = freshAddress("maker");
    vm.deal(maker, 10 ether);

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
    deal($(weth), makerContract.reserve(), 1 ether);
    deal($(usdc), makerContract.reserve(), cash(usdc, 2000));

    vm.prank(maker);
    makerContract.activate(tkn_pair(weth, usdc));
  }

  function setupMakerContract() internal virtual prank(maker) {
    makerContract = new SimpleMaker({
      _MGV: IMangrove($(mgv)), // TODO: remove IMangrove dependency?
      deployer: maker
    });
  }

  function setupRouter() internal virtual {}

  function test_checkList() public view {
    makerContract.checkList(tkn_pair(weth, usdc));
  }

  function test_AdminCanSetReserve() public {
    address new_reserve = freshAddress();
    vm.prank(maker);
    makerContract.set_reserve(new_reserve);
    assertEq(makerContract.reserve(), new_reserve, "Incorrect reserve");
  }

  function test_AdminCanPostNewOffer() public {
    vm.prank(maker);
    makerContract.newOffer{value: 0.1 ether}(mko);
  }

  function test_AdminCanRetractOffer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}(mko);
    uint makerBalWei = maker.balance;
    vm.prank(maker);
    uint deprovisioned = makerContract.retractOffer(
      mko.outbound_tkn,
      mko.inbound_tkn,
      offerId,
      true
    );
    assertEq(
      maker.balance,
      makerBalWei + deprovisioned,
      "Incorrect WEI balance"
    );
  }

  function test_AdminCanUpdateOffer() public {
    vm.prank(maker);
    uint offerId = makerContract.newOffer{value: 0.1 ether}(mko);
    mko.offerId = offerId;

    vm.prank(maker);
    makerContract.updateOffer(mko);
  }

  function performTrade()
    internal
    returns (
      uint takergot,
      uint takergave,
      uint bounty,
      uint fee
    )
  {
    vm.prank(maker);
    // ask 2000 USDC for 1 weth
    makerContract.newOffer{value: 0.1 ether}(mko);

    // taker has approved mangrove in the setUp
    vm.startPrank(taker);
    (takergot, takergave, bounty, fee) = mgv.marketOrder({
      outbound_tkn: $(mko.outbound_tkn),
      inbound_tkn: $(mko.inbound_tkn),
      takerWants: 0.5 ether,
      takerGives: cash(usdc, 1000),
      fillWants: true
    });
    vm.stopPrank();
    assertTrue(bounty == 0 && takergot > 0, "trade failed");
  }

  function test_ReserveUpdatedWhenTradeSucceeds() public {
    uint balOut = makerContract.tokenBalance(mko.outbound_tkn);
    uint balIn = makerContract.tokenBalance(mko.inbound_tkn);

    (uint takergot, uint takergave, uint bounty, uint fee) = performTrade();
    assertTrue(bounty == 0 && takergot > 0, "trade failed");
    assertEq(
      makerContract.tokenBalance(mko.outbound_tkn),
      balOut - (takergot + fee),
      "incorrect out balance"
    );
    assertEq(
      makerContract.tokenBalance(mko.inbound_tkn),
      balIn + takergave,
      "incorrect in balance"
    );
  }

  function test_AdminCanWithdrawTokens() public {
    // note in order to be routing strategy agnostic one cannot easily mockup a trade
    // for aave routers reserve will hold overlying while for simple router reserve will hold the asset
    uint balusdc = usdc.balanceOf(maker);

    (, uint takergave, , ) = performTrade();
    vm.prank(maker);
    // this will be a noop when maker == reserve
    makerContract.withdrawToken(usdc, maker, takergave);
    assertEq(usdc.balanceOf(maker), balusdc + takergave, "withdraw failed");
  }
}
