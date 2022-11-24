// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Mango, IERC20, IMangrove} from "mgv_src/strategies/offer_maker/market_making/mango/Mango.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice Shifts Mango down or up to reequilibrate the OB
 */
/**
 * Usage example (shifting MANGO_WETH_USDC of `shift` positions
 *
 * MANGO=0x62EaBFE2e66dd9421b06042A0F10167BF62C97A3 \
 * SHIFT=5 \
 * DEFAULT_GIVES_AMOUNT=$(cast ff 6 1000) \
 * forge script --fork-url $MUMBAI_NODE_URL \
 * --private-key $MUMBAI_TESTER_PRIVATE_KEY \
 * --broadcast \
 * ShiftMango
 */

contract ShiftMango is Deployer {
  Mango MGO;
  IERC20 BASE;
  IERC20 QUOTE;
  uint NSLOTS;
  uint absShift;

  function run() public {
    innerRun({
      mgo: payable(vm.envAddress("MANGO")),
      shift: vm.envInt("SHIFT"),
      default_gives_amount: vm.envUint("DEFAULT_GIVES_AMOUNT")
    });
  }

  function innerRun(
    address payable mgo,
    int shift,
    uint default_gives_amount // in base amount if shift < 0, in quote amount otherwise
  ) public {
    MGO = Mango(mgo);
    require(MGO.admin() == broadcaster(), "This script requires admin rights");
    BASE = MGO.BASE();
    console.log("This mango uses", BASE.symbol(), "as base");
    QUOTE = MGO.QUOTE();
    console.log("This mango uses", QUOTE.symbol(), "as quote");
    NSLOTS = MGO.NSLOTS();
    console.log("And has", NSLOTS, "slots");
    absShift = shift < 0 ? uint(-shift) : uint(shift);

    uint[] memory amounts = new uint[](absShift);
    for (uint i = 0; i < amounts.length; i++) {
      amounts[i] = default_gives_amount;
    }
    console.log("Shifting of", absShift, "positions", shift < 0 ? "down..." : "up...");
    broadcast();
    MGO.setShift(shift, shift < 0, amounts);
  }
}
