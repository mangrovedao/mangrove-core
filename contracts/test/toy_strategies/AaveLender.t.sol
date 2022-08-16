// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/Fork.sol";
import "mgv_src/toy_strategies/single_user/cash_management/AdvancedAaveRetail.sol";

abstract contract AaveV3ModuleTest is MangroveTest {
  /* aave expectations */
  function assertApproxBalanceAndBorrow(
    AaveV3Module op,
    IERC20 underlying,
    uint expected_balance,
    uint expected_borrow,
    address account
  ) public {
    uint balance = op.overlying(underlying).balanceOf(account);
    uint borrow = op.borrowed($(underlying), account);
    console2.log("borrow is", borrow);
    assertApproxEqAbs(
      balance,
      expected_balance,
      (10**14) / 2,
      "wrong balance on lender"
    );
    assertApproxEqAbs(
      borrow,
      expected_borrow,
      (10**14) / 2,
      "wrong borrow on lender"
    );
  }
}

// warning! currently only known to work on Polygon, block 26416000
// at a later point, Aave disables stable dai borrowing which those tests need
contract AaveLenderForkedTest is AaveV3ModuleTest {
  IERC20 weth;
  IERC20 dai;
  AaveDeepRouter router;
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

    deal($(weth), $(this), cash(weth, 10));
    deal($(dai), $(this), cash(dai, 10_000));
  }

  function test_run() public {
    deployStrat();

    execTraderStrat();
  }

  function deployStrat() public {
    strat = new AdvancedAaveRetail({
      _mgv: IMangrove($(mgv)),
      _addressesProvider: Fork.AAVE,
      deployer: $(this)
    });

    router = AaveDeepRouter($(strat.router()));
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
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = dai;
    tokens[1] = weth;
    strat.activate(tokens);

    // One sends 1000 DAI to MakerContract
    dai.transfer($(strat), 1000 ether);

    // testSigner asks makerContract to approve lender to be able to mint [c/a]Token
    router.approveLender(weth);
    // NB in the special case of cEth this is only necessary to repay debt
    router.approveLender(dai);

    // makerContract deposits some DAI on Lender (remains 100 DAIs on the contract)
    router.supply(
      dai,
      strat.reserve(),
      900 ether,
      $(strat) /* from */
    );
  }

  function execTraderStrat() public {
    // TODO logLenderStatus
    uint offerId = strat.newOffer(
      IOfferLogic.MakerOrder({
        outbound_tkn: dai,
        inbound_tkn: weth,
        wants: 0.15 ether,
        gives: 300 ether,
        gasreq: strat.ofr_gasreq(),
        gasprice: 0,
        pivotId: 0,
        offerId: 0
      })
    );

    (, uint got, uint gave, , ) = mgv.snipes({
      outbound_tkn: $(dai),
      inbound_tkn: $(weth),
      targets: wrap_dynamic([offerId, 300 ether, 0.15 ether, type(uint).max]),
      fillWants: true
    });
    assertEq(got, minusFee($(dai), $(weth), 300 ether), "wrong got amount");

    // TODO logLenderStatus
    assertApproxBalanceAndBorrow(router, dai, 700 ether, 0, $(router));
    assertApproxBalanceAndBorrow(router, weth, gave, 0, $(router));

    offerId = strat.newOffer(
      IOfferLogic.MakerOrder({
        outbound_tkn: weth,
        inbound_tkn: dai,
        wants: 380 ether,
        gives: 0.2 ether,
        gasreq: strat.ofr_gasreq(),
        gasprice: 0,
        pivotId: 0,
        offerId: 0
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

    assertApproxBalanceAndBorrow(router, weth, 0, 0.05 ether, $(router));

    offerId = strat.newOffer(
      IOfferLogic.MakerOrder({
        outbound_tkn: dai,
        inbound_tkn: weth,
        wants: 0.63 ether,
        gives: 1500 ether,
        gasreq: strat.ofr_gasreq(),
        gasprice: 0,
        pivotId: 0,
        offerId: 0
      })
    );

    // cannot borrowrepay in same block
    vm.warp(block.timestamp + 1);

    (, got, , , ) = mgv.snipes({
      outbound_tkn: $(dai),
      inbound_tkn: $(weth),
      targets: wrap_dynamic([offerId, 1500 ether, 0.63 ether, type(uint).max]),
      fillWants: true
    });
    assertEq(
      got,
      minusFee($(dai), $(weth), 1500 ether),
      "wrong received amount"
    );

    // TODO logLenderStatus
    assertApproxBalanceAndBorrow(router, weth, 0.58 ether, 0, $(router));
    // TODO check borrowing DAIs and not borrowing WETHs anymore
  }
}
