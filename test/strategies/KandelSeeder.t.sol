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
  PinnedPolygonFork fork;
  AbstractKandelSeeder seeder;
  AbstractKandelSeeder aaveSeeder;
  AavePooledRouter aaveRouter;

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
    fork = new PinnedPolygonFork();
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
      addressesProvider: fork.get('Aave'), 
      routerGasreq: 500_000, 
      aaveKandelGasreq: 128_001
    });
    aaveSeeder = aaveKandelSeeder;
    aaveRouter = aaveKandelSeeder.AAVE_ROUTER();
  }

  function test_aave_manager_is_attributed() public {
    assertEq(aaveRouter.aaveManager(), address(this), "invalid aave Manager");
  }

  function test_logs_new_aaveKandel() public {
    address maker = freshAddress("Maker");
    expectFrom(address(aaveSeeder));
    emit NewAaveKandel(maker, base, quote, 0x746326d3E4e54BA617F8aB39A21b7420aE8bF97d, maker);
    vm.prank(maker);
    sowAave(true);
  }

  function test_logs_new_kandel() public {
    address maker = freshAddress("Maker");
    expectFrom(address(seeder));
    emit NewKandel(maker, base, quote, 0x5B0091f49210e7B2A57B03dfE1AB9D08289d9294);
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

  function test_maker_deploys_private_kandel() public {
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

  function test_maker_deploys_shared_kandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = sow(true);
    assertEq(address(kdl.router()), address(kdl.NO_ROUTER()), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.RESERVE_ID(), maker, "Incorrect owner");
    assertEq(kdl.offerGasreq(), 128_000);
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kdl.checkList(tokens);
  }
}
