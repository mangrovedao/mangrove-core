// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@mgv/src/interfaces/IBlast.sol";

contract BaseBlast {
  IBlast public constant BLAST = IBlast(0x4300000000000000000000000000000000000002);
}
