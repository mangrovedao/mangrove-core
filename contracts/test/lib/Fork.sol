// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "forge-std/Vm.sol";

/* Only fork we deal with for now is Polygon
   In the future, strategies for managing multiple forks:
   * always import Fork, initialize it differently using env vars
   * always import Fork, but its locations depends on dynamic remapping
   * have multiple contracts (PolygonFork, AaveFork etc), and pick one depending on environment
*/
library Fork {
  // vm call setup
  address private constant VM_ADDRESS =
    address(bytes20(uint160(uint(keccak256("hevm cheat code")))));

  Vm public constant vm = Vm(VM_ADDRESS);

  // polygon mainnet addresses
  address constant AAVE = 0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb;
  address constant APOOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
  address constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
  address constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
  address constant AWETH = 0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8;
  address constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
  address constant ADAI = 0x82E64f49Ed5EC1bC6e43DAD4FC8Af9bb3A2312EE;
  address constant CDAI = 0x4eCEDdF62277eD78623f9A94995c680f8fd6C00e;
  address constant CUSDC = 0x73CF8c5D14Aa0EbC89f18272A568319F5BAB6cBD;
  address constant CWETH = 0x7ef18d0a9C3Fb1A716FF6c3ED0Edf52a2427F716;
  uint constant EXPECTED_CHAIN_ID = 137;
  string constant FORK_NAME = "Polygon";

  // temporarily duplicate function
  function uint2str(uint _i)
    internal
    pure
    returns (string memory _uintAsString)
  {
    unchecked {
      if (_i == 0) {
        return "0";
      }
      uint j = _i;
      uint len;
      while (j != 0) {
        len++;
        j /= 10;
      }
      bytes memory bstr = new bytes(len);
      uint k = len - 1;
      while (_i != 0) {
        bstr[k--] = bytes1(uint8(48 + (_i % 10)));
        _i /= 10;
      }
      return string(bstr);
    }
  }

  function setUp() public {
    if (block.chainid != 137) {
      revert(
        string.concat(
          "Chain id should be ",
          uint2str(EXPECTED_CHAIN_ID),
          " (",
          FORK_NAME,
          "), is ",
          uint2str(block.chainid)
        )
      );
    }

    vm.label(AAVE, "Aave");
    vm.label(APOOL, "Aave Pool");
    vm.label(WETH, "WETH");
    vm.label(USDC, "USDC");
    vm.label(AWETH, "AWETH");
    vm.label(DAI, "DAI");
    vm.label(ADAI, "ADAI");
    vm.label(CDAI, "CDAI");
    vm.label(CUSDC, "CUSDC");
    vm.label(CWETH, "CWETH");
  }
}
