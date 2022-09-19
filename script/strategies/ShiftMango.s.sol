// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Mango, IERC20, IMangrove} from "mgv_src/strategies/offer_maker/market_making/mango/Mango.sol";

/** @notice Shifts Mango down or up to reequilibrate the OB */
/** Usage example (shifting MANGO_WETH_USDC of `shift` positions*/

// forge script --fork-url $MUMBAI_NODE_URL \
// --private-key $MUMBAI_TESTER_PRIVATE_KEY \
// --sig "run(address, int, uint)" \
// --broadcast \
// ShiftMango \
// 0x62EaBFE2e66dd9421b06042A0F10167BF62C97A3 5 $(cast ff 6 1000)

contract ShiftMango is Script {
  Mango MGO;
  IERC20 BASE;
  IERC20 QUOTE;
  uint NSLOTS;
  uint absShift;

  function run(
    address payable mgo,
    int shift,
    uint default_gives_amount // in base amount if shift < 0, in quote amount otherwise
  ) public {
    MGO = Mango(mgo);
    require(MGO.admin() == msg.sender, "This script requires admin rights");
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
    console.log(
      "Shifting of",
      absShift,
      "positions",
      shift < 0 ? "down..." : "up..."
    );
    vm.broadcast();
    MGO.setShift(shift, shift < 0, amounts);
  }
}
