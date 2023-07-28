// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {GeometricKandelGasTest, PinnedPolygonFork, MgvReader, IMangrove} from "../abstract/GeometricKandel.gas.t.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {
  ShortKandel, GeometricKandel, IERC20
} from "mgv_src/strategies/offer_maker/market_making/kandel/ShortKandel.sol";
import {AavePrivateRouter} from "mgv_src/strategies/routers/integrations/AavePrivateRouter.sol";

contract ShortKandelGasTest is GeometricKandelGasTest {
  TestToken internal collateral;
  AavePrivateRouter internal router;
  uint internal interestRate = 2;
  uint internal constant INIT_COLLATERAL = 1_000_000 * 10 ** 18;

  function Short(GeometricKandel kdl) internal pure returns (ShortKandel) {
    return ShortKandel($(kdl));
  }

  function setUp() public override {
    super.setUp();
    completeFill_ = 0.1 ether;
    partialFill_ = 0.08 ether;

    collateral = TestToken(fork.get("DAI"));
    ShortKandel kdl_ = Short(kdl);

    deal($(collateral), maker, INIT_COLLATERAL);
    vm.startPrank(maker);
    {
      collateral.approve($(kdl), type(uint).max);
      // initialize does not activates collateral
      kdl_.activate(dynamic([IERC20(collateral)]));
      expectFrom($(kdl));
      emit Credit(collateral, INIT_COLLATERAL);
      kdl_.depositFunds(collateral, INIT_COLLATERAL);
    }
    vm.stopPrank();
  }

  function __setForkEnvironment__() internal override {
    fork = new PinnedPolygonFork();
    fork.setUp();
    options.gasprice = 140;
    options.gasbase = 120000;
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
    uint router_gasreq = 600 * 1000;
    uint kandel_gasreq = 160 * 1000;
    router =
      address(router) == address(0) ? new AavePrivateRouter(fork.get("Aave"), interestRate, router_gasreq, 0) : router;
    ShortKandel lkdl = new ShortKandel({
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
