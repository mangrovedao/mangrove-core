// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_src/Mangrove.sol";
import "./TestMaker.sol";
import "mgv_test/lib/tokens/TestToken.sol";

contract MakerDeployer {
  address payable[] makers;
  bool deployed;
  AbstractMangrove mgv;
  address base;
  address quote;

  constructor(
    AbstractMangrove _mgv,
    address _base,
    address _quote
  ) {
    mgv = _mgv;
    base = _base;
    quote = _quote;
  }

  function dispatch() external {
    uint k = makers.length;
    uint perMaker = address(this).balance / k;
    require(perMaker > 0, "0 ether to transfer");
    for (uint i = 0; i < k; i++) {
      address payable maker = makers[i];
      bool ok = maker.send(perMaker);
      require(ok);
    }
  }

  function length() external view returns (uint) {
    return makers.length;
  }

  function getMaker(uint i) external view returns (TestMaker) {
    return TestMaker(makers[i]);
  }

  function deploy(uint k) external {
    if (!deployed) {
      makers = new address payable[](k);
      for (uint i = 0; i < k; i++) {
        makers[i] = payable(
          address(new TestMaker(mgv, TestToken(base), TestToken(quote)))
        );
        TestMaker(makers[i]).approveMgv(TestToken(base), 10 ether);
        TestMaker(makers[i]).shouldFail(i == 0); //maker-0 is failer
      }
    }
    deployed = true;
  }
}
