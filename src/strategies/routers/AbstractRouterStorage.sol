// SPDX-License-Identifier:	BSD-2-Clause

//AbstractRouterStorage.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

pragma abicoder v2;


/// @title This is the storage part of a diamond storage scheme for `AbstractRouter` to reduce size of contracts.
library AbstractRouterStorage {
  /// @notice The layout of the storage.
  /// @param makers maker contract addresses allowed to call this router.
  /// @param gasOverhead the gas overhead of this router.
  struct Layout {
    mapping(address => bool) makers;
    uint gasOverhead;
  }

  /// @notice Gets the `AbstractRouter` storage from a fixed slot.
  function getStorage() internal pure returns (Layout storage st) {
    // Unique slot within the contract
    bytes32 storagePosition = keccak256("Mangrove.AbstractRouterStorage");
    assembly {
      st.slot := storagePosition
    }
  }
}
