// SPDX-License-Identifier:	BSD-2-Clause

//AaveLender.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;
import "./AaveModuleStorage.sol";
import {AaveV3ModuleImplementation as AMI} from "./AaveModuleImplementation.sol";

contract AaveV3Module is AaveV3ModuleStorage {
  address immutable implementation;

  constructor(address _addressesProvider, uint _referralCode)
    AaveV3ModuleStorage(_addressesProvider, _referralCode)
  {
    AMI impl = new AMI(_addressesProvider, _referralCode);
    implementation = address(impl);
  }

  function revertWithData(bytes memory retdata) internal pure {
    assembly {
      revert(add(retdata, 32), mload(retdata))
    }
  }

  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with Aave
  /**************************************************************************/

  ///@notice approval of overlying contract by the underlying is necessary for minting and repaying borrow
  ///@notice user must use this function to do so.
  function _approveLender(IEIP20 token, uint amount) internal {
    token.approve(address(lendingPool), amount);
  }

  ///@notice exits markets
  function _exitMarket(IEIP20 underlying) internal {
    lendingPool.setUserUseReserveAsCollateral(address(underlying), false);
  }

  function _enterMarkets(IEIP20[] calldata underlyings) internal {
    for (uint i = 0; i < underlyings.length; i++) {
      lendingPool.setUserUseReserveAsCollateral(address(underlyings[i]), true);
    }
  }

  function overlying(IEIP20 asset) public view returns (IEIP20 aToken) {
    aToken = IEIP20(lendingPool.getReserveData(address(asset)).aTokenAddress);
  }

  /// @notice Computes maximal maximal redeem capacity (R) and max borrow capacity (B|R) after R has been redeemed
  /// returns (R, B|R)

  function maxGettableUnderlying(
    address asset,
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
    (bool success, bytes memory retdata) = implementation.staticcall(
      abi.encodeWithSelector(
        AMI.maxGettableUnderlying.selector,
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
      revertWithData(retdata);
    }
  }

  function repayThenDeposit(
    uint interestRateMode,
    IEIP20 token,
    uint amount
  ) internal {
    (bool success, bytes memory retdata) = implementation.delegatecall(
      abi.encodeWithSelector(
        AMI.repayThenDeposit.selector,
        interestRateMode,
        token,
        amount
      )
    );
    if (!success) {
      revertWithData(retdata);
    }
  }

  function exactRedeemThenBorrow(
    uint interestRateMode,
    IEIP20 token,
    address to,
    uint amount
  ) internal returns (uint got) {
    (bool success, bytes memory retdata) = implementation.delegatecall(
      abi.encodeWithSelector(
        AMI.exactRedeemThenBorrow.selector,
        interestRateMode,
        token,
        to,
        amount
      )
    );
    if (success) {
      got = abi.decode(retdata, (uint));
    } else {
      revertWithData(retdata);
    }
  }

  function _borrow(
    IEIP20 token,
    uint amount,
    uint interestRateMode,
    address to
  ) internal {
    lendingPool.borrow(
      address(token),
      amount,
      interestRateMode,
      referralCode,
      to
    );
  }

  function _redeem(
    IEIP20 token,
    uint amount,
    address to
  ) internal returns (uint redeemed) {
    redeemed = lendingPool.withdraw(address(token), amount, to);
  }

  function _mint(
    IEIP20 token,
    uint amount,
    address onBehalf
  ) internal {
    lendingPool.supply(address(token), amount, onBehalf, referralCode);
  }

  function _repay(
    IEIP20 token,
    uint amount,
    uint interestRateMode,
    address onBehalf
  ) internal returns (uint repaid) {
    return
      lendingPool.repay(address(token), amount, interestRateMode, onBehalf);
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
