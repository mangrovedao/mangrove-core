// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {AaveV3Borrower, IERC20} from "mgv_src/strategies/integrations/AaveV3Borrower.sol";
import {MangroveTest, console} from "mgv_test/lib/MangroveTest.sol";

contract AaveCaller is AaveV3Borrower, MangroveTest {
  constructor(address _addressesProvider, uint borrowMode) AaveV3Borrower(_addressesProvider, 0, borrowMode) {}

  address callback;

  function setCallbackAddress(address cb) public {
    callback = cb;
  }

  function approveLender(IERC20 token) public {
    _approveLender(token, type(uint).max);
  }

  function supply(IERC20 token, uint amount) public {
    _supply(token, amount, address(this), false);
  }

  function borrow(IERC20 token, uint amount) public {
    _borrow(token, amount, address(this));
  }

  function redeem(IERC20 token, uint amount) public {
    _redeem(token, amount, address(this));
  }

  function executeOperation(address asset, uint amount, uint premium, address, bytes calldata cd)
    external
    returns (bool)
  {
    approveLender(IERC20(asset));
    deal(asset, address(this), amount + premium);
    console.log(
      "flashloan of %s succeeded, cost is %s %s",
      toUnit(amount, IERC20(asset).decimals()),
      toUnit(premium, IERC20(asset).decimals()),
      IERC20(asset).symbol()
    );
    (bool success,) = callback.call(cd);
    // attack is a success is callback succeeds
    return success;
  }

  function get_supply(IERC20 asset) public view returns (uint) {
    return asset.balanceOf(address(overlying(asset)));
  }

  function flashloan(IERC20 token, uint amount, bytes calldata cd) public {
    POOL.flashLoanSimple(address(this), address(token), amount, cd, 0);
  }

  function repay(IERC20 token, uint amount) public {
    _repay(token, amount, address(this));
  }
}
