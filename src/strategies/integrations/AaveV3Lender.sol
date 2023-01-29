// SPDX-License-Identifier:	BSD-2-Clause

// AaveV3Lender.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

/**
 * @notice This contract provides a collection of lending capabilities with AAVE-v3 to whichever contract inherits it
 */

import {IPool} from "../vendor/aave/v3/IPool.sol";
import {IPoolAddressesProvider} from "../vendor/aave/v3/IPoolAddressesProvider.sol";
import {IRewardsControllerIsh} from "../vendor/aave/v3/IRewardsControllerIsh.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

contract AaveV3Lender {
  /**
   * @notice address of the AAVE pool
   */
  IPool public immutable POOL;
  IPoolAddressesProvider public immutable ADDRESS_PROVIDER;

  /**
   * @notice contract's constructor
   * @param _addressesProvider address of AAVE's address provider
   */
  constructor(address _addressesProvider) {
    ADDRESS_PROVIDER = IPoolAddressesProvider(_addressesProvider);

    address _lendingPool = IPoolAddressesProvider(_addressesProvider).getPool();
    require(_lendingPool != address(0), "AaveModule/0xPool");

    POOL = IPool(_lendingPool);
  }

  /**
   * @notice allows this contract to approve the POOL to transfer some underlying asset on its behalf
   * @dev this is a necessary step prio to supplying tokens to the POOL or to repay a debt
   * @param token the underlying asset for which approval is required
   * @param amount the approval amount
   */
  function _approveLender(IERC20 token, uint amount) internal {
    token.approve(address(POOL), amount);
  }

  /**
   * @notice prevents the POOL to use some underlying as collateral
   * @dev this call will revert if removing the asset from collateral would put the account into a liquidation state
   * @param underlying the token one wishes to remove collateral
   */
  function _exitMarket(IERC20 underlying) internal {
    POOL.setUserUseReserveAsCollateral(address(underlying), false);
  }

  /**
   * @notice allows the POOL to use some underlying tokens as collateral
   * @dev when supplying a token for the first time, it is automatically set as possible collateral so there is no need to call this function for it.
   * @param underlyings the token one wishes to add as collateral
   */
  function _enterMarkets(IERC20[] calldata underlyings) internal {
    for (uint i = 0; i < underlyings.length; i++) {
      POOL.setUserUseReserveAsCollateral(address(underlyings[i]), true);
    }
  }

  /**
   * @notice convenience function to obtain the overlying of a given asset
   * @param asset the underlying asset
   * @return aToken the overlying asset
   */
  function overlying(IERC20 asset) public view returns (IERC20 aToken) {
    aToken = IERC20(POOL.getReserveData(address(asset)).aTokenAddress);
  }

  ///@notice redeems funds from the pool
  ///@param token the asset one is trying to redeem
  ///@param amount of assets one wishes to redeem
  ///@param to is the address where the redeemed assets should be transfered
  ///@return redeemed the amount of asset that were transfered to `to`
  function _redeem(IERC20 token, uint amount, address to) internal returns (uint redeemed) {
    redeemed = (amount == 0) ? 0 : POOL.withdraw(address(token), amount, to);
  }

  ///@notice supplies funds to the pool
  ///@param token the asset one is supplying
  ///@param amount of assets to be transfered to the pool
  ///@param onBehalf address of the account whose collateral is being supplied to
  function _supply(IERC20 token, uint amount, address onBehalf) internal {
    if (amount == 0) {
      return;
    } else {
      POOL.supply(address(token), amount, onBehalf, 0);
    }
  }

  ///@notice rewards claiming.
  ///@param assets list of overlying for which one is claiming awards
  ///@param to whom the rewards should be sent
  ///@return rewardsList the address of assets that have been claimed
  ///@return claimedAmounts the amount of assets that have been claimed
  function _claimRewards(address[] calldata assets, address to)
    internal
    returns (address[] memory rewardsList, uint[] memory claimedAmounts)
  {
    IRewardsControllerIsh rewardsController =
      IRewardsControllerIsh(ADDRESS_PROVIDER.getAddress(keccak256("INCENTIVES_CONTROLLER")));
    (rewardsList, claimedAmounts) = rewardsController.claimAllRewards(assets, to);
  }

  ///@notice gas costly function to verify whether an asset can be supplied on pool
  ///@param asset one wants to lend
  function checkAsset(IERC20 asset) public view returns (bool) {
    address[] memory reserves = POOL.getReservesList();
    for (uint i; i < reserves.length; i++) {
      if (reserves[i] == address(asset)) {
        return true;
      }
    }
    return false;
  }
}