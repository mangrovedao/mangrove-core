// SPDX-License-Identifier:	BSD-2-Clause

//AaveModule.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

import {AaveV3ModuleStorage as AMS} from "./AaveModuleStorage.sol";
import {AaveV3ModuleImplementation as AMI, IEIP20, IRewardsControllerIsh, IPoolAddressesProvider, IPool, IPriceOracleGetter, DataTypes} from "./AaveModuleImplementation.sol";

contract AaveV3Module {
  address private immutable IMPLEMENTATION;
  IPool public immutable POOL;
  IPriceOracleGetter public immutable ORACLE;

  constructor(address _addressesProvider, uint _referralCode) {
    require(
      uint16(_referralCode) == _referralCode,
      "Referral code should be uint16"
    );
    AMS.get_storage().referralCode = uint16(_referralCode); // for aave reference, put 0 for tests

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

  function referralCode() public view returns (uint16) {
    return AMS.get_storage().referralCode;
  }

  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with Aave
  /**************************************************************************/

  ///@notice approval of overlying contract by the underlying is necessary for minting and repaying borrow
  ///@notice user must use this function to do so.
  function _approveLender(IEIP20 token, uint amount) internal {
    token.approve(address(POOL), amount);
  }

  ///@notice exits markets
  function _exitMarket(IEIP20 underlying) internal {
    POOL.setUserUseReserveAsCollateral(address(underlying), false);
  }

  function _enterMarkets(IEIP20[] calldata underlyings) internal {
    for (uint i = 0; i < underlyings.length; i++) {
      POOL.setUserUseReserveAsCollateral(address(underlyings[i]), true);
    }
  }

  function overlying(IEIP20 asset) public view returns (IEIP20 aToken) {
    aToken = IEIP20(POOL.getReserveData(address(asset)).aTokenAddress);
  }

  /// @notice Computes maximal maximal redeem capacity (R) and max borrow capacity (B|R) after R has been redeemed
  /// returns (R, B|R)
  function maxGettableUnderlying(
    address asset,
    bool tryBorrow,
    address onBehalf
  )
    public
    returns (
      uint maxRedeemableUnderlying,
      uint maxBorrowAfterRedeemInUnderlying
    )
  {
    (bool success, bytes memory retdata) = IMPLEMENTATION.delegatecall(
      abi.encodeWithSelector(
        AMI.$maxGettableUnderlying.selector,
        asset,
        tryBorrow,
        onBehalf
      )
    );
    if (success) {
      (maxRedeemableUnderlying, maxBorrowAfterRedeemInUnderlying) = abi.decode(
        retdata,
        (uint, uint)
      );
    } else {
      AMS.revertWithData(retdata);
    }
  }

  function repayThenDeposit(
    uint interestRateMode,
    IEIP20 token,
    uint amount
  ) internal {
    (bool success, bytes memory retdata) = IMPLEMENTATION.delegatecall(
      abi.encodeWithSelector(
        AMI.$repayThenDeposit.selector,
        interestRateMode,
        token,
        amount
      )
    );
    if (!success) {
      AMS.revertWithData(retdata);
    }
  }

  function exactRedeemThenBorrow(
    uint interestRateMode,
    IEIP20 token,
    address to,
    uint amount
  ) internal returns (uint got) {
    (bool success, bytes memory retdata) = IMPLEMENTATION.delegatecall(
      abi.encodeWithSelector(
        AMI.$exactRedeemThenBorrow.selector,
        interestRateMode,
        token,
        to,
        amount
      )
    );
    if (success) {
      got = abi.decode(retdata, (uint));
    } else {
      AMS.revertWithData(retdata);
    }
  }

  function _borrow(
    IEIP20 token,
    uint amount,
    uint interestRateMode,
    address to
  ) internal {
    POOL.borrow(address(token), amount, interestRateMode, referralCode(), to);
  }

  function _redeem(
    IEIP20 token,
    uint amount,
    address to
  ) internal returns (uint redeemed) {
    redeemed = POOL.withdraw(address(token), amount, to);
  }

  function _mint(
    IEIP20 token,
    uint amount,
    address onBehalf
  ) internal {
    POOL.supply(address(token), amount, onBehalf, referralCode());
  }

  function _repay(
    IEIP20 token,
    uint amount,
    uint interestRateMode,
    address onBehalf
  ) internal returns (uint repaid) {
    return POOL.repay(address(token), amount, interestRateMode, onBehalf);
  }

  // rewards claiming.
  // may use `SingleUser.redeemToken` to move collected tokens afterwards
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
}
