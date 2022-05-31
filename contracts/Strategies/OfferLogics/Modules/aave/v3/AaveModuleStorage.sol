// SPDX-License-Identifier:	BSD-2-Clause

//AaveLender.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;
import "./IPool.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IRewardsControllerIsh} from "./IRewardsControllerIsh.sol";

import "./IPriceOracleGetter.sol";
import {ReserveConfiguration as RC} from "./ReserveConfiguration.sol";

import "../../../../interfaces/IMangrove.sol";
import "../../../../interfaces/IEIP20.sol";

contract AaveV3ModuleStorage {
  // address of the lendingPool
  IPool public lendingPool;
  IPriceOracleGetter public priceOracle;

  // cannot be immutable because address is known at AaveModule construction time
  address implementation;

  uint16 referralCode;

  // structs to avoir stack too deep in maxGettableUnderlying
  struct Underlying {
    uint ltv;
    uint liquidationThreshold;
    uint decimals;
    uint price;
  }

  struct Account {
    uint collateral;
    uint debt;
    uint borrowPower;
    uint redeemPower;
    uint ltv;
    uint liquidationThreshold;
    uint health;
    uint balanceOfUnderlying;
  }

  constructor(
    bool has_storage,
    address _addressesProvider,
    uint _referralCode
  ) {
    require(
      uint16(_referralCode) == _referralCode,
      "Referral code should be uint16"
    );

    referralCode = uint16(_referralCode); // for aave reference, put 0 for tests

    address _priceOracle;
    address _lendingPool;
    if (has_storage) {
      _priceOracle = IPoolAddressesProvider(_addressesProvider).getAddress(
        "PRICE_ORACLE"
      );
      _lendingPool = IPoolAddressesProvider(_addressesProvider).getPool();
      require(_priceOracle != address(0), "AaveModuleStorage/0xPriceOracle");
      require(_lendingPool != address(0), "AaveModuleStorage/0xPool");
    }
    lendingPool = IPool(_lendingPool);
    priceOracle = IPriceOracleGetter(_priceOracle);
  }
}
