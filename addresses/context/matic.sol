// SPDX-License-Identifier: Unlicense
pragma solidity >= 0.7.4;

function load(function(string memory,address) internal addAddress) {
  addAddress("WETH", 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
  addAddress("USDC", 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
  addAddress("USDT", 0xc2132D05D31c914a87C6611C10748AEb04B58e8F);
  addAddress("DAI", 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063);
  addAddress("Gasbot", 0x10B124Da45Bc440171664cee59Aafa23979C9616);
  addAddress("MgvGovernance", 0x59a424169526ECae25856038598F862043DCeDf7);
}
