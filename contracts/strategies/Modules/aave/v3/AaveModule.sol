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

  /// @notice Computes maximal maximal redeem capacity (R) and max borrow capacity (B|R) after R has been redeemed
  /// returns (R, B|R)
  function maxGettableUnderlying(
    IEIP20 asset,
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
    IEIP20 token,
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

  function exactRedeemThenBorrow(
    IEIP20 token,
    address to,
    uint amount
  ) internal returns (uint got) {
    (bool success, bytes memory retdata) = IMPLEMENTATION.delegatecall(
      abi.encodeWithSelector(
        AMI.$exactRedeemThenBorrow.selector,
        INTEREST_RATE_MODE,
        REFERRAL_CODE,
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
    IEIP20 token,
    uint amount,
    address to
  ) internal returns (uint redeemed) {
    redeemed = (amount == 0) ? 0 : POOL.withdraw(address(token), amount, to);
  }

  function _supply(
    IEIP20 token,
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
    IEIP20 token,
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
}
