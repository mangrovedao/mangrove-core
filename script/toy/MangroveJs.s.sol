// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {MangroveDeployer} from "mgv_script/lib/MangroveDeployer.sol";

import {AbstractMangrove} from "mgv_src/AbstractMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {MangroveOrderDeployer} from "mgv_script/strategies/MangroveOrderDeployer.s.sol";
import {MangroveOrder} from "mgv_src/strategies/MangroveOrderEnriched.sol";
import {SimpleTestMaker} from "mgv_test/lib/agents/TestMaker.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/* 
This script prepares a local server for testing by mangrove.js.

In the future it should a) Use mostly the normal deploy file, so there is as
little discrepancy between real deploys and deploys that mangrove.js tests
interact with.  b) For any additional deployments needed, those files should be
hosted in mangrove.js.*/

contract MangroveJsDeploy is Deployer {
  IERC20 tokenA;
  IERC20 tokenB;
  IERC20 dai;
  IERC20 usdc;
  IERC20 weth;
  SimpleTestMaker simpleTestMaker;
  MangroveOrder mgo;

  function run() public {
    innerRun({chief: broadcaster(), gasprice: 1, gasmax: 2_000_000});
    outputDeployment();
  }

  function innerRun(address chief, uint gasprice, uint gasmax) public {
    MangroveDeployer mgvDeployer = new MangroveDeployer();

    mgvDeployer.innerRun({chief: chief, gasprice: gasprice, gasmax: gasmax});

    address mgv = address(mgvDeployer.mgv());

    broadcast();
    tokenA = new TestToken({
      admin: chief,
      name: "Token A",
      symbol: "TokenA",
      _decimals: 18
    });
    fork.set("TokenA", address(tokenA));

    broadcast();
    tokenB = new TestToken({
      admin: chief,
      name: "Token B",
      symbol: "TokenB",
      _decimals: 6
    });
    fork.set("TokenB", address(tokenB));

    broadcast();
    dai = new TestToken({
      admin: chief,
      name: "DAI",
      symbol: "DAI",
      _decimals: 18
    });
    fork.set("DAI", address(dai));

    broadcast();
    usdc = new TestToken({
      admin: chief,
      name: "USD Coin",
      symbol: "USDC",
      _decimals: 6
    });
    fork.set("USDC", address(usdc));

    broadcast();
    weth = new TestToken({
      admin: chief,
      name: "Wrapped Ether",
      symbol: "WETH",
      _decimals: 18
    });
    fork.set("WETH", address(weth));

    broadcast();
    simpleTestMaker = new SimpleTestMaker({
      _mgv: AbstractMangrove(payable(mgv)),
      _base: tokenA,
      _quote: tokenB
    });
    fork.set("SimpleTestMaker", address(simpleTestMaker));

    MangroveOrderDeployer mgoeDeployer = new MangroveOrderDeployer();
    mgoeDeployer.innerRun({admin: chief, mangrove: mgv});

    broadcast();
    mgo = new MangroveOrder({mgv: IMangrove(payable(mgv)), deployer: chief, gasreq:30_000});
    fork.set("MangroveOrder", address(mgo));
  }
}
