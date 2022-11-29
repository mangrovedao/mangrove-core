// SPDX-License-Identifier:	BSD-2-Clause

// MangroveOfferStorage.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import "mgv_src/strategies/interfaces/IOfferLogic.sol";

/// @title This is the storage part of a diamond storage scheme for `MangroveOffer` to reduce size of contracts.
library MangroveOfferStorage {
  /// @notice The layout of the storage.
  /// @param router the router to pull outbound tokens from contract's reserve to `this` and push inbound tokens to reserve.
  struct Layout {
    AbstractRouter router;
  }

  /// @notice Gets the `MangroveOffer` storage from a fixed slot.
  function getStorage() internal pure returns (Layout storage st) {
    // Unique slot within the contract
    bytes32 storagePosition = keccak256("Mangrove.MangroveOfferStorage");
    assembly {
      st.slot := storagePosition
    }
  }
}
