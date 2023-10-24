// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {MangroveDeployer} from "mgv_script/core/deployers/MangroveDeployer.s.sol";

import {AbstractMangrove} from "mgv_src/AbstractMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {MangroveOrderDeployer} from "mgv_script/strategies/mangroveOrder/deployers/MangroveOrderDeployer.s.sol";
import {KandelSeederDeployer} from "mgv_script/strategies/kandel/deployers/KandelSeederDeployer.s.sol";
import {MangroveOrder} from "mgv_src/strategies/MangroveOrder.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {SimpleTestMaker} from "mgv_test/lib/agents/TestMaker.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {ActivateMarket} from "mgv_script/core/ActivateMarket.s.sol";
import {PoolAddressProviderMock} from "mgv_script/toy/AaveMock.sol";
import "forge-std/console.sol";

/* 
This script prepares a local server for testing by mangrove.js.

In the future it should a) Use mostly the normal deploy file, so there is as
little discrepancy between real deploys and deploys that mangrove.js tests
interact with.  b) For any additional deployments needed, those files should be
hosted in mangrove.js.*/

contract MangroveJsDeploy is Deployer {
  TestToken public tokenA;
  TestToken public tokenB;
  IERC20 public dai;
  IERC20 public usdc;
  IERC20 public weth;
  SimpleTestMaker public simpleTestMaker;
  MangroveOrder public mgo;

  function run() public {
    innerRun({gasprice: 1, gasmax: 2_000_000, gasbot: broadcaster()});
    outputDeployment();
  }

  function innerRun(uint gasprice, uint gasmax, address gasbot) public {
    MangroveDeployer mgvDeployer = new MangroveDeployer();

    mgvDeployer.innerRun({chief: broadcaster(), gasprice: gasprice, gasmax: gasmax, gasbot: gasbot});

    Mangrove mgv = mgvDeployer.mgv();
    MgvReader mgvReader = mgvDeployer.reader();

    broadcast();
    mgv.setUseOracle(false);

    broadcast();
    tokenA = new TestToken({
      admin: broadcaster(),
      name: "Token A",
      symbol: "TokenA",
      _decimals: 18
    });

    broadcast();
    tokenA.setMintLimit(type(uint).max);
    fork.set("TokenA", address(tokenA));

    broadcast();
    tokenB = new TestToken({
      admin: broadcaster(),
      name: "Token B",
      symbol: "TokenB",
      _decimals: 6
    });

    broadcast();
    tokenB.setMintLimit(type(uint).max);
    fork.set("TokenB", address(tokenB));

    broadcast();
    dai = new TestToken({
      admin: broadcaster(),
      name: "DAI",
      symbol: "DAI",
      _decimals: 18
    });
    fork.set("DAI", address(dai));

    broadcast();
    usdc = new TestToken({
      admin: broadcaster(),
      name: "USD Coin",
      symbol: "USDC",
      _decimals: 6
    });
    fork.set("USDC", address(usdc));

    broadcast();
    weth = new TestToken({
      admin: broadcaster(),
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

    ActivateMarket activateMarket = new ActivateMarket();

    activateMarket.innerRun(mgv, mgvReader, tokenA, tokenB, 2 * 1e9, 3 * 1e9, 0);
    activateMarket.innerRun(mgv, mgvReader, dai, usdc, 1e9 / 1000, 1e9 / 1000, 0);
    activateMarket.innerRun(mgv, mgvReader, weth, dai, 1e9, 1e9 / 1000, 0);
    activateMarket.innerRun(mgv, mgvReader, weth, usdc, 1e9, 1e9 / 1000, 0);

    MangroveOrderDeployer mgoeDeployer = new MangroveOrderDeployer();
    mgoeDeployer.innerRun({admin: broadcaster(), mgv: IMangrove(payable(mgv))});

    address[] memory underlying =
      dynamic([address(tokenA), address(tokenB), address(dai), address(usdc), address(weth)]);
    broadcast();
    address aaveAddressProvider = address(new PoolAddressProviderMock(underlying));

    KandelSeederDeployer kandelSeederDeployer = new KandelSeederDeployer();
    kandelSeederDeployer.innerRun({
      mgv: IMangrove(payable(mgv)),
      addressesProvider: aaveAddressProvider,
      aaveRouterGasreq: 318_000,
      aaveKandelGasreq: 338_000,
      kandelGasreq: 128_000,
      deployKandel: true,
      deployAaveKandel: true,
      testBase: IERC20(fork.get("WETH")),
      testQuote: IERC20(fork.get("DAI"))
    });

    broadcast();
    mgo = new MangroveOrder({mgv: IMangrove(payable(mgv)), deployer: broadcaster(), gasreq:30_000});
    fork.set("MangroveOrder", address(mgo));
  }
}
