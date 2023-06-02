// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";

import {console} from "forge-std/console.sol";

/**
 * Mint lots of tokens for Greedy taker bot
 */

contract MumbaiMintTokensForGreedyTakerBot is Deployer {
  function run() public {
    address greedyTakerBotAccount = 0x3073A02460D7BE1A1C9afC60A059Ad8d788A4502;
    TestToken wmatic = TestToken(fork.get("WMATIC"));
    TestToken wbtc = TestToken(fork.get("WBTC"));
    TestToken usdt = TestToken(fork.get("USDT"));

    mint(wmatic, greedyTakerBotAccount, 1_000_000_000);
    mint(wbtc, greedyTakerBotAccount, 1_000_000_000);
    mint(usdt, greedyTakerBotAccount, 1_000_000_000);
  }

  function mint(TestToken token, address to, uint amountWithoutDecimals) internal {
    uint oldMintLimit = token.mintLimit();
    uint decimals = token.decimals();
    uint amountWithDecimals = amountWithoutDecimals * 10 ** decimals;

    broadcast();
    token.setMintLimit(type(uint).max);

    broadcast();
    token.mintTo(to, amountWithDecimals);

    broadcast();
    token.setMintLimit(oldMintLimit);
  }
}
