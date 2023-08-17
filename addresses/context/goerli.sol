// SPDX-License-Identifier: Unlicense
pragma solidity >= 0.7.4;

function load(function(string memory,address) internal loader) {
  addAddress("WETH", 0x695364ffAA20F205e337f9e6226e5e22525838d9);
  addAddress("USDC", 0x3a034fe373b6304f98b7a24a3f21c958946d407);
  addAddress("DAI", 0xD77b79BE3e85351fF0cbe78f1B58cf8d1064047C);
}
