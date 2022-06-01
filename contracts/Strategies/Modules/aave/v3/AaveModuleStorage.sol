// SPDX-License-Identifier:	BSD-2-Clause

//AaveModuleStorage.sol

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

import "../../../interfaces/IMangrove.sol";
import "../../../interfaces/IEIP20.sol";

library AaveV3ModuleStorage {
  // address of the lendingPool
  // struct Layout {
  // }

  // function get_storage() internal pure returns (Layout storage st) {
  //   bytes32 storagePosition = keccak256(
  //     "Mangrove.AaveV3ModuleStorageLib.Layout"
  //   );
  //   assembly {
  //     st.slot := storagePosition
  //   }
  // }

  function revertWithData(bytes memory retdata) internal pure {
    if (retdata.length == 0) {
      revert("AaveModuleStorage/revertNoReason");
    }
    assembly {
      revert(add(retdata, 32), mload(retdata))
    }
  }
}
