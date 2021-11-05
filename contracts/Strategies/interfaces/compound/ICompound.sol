// SPDX-License-Identifier: Unlicense

// ICompound.sol

// This is free and unencumbered software released into the public domain.

// Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

// In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// For more information, please refer to <https://unlicense.org/>

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../../../MgvLib.sol";

interface ICompoundPriceOracle {
  function getUnderlyingPrice(IcERC20 cToken) external view returns (uint);
}

interface IComptroller {
  // adding usefull public getters
  function oracle() external returns (ICompoundPriceOracle priceFeed);

  function markets(address cToken)
    external
    view
    returns (
      bool isListed,
      uint collateralFactorMantissa,
      bool isComped
    );

  /*** Assets You Are In ***/

  function enterMarkets(address[] calldata cTokens)
    external
    returns (uint[] memory);

  function exitMarket(address cToken) external returns (uint);

  function getAccountLiquidity(address user)
    external
    view
    returns (
      uint errorCode,
      uint liquidity,
      uint shortfall
    );

  function claimComp(address holder) external;

  function checkMembership(address account, IcERC20 cToken)
    external
    view
    returns (bool);
}

interface IcERC20 is IERC20 {
  // from https://github.com/compound-finance/compound-protocol/blob/master/contracts/CTokenInterfaces.sol
  function redeem(uint redeemTokens) external returns (uint);

  function borrow(uint borrowAmount) external returns (uint);

  // for non cETH only
  function repayBorrow(uint repayAmount) external returns (uint);

  // for cETH only
  function repayBorrow() external payable;

  // for non cETH only
  function repayBorrowBehalf(address borrower, uint repayAmount)
    external
    returns (uint);

  // for cETH only
  function repayBorrowBehalf(address borrower) external payable;

  function balanceOfUnderlying(address owner) external returns (uint);

  function getAccountSnapshot(address account)
    external
    view
    returns (
      uint,
      uint,
      uint,
      uint
    );

  function borrowRatePerBlock() external view returns (uint);

  function supplyRatePerBlock() external view returns (uint);

  function totalBorrowsCurrent() external returns (uint);

  function borrowBalanceCurrent(address account) external returns (uint);

  function borrowBalanceStored(address account) external view returns (uint);

  function exchangeRateCurrent() external returns (uint);

  function exchangeRateStored() external view returns (uint);

  function getCash() external view returns (uint);

  function accrueInterest() external returns (uint);

  function seize(
    address liquidator,
    address borrower,
    uint seizeTokens
  ) external returns (uint);

  function redeemUnderlying(uint redeemAmount) external returns (uint);

  function mint(uint mintAmount) external returns (uint);

  // only in cETH
  function mint() external payable;

  // non cETH only
  function underlying() external view returns (address); // access to public variable containing the address of the underlying ERC20

  function isCToken() external view returns (bool); // public constant froim CTokenInterfaces.sol
}
