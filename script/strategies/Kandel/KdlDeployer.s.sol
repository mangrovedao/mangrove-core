// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {
  ExplicitKandel as Kandel,
  IERC20,
  IMangrove
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveTest, Test} from "mgv_test/lib/MangroveTest.sol";

/**
 * @notice deploys a Kandel instance on a given market
 * @dev since the max number of price slot Kandel can use is an immutable, one should deploy Kandel on a large price range.
 */

contract KdlDeployer is Deployer {
  Kandel public current;

  function run() public {
    innerRun({
      base: envAddressOrName("BASE"),
      quote: envAddressOrName("QUOTE"),
      nslots: vm.envUint("NSLOTS"),
      gasreq: 160_000
    });
  }

  /**
   * @param base Address of the base token of the market Kandel will act on
   * @param quote Address of the quote token of the market Kandel will act on
   * @param nslots the number of price slots of the Kandel strat
   * @param gasreq the gas required for the offer logic
   */
  function innerRun(address base, address quote, uint nslots, uint gasreq) public {
    IMangrove mgv = IMangrove(fork.get("Mangrove"));
    broadcast();
    current = new Kandel(
      mgv,
      IERC20(base),
      IERC20(quote),
      gasreq,
      uint16(nslots)
    );
    string memory kandelName = getName(IERC20(base), IERC20(quote));
    fork.set(kandelName, address(current));
    outputDeployment();
  }

  function getName(IERC20 base, IERC20 quote) public view returns (string memory) {
    try vm.envString("NAME") returns (string memory name) {
      return name;
    } catch {
      return string.concat("Kandel_", base.symbol(), "_", quote.symbol());
    }
  }
}
