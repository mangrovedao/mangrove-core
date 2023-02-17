// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Mango, IERC20, IMangrove} from "mgv_src/strategies/offer_maker/market_making/mango/Mango.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice Shuts down a Mango instance on a given market
 * Retracts all Mango offers, and recovers funds.
 */

/**
 * Usage example (retracting 100 bids and asks from MANGO_WETH_USDC)
 *
 * MANGO=0x1C9f224c402233006C438Ae081Ed35697b2A4919 \
 * FROM=0 \
 * TO=100 \
 * forge script --fork-url $MUMBAI_NODE_URL \
 * --private-key $MUMBAI_TESTER_PRIVATE_KEY \
 * --broadcast \
 * StopMango
 */

contract StopMango is Deployer {
  function run() public {
    innerRun({$mgo: payable(vm.envAddress("MANGO")), from: vm.envUint("FROM"), to: vm.envUint("TO")});
  }

  function innerRun(address payable $mgo, uint from, uint to) public {
    Mango mgo = Mango($mgo);
    uint n = mgo.NSLOTS();
    require(mgo.admin() == broadcaster(), "This script requires admin rights");
    require(from < n, "invalid start index");
    to = to >= n ? n - 1 : to;
    broadcast();
    uint collected = mgo.retractOffers(
      2, // both bids and asks
      from, // from
      to
    );
    uint bal = mgo.MGV().balanceOf($mgo);
    if (bal > 0) {
      collected += bal;
      broadcast();
      mgo.withdrawFromMangrove(bal, payable(broadcaster()));
    }
    console.log("Retracted", to - from, "offers");
    console.log("Recoverd", collected, "WEIs in doing so");
  }
}
