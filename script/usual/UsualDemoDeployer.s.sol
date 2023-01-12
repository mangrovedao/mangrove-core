// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {LockedWrapperToken} from "mgv_src/usual/LockedWrapperToken.sol";
import {MetaPLUsDAOToken} from "mgv_src/usual/MetaPLUsDAOToken.sol";
import {PLUsMgvStrat} from "mgv_src/usual/PLUsMgvStrat.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

// This script deploys the Usual demo contracts
contract UsualDemoDeployer is Deployer {
  function run() public {
    address seller = envAddressOrName("SELLER_ADDRESS");
    address taker = envAddressOrName("TAKER_ADDRESS");

    uint sellerLUsDAOAmount = 10e18;
    uint takerUsUSDAmount = 100e18;

    IMangrove mgv = IMangrove(fork.get("Mangrove"));

    broadcast();
    TestToken usUSDToken =
      new TestToken({ admin: msg.sender, name: "Usual USD stable coin", symbol: "UsUSD", _decimals: 18 });
    fork.set("UsUSD", address(usUSDToken));

    broadcast();
    TestToken usDAOToken =
      new TestToken({ admin: msg.sender, name: "Usual governance token", symbol: "UsDAO", _decimals: 18 });
    fork.set("UsDAO", address(usDAOToken));

    broadcast();
    LockedWrapperToken lUsDAOToken =
    new LockedWrapperToken({ admin: msg.sender, name: "Locked Usual governance token", symbol: "LUsDAO", _underlying: usDAOToken });
    fork.set("LUsDAO", address(lUsDAOToken));

    broadcast();
    LockedWrapperToken pLUsDAOToken =
    new LockedWrapperToken({ admin: msg.sender, name: "Price-locked Usual governance token", symbol: "PLUsDAO", _underlying: lUsDAOToken });
    fork.set("PLUsDAO", address(pLUsDAOToken));

    broadcast();
    MetaPLUsDAOToken metaPLUsDAOToken =
    new MetaPLUsDAOToken({ admin: msg.sender, _name: "Meta Price-locked Usual governance token", _symbol: "Meta-PLUsDAO", lUsDAOToken: lUsDAOToken, pLUsDAOToken: pLUsDAOToken, mangrove: address(mgv) });
    fork.set("Meta-PLUsDAO", address(metaPLUsDAOToken));

    broadcast();
    PLUsMgvStrat pLUsMgvStrat =
    // new PLUsMgvStrat({ admin: msg.sender, mgv: mgv, pLUsDAOToken: pLUsDAOToken, usUSD: usUSDToken });
     new PLUsMgvStrat({mgv: mgv, pLUsDAOToken: pLUsDAOToken, metaPLUsDAOToken: metaPLUsDAOToken});
    fork.set("PLUsMgvStrat", address(pLUsMgvStrat));

    // Setup tx's. Placed after deployments to keep addresses stable
    // Activate PLUsMgvStrat
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = IERC20(metaPLUsDAOToken);
    tokens[1] = IERC20(usUSDToken);
    broadcast();
    pLUsMgvStrat.activate(tokens);
    // FIXME: PLUsMgvStrat is single-user in this demo, so set seller to admin
    broadcast();
    pLUsMgvStrat.setAdmin(seller);

    // Tell Meta-PLUsDAO the address of PLUsMgvStrat
    broadcast();
    metaPLUsDAOToken.setPLUsMgvStrat(address(pLUsMgvStrat));

    // Mint tokens for seller and taker
    broadcast();
    usUSDToken.mint(taker, takerUsUSDAmount);
    broadcast();
    usDAOToken.addAdmin(address(lUsDAOToken)); // Allow LUsDAO to mint UsDAO
    broadcast();
    lUsDAOToken.mint(seller, sellerLUsDAOAmount);

    // Whitelistings
    //   PLUsDAO for LUsDAO
    broadcast();
    lUsDAOToken.addToWhitelist(address(pLUsDAOToken));
    //   Meta-PLUsDAO for PLUsDAO
    broadcast();
    pLUsDAOToken.addToWhitelist(address(metaPLUsDAOToken));
    //   PLUsMgvStrat for PLUsDAO
    broadcast();
    pLUsDAOToken.addToWhitelist(address(pLUsMgvStrat));
    //   PLUsMgvStrat for Meta-PLUsDAO
    broadcast();
    metaPLUsDAOToken.addToWhitelist(address(pLUsMgvStrat));
    //   Mangrove for Meta-PLUsDAO
    broadcast();
    metaPLUsDAOToken.addToWhitelist(address(mgv));

    outputDeployment();
  }
}
