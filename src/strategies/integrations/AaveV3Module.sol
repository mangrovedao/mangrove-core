// SPDX-License-Identifier:	BSD-2-Clause

// AaveV2Module.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

// TODO-foundry-merge explain what this contract does

import {AaveV3ModuleStorage as AMS} from "./AaveModuleStorage.sol";
import {AaveV3ModuleImplementation as AMI, IERC20, IRewardsControllerIsh, IPoolAddressesProvider, IPool, ICreditDelegationToken, IPool, IPriceOracleGetter, DataTypes} from "./AaveModuleImplementation.sol";

contract AaveV3Module {
  address public immutable IMPLEMENTATION;
  IPool public immutable POOL;
  IPriceOracleGetter public immutable ORACLE;
  uint public immutable INTEREST_RATE_MODE;
  uint16 public immutable REFERRAL_CODE;

  constructor(
    address _addressesProvider,
    uint _referralCode,
    uint _interestRateMode
  ) {
    REFERRAL_CODE = uint16(_referralCode);
    INTEREST_RATE_MODE = _interestRateMode;

    address _priceOracle = IPoolAddressesProvider(_addressesProvider)
      .getAddress("PRICE_ORACLE");
    address _lendingPool = IPoolAddressesProvider(_addressesProvider).getPool();
    require(_priceOracle != address(0), "AaveModule/0xPriceOracle");
    require(_lendingPool != address(0), "AaveModule/0xPool");

    POOL = IPool(_lendingPool);
    ORACLE = IPriceOracleGetter(_priceOracle);
    IMPLEMENTATION = address(
      new AMI(IPool(_lendingPool), IPriceOracleGetter(_priceOracle))
    );
  }

  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with Aave
  /**************************************************************************/

  ///@notice approval the POOL contract by the underlying is necessary for supplying and repaying debt
  ///@notice user must use this function to do so.
  function _approveLender(IERC20 token, uint amount) internal {
    token.approve(address(POOL), amount);
  }

  ///@notice exits markets
  function _exitMarket(IERC20 underlying) internal {
    POOL.setUserUseReserveAsCollateral(address(underlying), false);
  }

  function _enterMarkets(IERC20[] calldata underlyings) internal {
    for (uint i = 0; i < underlyings.length; i++) {
      POOL.setUserUseReserveAsCollateral(address(underlyings[i]), true);
    }
  }

  function overlying(IERC20 asset) public view returns (IERC20 aToken) {
    aToken = IERC20(POOL.getReserveData(address(asset)).aTokenAddress);
  }

  function debtToken(IERC20 asset)
    public
    view
    returns (ICreditDelegationToken debtTkn)
  {
    debtTkn = INTEREST_RATE_MODE == 1
      ? ICreditDelegationToken(
        POOL.getReserveData(address(asset)).stableDebtTokenAddress
      )
      : ICreditDelegationToken(
        POOL.getReserveData(address(asset)).variableDebtTokenAddress
      );
  }

  function _staticdelegatecall(bytes calldata data) external {
    require(msg.sender == address(this), "AaveModule/internalOnly");
    (bool success, bytes memory retdata) = IMPLEMENTATION.delegatecall(data);
    if (!success) {
      AMS.revertWithData(retdata);
    }
    assembly {
      return(add(retdata, 32), returndatasize())
    }
  }

  /// @param asset the underlying asset to redeem and borrow
  /// @param tryBorrow compute borrow capacity (costs extra gas)
  /// @param onBehalf user for whom max redeem/borrow is computed
  /// @return maxRedeemableUnderlying how much `onBehalf` can redeem of `asset`
  /// @return maxBorrowAfterRedeemInUnderlying how much `onBehalf` could borrow in `asset` after redeeming `maxRedeemableUnderlying` if `tryBorrow` is `true`, 0 otherwise.
  /// @dev Return max redeem and borrow capacity conditional on a potential redeem
  /// @dev Using those values will might make you liquidatable at the next block
  function maxGettableUnderlying(
    IERC20 asset,
    bool tryBorrow,
    address onBehalf
  )
    public
    view
    returns (
      uint maxRedeemableUnderlying,
      uint maxBorrowAfterRedeemInUnderlying
    )
  {
    (bool success, bytes memory retdata) = address(this).staticcall(
      abi.encodeWithSelector(
        this._staticdelegatecall.selector,
        abi.encodeWithSelector(
          AMI.$maxGettableUnderlying.selector,
          asset,
          tryBorrow,
          onBehalf
        )
      )
    );
    if (!success) {
      AMS.revertWithData(retdata);
    } else {
      return abi.decode(retdata, (uint, uint));
    }
  }

  function repayThenDeposit(
    IERC20 token,
    address onBehalf,
    uint amount
  ) internal {
    (bool success, bytes memory retdata) = IMPLEMENTATION.delegatecall(
      abi.encodeWithSelector(
        AMI.$repayThenDeposit.selector,
        INTEREST_RATE_MODE,
        REFERRAL_CODE,
        token,
        onBehalf,
        amount
      )
    );
    if (!success) {
      AMS.revertWithData(retdata);
    }
  }

  ///@notice redeems liquidity on aave, if not enough liquidity is redeemed, tries to borrow what's missing.
  ///@param token the asset that needs to be redeemed
  ///@param onBehalf the account whose collateral is beeing redeemed and borrowed upon.
  ///@dev if `onBehalf != address(this)` then `this` needs to be approved by `onBehalf` using `ICreditDelegationToken.approveDelegation`
  ///@param amount the target amount of `token` one needs to redeem
  ///@param strict whether call allows contract to redeem more than amount (for gas optimization).
  ///@dev function will only try to borrow if less than `amount` was redeemed and will not try to borrow more than what is missing, even if `strict` is not required.
  ///@dev this is forced by aave v3 currently not allowing to repay a debt that was incurred on the same block (so no gas optim can be used). Repaying on the next block would be dangerous as `onBehalf` position could possibly be liquidated
  ///@param recipient the target address to which redeemed and borrowed tokens should be sent
  function redeemThenBorrow(
    IERC20 token,
    address onBehalf,
    uint amount,
    bool strict,
    address recipient
  ) internal returns (uint got) {
    (bool success, bytes memory retdata) = IMPLEMENTATION.delegatecall(
      abi.encodeWithSelector(
        AMI.$redeemThenBorrow.selector,
        INTEREST_RATE_MODE,
        REFERRAL_CODE,
        token,
        onBehalf,
        amount,
        strict,
        recipient
      )
    );
    if (success) {
      got = abi.decode(retdata, (uint));
    } else {
      AMS.revertWithData(retdata);
    }
  }

  function _borrow(
    IERC20 token,
    uint amount,
    address onBehalf
  ) internal {
    POOL.borrow(
      address(token),
      amount,
      INTEREST_RATE_MODE,
      REFERRAL_CODE,
      onBehalf
    );
  }

  function _redeem(
    IERC20 token,
    uint amount,
    address to
  ) internal returns (uint redeemed) {
    redeemed = (amount == 0) ? 0 : POOL.withdraw(address(token), amount, to);
  }

  function _supply(
    IERC20 token,
    uint amount,
    address onBehalf
  ) internal {
    if (amount == 0) {
      return;
    } else {
      POOL.supply(address(token), amount, onBehalf, REFERRAL_CODE);
    }
  }

  function _repay(
    IERC20 token,
    uint amount,
    address onBehalf
  ) internal returns (uint repaid) {
    repaid = (amount == 0)
      ? 0
      : POOL.repay(address(token), amount, INTEREST_RATE_MODE, onBehalf);
  }

  // rewards claiming.
  // may use `SingleUser.withdrawToken` to move collected tokens afterwards
  function _claimRewards(
    IRewardsControllerIsh rewardsController,
    address[] calldata assets
  )
    internal
    returns (address[] memory rewardsList, uint[] memory claimedAmounts)
  {
    (rewardsList, claimedAmounts) = rewardsController.claimAllRewardsToSelf(
      assets
    );
  }

  // @dev user can only borrow underlying in variable or stable, not both
  function borrowed(address underlying, address account)
    public
    view
    returns (uint)
  {
    DataTypes.ReserveData memory rd = POOL.getReserveData(underlying);
    uint vborrow = IERC20(rd.variableDebtTokenAddress).balanceOf(account);
    uint sborrow = IERC20(rd.stableDebtTokenAddress).balanceOf(account);
    return sborrow >= vborrow ? sborrow : vborrow;
  }
}
