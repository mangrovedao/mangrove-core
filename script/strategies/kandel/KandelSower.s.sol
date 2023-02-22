// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {GeometricKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {AaveKandelSeeder} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandelSeeder.sol";
import {
  KandelSeeder, AbstractKandelSeeder
} from "mgv_src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveTest, Test} from "mgv_test/lib/MangroveTest.sol";

/**
 * @notice deploys a Kandel instance on a given market
 * @dev since the max number of price slot Kandel can use is an immutable, one should deploy Kandel on a large price range.
 * @dev Example: WRITE_DEPLOY=true BASE=WETH QUOTE=USDC GASPRICE_FACTOR=10 COMPOUND_RATE_BASE=100 COMPOUND_RATE_QUOTE=100 forge script --fork-url $LOCALHOST_URL KandelDeployer --broadcast --private-key $MUMBAI_PRIVATE_KEY
 */

contract KandelSower is Deployer {
  function run() public {
    innerRun({
      base: envAddressOrName("BASE"),
      quote: envAddressOrName("QUOTE"),
      gaspriceFactor: vm.envUint("GASPRICE_FACTOR"), // 10 means cover 10x the current gasprice of Mangrove
      sharing: vm.envBool("SHARING"),
      onAave: vm.envBool("ON_AAVE")
    });
    outputDeployment();
  }

  /**
   * @param base Address of the base token of the market Kandel will act on
   * @param quote Address of the quote token of the market Kandel will act on
   * @param gaspriceFactor multiplier of Mangrove's gasprice used to compute Kandel's provision
   * @param sharing whether the deployed (aave) Kandel should allow shared liquidity
   * @param onAave whether AaveKandel should be deployed instead of Kandel
   */
  function innerRun(address base, address quote, uint gaspriceFactor, bool sharing, bool onAave) public {
    IMangrove mgv = IMangrove(fork.get("Mangrove"));
    (MgvStructs.GlobalPacked global,) = mgv.config(address(0), address(0));
    AbstractKandelSeeder seeder =
      onAave ? AaveKandelSeeder(fork.get("AaveKandelSeeder")) : AaveKandelSeeder(fork.get("KandelSeeder"));

    broadcast();
    GeometricKandel kdl = seeder.sow(
      AbstractKandelSeeder.KandelSeed({
        base: IERC20(base),
        quote: IERC20(quote),
        gasprice: global.gasprice() * gaspriceFactor,
        liquiditySharing: sharing
      })
    );

    string memory kandelName = getName(IERC20(base), IERC20(quote), onAave);
    fork.set(kandelName, address(kdl));
    smokeTest(kdl, onAave);
  }

  function getName(IERC20 base, IERC20 quote, bool onAave) public view returns (string memory) {
    try vm.envString("NAME") returns (string memory name) {
      return name;
    } catch {
      string memory baseName = onAave ? "AaveKandel_" : "Kandel_";
      return string.concat(baseName, base.symbol(), "_", quote.symbol());
    }
  }

  function smokeTest(GeometricKandel kdl, bool onAave) internal {
    require(kdl.admin() == broadcaster(), "Incorrect admin for Kandel");
    require(onAave || address(kdl.router()) == address(0), "Inccorrect router");
  }
}
