// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Mango, IERC20, IMangrove} from "mgv_src/strategies/offer_maker/market_making/mango/Mango.sol";
import {Deployer} from "../lib/Deployer.sol";

/**
 * @notice deploys a Mango instance on a given market
 */
/**
 * First test:
 *  forge script
 *  NAME=<optional name in case symbols are ambiguous>
 *  BASE=WETH \
 *  QUOTE=0x<quote_address> \
 *  --fork-url mumbai MangoDeployer -vvv
 *
 * e.g deploy mango on WETH <quote> market:
 *
 *   WRITE_DEPLOY=true \
 *   BASE=WETH QUOTE=USDC BASE_0=$(cast ff 18 1) QUOTE_0=$(cast ff 6 800)\
 *   NSLOTS=100 PRICE_INCR=$(cast ff 6 10)\
 *   DEPLOYER=$MUMBAI_TESTER_ADDRESS\
 *   forge script --fork-url $LOCALHOST_URL  MangoDeployer --broadcast\
 *   --broadcast \
 *   MangoDeployer
 */

contract MangoDeployer is Deployer {
  Mango public current;

  function run() public {
    innerRun({
      base: envAddressOrName("BASE"),
      quote: envAddressOrName("QUOTE"),
      base_0: vm.envUint("BASE_0"),
      quote_0: vm.envUint("QUOTE_0"),
      nslots: vm.envUint("NSLOTS"),
      price_incr: vm.envUint("PRICE_INCR"),
      admin: vm.envAddress("DEPLOYER")
    });
  }

  /**
   * @param base Address of the base currency of the market Mango will act upon
   * @param quote Addres of the quote of Mango's market
   * @param base_0 in units of base. Amounts of initial `makerGives` for Mango's asks
   * @param quote_0 in units of quote. Amounts of initial `makerGives` for Mango's bids
   * @notice min price of Mango is determined by `quote_0/base_0`
   * @param nslots the number of price slots of the Mango strat
   * @param price_incr in units of quote. Price(i+1) = price(i) + price_incr
   * @param admin address of the adim on Mango after deployment
   */
  function innerRun(address base, address quote, uint base_0, uint quote_0, uint nslots, uint price_incr, address admin)
    public
  {
    IMangrove mgv = IMangrove(fork.get("Mangrove"));
    broadcast();
    console.log(broadcaster(), broadcaster().balance);
    current = new Mango(
      mgv,
      IERC20(base),
      IERC20(quote),
      base_0,
      quote_0,
      nslots,
      price_incr,
      admin
    );
    string memory mangoName = getName(IERC20(base), IERC20(quote));
    fork.set(mangoName, address(current));
    outputDeployment();
  }

  function getName(IERC20 base, IERC20 quote) public view returns (string memory) {
    try vm.envString("NAME") returns (string memory mangoName) {
      return mangoName;
    } catch {
      return string.concat("Mango_", base.symbol(), "_", quote.symbol());
    }
  }
}
