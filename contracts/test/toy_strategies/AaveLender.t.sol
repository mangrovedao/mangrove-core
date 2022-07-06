// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/Fork.sol";
import "mgv_src/toy_strategies/single_user/cash_management/AdvancedAaveRetail.sol";
import "mgv_test/toy_strategies/OfferProxy.t.sol";

// warning! currently only known to work on Polygon, block 26416000
// at a later point, Aave disables stable dai borrowing which those tests need
contract AaveLenderTest is AaveV3ModuleTest {
  IERC20 weth;
  IERC20 dai;
  // BufferedAaveRouter router;
  AdvancedAaveRetail strat;

  receive() external payable {}

  function setUp() public override {
    Fork.setUp();

    mgv = setupMangrove();
    mgv.setVault($(mgv));

    dai = IERC20(Fork.DAI);
    weth = IERC20(Fork.WETH);
    options.defaultFee = 30;
    setupMarket(dai, weth);

    weth.approve($(mgv), type(uint).max);
    dai.approve($(mgv), type(uint).max);

    deal($(weth), $(this), 10 ether);
    deal($(dai), $(this), 10_000 ether);
  }

  function test_run() public {
    deployStrat();

    execTraderStrat();
  }

  function deployStrat() public {
    strat = new AdvancedAaveRetail({
      addressesProvider: Fork.AAVE,
      _MGV: IMangrove($(mgv)),
      deployer: $(this)
    });
    // note for later: compound is
    //   simple/advanced compoudn= Contract.deploy(Fork.COMP,IMangrove($(mgv)),Fork.WETH,$(this));
    //   market = [Fork.CWETH,Fork.CDAI];

    // aave rejects market entering if underlying balance is 0 (will self enter at first deposit)
    // enterMarkets = false; // compound should have it set to true
    // provisioning Mangrove on behalf of MakerContract
    mgv.fund{value: 2 ether}($(strat));

    // testSigner approves Mangrove for WETH/DAI before trying to take offers
    weth.approve($(mgv), type(uint).max);
    dai.approve($(mgv), type(uint).max);

    // offer should get/put base/quote tokens on lender contract (OK since sender is MakerContract admin)
    // strat.enterMarkets(market); // not on aave

    strat.approveMangrove(dai, type(uint).max);
    strat.approveMangrove(weth, type(uint).max);

    // One sends 1000 DAI to MakerContract
    dai.transfer($(strat), 1000 ether);

    // testSigner asks makerContract to approve lender to be able to mint [c/a]Token
    strat.approveLender(weth, type(uint).max);
    // NB in the special case of cEth this is only necessary to repay debt
    strat.approveLender(dai, type(uint).max);

    // makerContract deposits some DAI on Lender (remains 100 DAIs on the contract)
    strat.mint(dai, 900 ether, $(strat));
  }

  function execTraderStrat() public {
    // TODO logLenderStatus
    uint offerId = strat.newOffer(
      IOfferLogic.MakerOrder({
        outbound_tkn: dai,
        inbound_tkn: weth,
        wants: 0.15 ether,
        gives: 300 ether,
        gasreq: strat.OFR_GASREQ(),
        gasprice: 0,
        pivotId: 0
      })
    );

    (, , uint gave, , ) = mgv.snipes({
      outbound_tkn: $(dai),
      inbound_tkn: $(weth),
      targets: wrap_dynamic([offerId, 300 ether, 0.15 ether, type(uint).max]),
      fillWants: true
    });

    // TODO logLenderStatus
    assertApproxBalanceAndBorrow(strat, dai, 700 ether, 0, $(strat));
    assertApproxBalanceAndBorrow(strat, weth, gave, 0, $(strat));

    strat.approveMangrove(weth, type(uint).max);

    offerId = strat.newOffer(
      IOfferLogic.MakerOrder({
        outbound_tkn: weth,
        inbound_tkn: dai,
        wants: 380 ether,
        gives: 0.2 ether,
        gasreq: strat.OFR_GASREQ(),
        gasprice: 0,
        pivotId: 0
      })
    );

    vm.warp(block.timestamp + 10);
    (uint successes, , , , ) = mgv.snipes({
      outbound_tkn: $(weth),
      inbound_tkn: $(dai),
      targets: wrap_dynamic([offerId, 0.2 ether, 380 ether, type(uint).max]),
      fillWants: true
    });
    assertEq(successes, 1, "snipes should succeed");

    // TODO logLenderStatus

    assertApproxBalanceAndBorrow(strat, weth, 0, 0.05 ether, $(strat));

    offerId = strat.newOffer(
      IOfferLogic.MakerOrder({
        outbound_tkn: dai,
        inbound_tkn: weth,
        wants: 0.63 ether,
        gives: 1500 ether,
        gasreq: strat.OFR_GASREQ(),
        gasprice: 0,
        pivotId: 0
      })
    );

    mgv.snipes({
      outbound_tkn: $(dai),
      inbound_tkn: $(weth),
      targets: wrap_dynamic([offerId, 1500 ether, 0.63 ether, type(uint).max]),
      fillWants: true
    });

    // TODO logLenderStatus

    // TODO check borrowing DAIs and not borrowing WETHs anymore
  }
}
