// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {
  LeveragedKandel,
  GeometricKandel,
  OfferType,
  IERC20
} from "mgv_src/strategies/offer_maker/market_making/kandel/LeveragedKandel.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {KandelLib} from "lib/kandel/KandelLib.sol";
import {CoreKandelTest} from "../abstract/CoreKandel.t.sol";
import {console2 as console} from "forge-std/Test.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {AavePrivateRouter} from "mgv_src/strategies/routers/integrations/AavePrivateRouter.sol";

contract LeveragedKandelTest is CoreKandelTest {
  TestToken collateral;
  PinnedPolygonFork fork;
  AavePrivateRouter router;
  uint interestRate = 2;

  function setUp() public override {
    super.setUp();
    collateral = TestToken(fork.get("DAI"));
    LeveragedKandel kdl_ = LeveragedKandel($(kdl));

    uint collateralAmount = 1_000_000 * 10 ** 18;
    deal($(collateral), maker, collateralAmount);
    vm.startPrank(maker);
    {
      collateral.approve($(kdl), type(uint).max);
      // initialize does not activates collateral
      kdl_.activate(dynamic([IERC20(collateral)]));
      expectFrom($(kdl));
      emit Credit(collateral, collateralAmount);
      kdl_.depositFunds(collateral, collateralAmount);
    }
    vm.stopPrank();

    console.log(
      "base: %s, quote: %s, collateral: %s",
      toFixed(router.balanceOfReserve(base, address(0)), base.decimals()),
      toFixed(router.balanceOfReserve(quote, address(0)), quote.decimals()),
      toFixed(router.balanceOfReserve(collateral, address(0)), collateral.decimals())
    );
  }

  function __setForkEnvironment__() internal override {
    fork = new PinnedPolygonFork();
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH"));
    quote = TestToken(fork.get("USDC"));
    setupMarket(base, quote);
  }

  function __deployKandel__(address deployer, address reserveId)
    internal
    virtual
    override
    returns (GeometricKandel kdl_)
  {
    uint router_gasreq = 500 * 1000;
    uint kandel_gasreq = 160 * 1000;
    router =
      address(router) == address(0) ? new AavePrivateRouter(fork.get("Aave"), interestRate, router_gasreq) : router;
    LeveragedKandel lkdl = new LeveragedKandel({
      mgv: IMangrove($(mgv)),
      base: base,
      quote: quote,
      gasreq: kandel_gasreq,
      gasprice: 0,
      reserveId: reserveId
    });
    router.bind($(lkdl));

    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20

    lkdl.initialize(router);
    lkdl.setAdmin(deployer);
    assertEq(lkdl.offerGasreq(), kandel_gasreq + router_gasreq, "Incorrect gasreq");

    return lkdl;
  }
}
