// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {
  KandelSeeder,
  IMangrove,
  GeometricKandel
} from "mgv_src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";

contract KandelSeederTest is MangroveTest {
  PinnedPolygonFork fork;
  KandelSeeder seeder;

  function seed(bool onAave, bool sharing) internal view returns (KandelSeeder.KandelSeed memory seed_) {
    seed_ = KandelSeeder.KandelSeed({
      base: base,
      quote: quote,
      gasprice: 0,
      onAave: onAave,
      compoundRateBase: 10_000,
      compoundRateQuote: 10_000,
      liquiditySharing: sharing
    });
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
      addressesProvider_: fork.get('Aave'), 
      routerGasreq: 500_000, 
      aaveKandelGasreq: 128_000, 
      kandelGasreq: 128_000
    });
  }

  function test_maker_deploys_shared_aaveKandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = seeder.sow(seed(true, true));

    assertEq(address(kdl.router()), address(seeder.AAVE_ROUTER()), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.reserveId(), kdl.admin(), "Incorrect owner");
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kdl.checkList(tokens, kdl.reserveId());
  }

  function test_maker_deploys_private_aaveKandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = seeder.sow(seed(true, false));

    assertEq(address(kdl.router()), address(seeder.AAVE_ROUTER()), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.reserveId(), address(kdl), "Incorrect owner");
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kdl.checkList(tokens, kdl.reserveId());
  }

  function test_maker_deploys_private_kandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = seeder.sow(seed(false, false));
    assertEq(address(kdl.router()), address(kdl.NO_ROUTER()), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.reserveId(), address(kdl), "Incorrect owner");
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kdl.checkList(tokens, kdl.reserveId());
  }

  function test_maker_deploys_shared_kandel() public {
    GeometricKandel kdl;
    address maker = freshAddress("Maker");
    vm.prank(maker);
    kdl = seeder.sow(seed(false, true));
    assertEq(address(kdl.router()), address(kdl.NO_ROUTER()), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.reserveId(), maker, "Incorrect owner");
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kdl.checkList(tokens, kdl.reserveId());
  }
}
