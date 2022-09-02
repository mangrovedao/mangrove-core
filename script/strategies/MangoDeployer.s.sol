// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Mango, IERC20, IMangrove} from "mgv_src/strategies/single_user/market_making/mango/Mango.sol";
import {Deployer} from "../lib/Deployer.sol";

/** @notice deploys a Mango instance on a given market */
/** */
// forge script --fork-url $MUMBAI_NODE_URL \
// --private-key $MUMBAI_DEPLOYER_PRIVATE_KEY \
// --sig "run(string, address, address, address, uint, uint, uint, uint)" \
// --etherscan-api-key $POLYGONSCAN_API \
// --verify \
// MangoDeployer \
// 0xF3e339d8a0B989114412fa157Cc846ebaf4BCbd8 \
// 0x63e537a69b3f5b03f4f46c5765c82861bd874b6e \
// 0xc87385b5e62099f92d490750fcd6c901a524bbca \
// $(cast ff 18 1) \
// $(cast ff 18 200) \
// 100 \
// 36

contract MangoDeployer is Deployer {
  function run(
    address payable mgv,
    address base,
    address quote,
    uint base_0,
    uint quote_0,
    uint nslots,
    uint price_incr
  ) public {
    console.log(
      "Deploying Mango on market",
      IERC20(base).symbol(),
      IERC20(quote).symbol()
    );
    vm.broadcast();
    Mango mgo = new Mango(
      IMangrove(mgv),
      IERC20(base),
      IERC20(quote),
      base_0,
      quote_0,
      nslots,
      price_incr,
      msg.sender
    );
    outputDeployment();
    console.log("Mango deployed", address(mgo));
  }
}
