// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {
  KandelSeeder,
  IMangrove,
  GeometricKandel
} from "mgv_src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {
  AaveKandelSeeder, AavePooledRouter
} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandelSeeder.sol";
import {AbstractKandelSeeder} from
  "mgv_src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandelSeeder.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";

contract KandelSeederTest is MangroveTest {
  PinnedPolygonFork internal fork;
  AbstractKandelSeeder internal seeder;
  AbstractKandelSeeder internal aaveSeeder;
  AavePooledRouter internal aaveRouter;

  event NewAaveKandel(
    address indexed owner, IERC20 indexed base, IERC20 indexed quote, address aaveKandel, address reserveId
  );
  event NewKandel(address indexed owner, IERC20 indexed base, IERC20 indexed quote, address kandel);

  function sow(bool sharing) internal returns (GeometricKandel) {
    return
      seeder.sow(AbstractKandelSeeder.KandelSeed({base: base, quote: quote, gasprice: 0, liquiditySharing: sharing}));
  }

  function sowAave(bool sharing) internal returns (GeometricKandel) {
    return aaveSeeder.sow(
      AbstractKandelSeeder.KandelSeed({base: base, quote: quote, gasprice: 0, liquiditySharing: sharing})
    );
  }

  function setEnvironment() internal {
    fork = new PinnedPolygonFork(39880000);
    fork.setUp();
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH"));
    quote = TestToken(fork.get("USDC"));
    setupMarket(base, quote);
  }

  function setUp() public virtual override {
    /// sets base, quote, opens a market (base,quote) on Mangrove
    setEnvironment();
    seeder = new KandelSeeder({
      mgv:IMangrove($(mgv)), 
      kandelGasreq: 128_000
    });

    AaveKandelSeeder aaveKandelSeeder = new AaveKandelSeeder({
      mgv:IMangrove($(mgv)), 
      addressesProvider: fork.get("AaveAddressProvider"), 
      routerGasreq: 500_000, 
      aaveKandelGasreq: 128_001
    });
    aaveSeeder = aaveKandelSeeder;
    aaveRouter = aaveKandelSeeder.AAVE_ROUTER();
  }

  function test_sow_fails_if_market_not_fully_active() public {
    mgv.deactivate($(base), $(quote));
    vm.expectRevert("KandelSeeder/inactiveMarket");
    sow(false);
    mgv.activate($(base), $(quote), 0, 10, 50_000);
    mgv.deactivate($(quote), $(base));
    vm.expectRevert("KandelSeeder/inactiveMarket");
    sow(false);
  }

  function test_aave_manager_is_attributed() public {
    assertEq(aaveRouter.aaveManager(), address(this), "invalid aave Manager");
  }

  function test_logs_new_aaveKandel() public {
    address maker = freshAddress("Maker");
    expectFrom(address(aaveSeeder));
    emit NewAaveKandel(maker, base, quote, 0xf5Ba21691a8bC011B7b430854B41d5be0B78b938, maker);
    vm.prank(maker);
    sowAave(true);
  }

  function test_logs_new_kandel() public {
    address maker = freshAddress("Maker");
    expectFrom(address(seeder));
    emit NewKandel(maker, base, quote, 0xa38D17ef017A314cCD72b8F199C0e108EF7Ca04c);
    vm.prank(maker);
    sow(true);
  }

  function test_maker_deploys_shared_aaveKandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = sowAave(true);

    assertEq(address(kdl.router()), address(aaveRouter), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.RESERVE_ID(), kdl.admin(), "Incorrect owner");
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kdl.checkList(tokens);
  }

  function test_maker_deploys_private_aaveKandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = sowAave(false);

    assertEq(address(kdl.router()), address(aaveRouter), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.RESERVE_ID(), address(kdl), "Incorrect owner");
    assertEq(kdl.offerGasreq(), 500_000 + 128_001);

    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kdl.checkList(tokens);
  }

  function test_maker_deploys_kandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = sow(false);
    assertEq(address(kdl.router()), address(kdl.NO_ROUTER()), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.RESERVE_ID(), address(kdl), "Incorrect owner");
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kdl.checkList(tokens);
  }
}
