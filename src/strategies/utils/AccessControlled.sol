// SPDX-License-Identifier:	BSD-2-Clause

// AccessControlled.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {AccessControlledStorage as ACS} from "./AccessControlledStorage.sol";

/// @title This contract is used to restrict access to privileged functions of inheriting contracts through modifiers.
/// @notice The contract stores an admin address which is checked against `msg.sender` in the `onlyAdmin` modifier.
/// @notice Additionally, a specific `msg.sender` can be verified with the `onlyCaller` modifier.
contract AccessControlled {
  /// @notice logs new `admin` of `this`
  event SetAdmin(address admin);

  /**
   * @notice `AccessControlled`'s constructor
   * @param admin_ The address of the admin that can access privileged functions and also allowed to change the admin. Cannot be `address(0)`.
   */
  constructor(address admin_) {
    require(admin_ != address(0), "AccessControlled/0xAdmin");
    ACS.getStorage().admin = admin_;
  }

  /**
   * @notice This modifier verifies that `msg.sender` is the caller.
   * @param caller The address of the caller that can access the modified function.
   */
  modifier onlyCaller(address caller) {
    require(msg.sender == caller, "AccessControlled/Invalid");
    _;
  }

  /**
   * @notice Retrieves the current admin.
   */
  function admin() public view returns (address) {
    return ACS.getStorage().admin;
  }

  /**
   * @notice This modifier verifies that `msg.sender` is the admin.
   */
  modifier onlyAdmin() {
    require(msg.sender == admin(), "AccessControlled/Invalid");
    _;
  }

  /**
   * @notice This sets the admin. Only the current admin can change the admin.
   * @param admin_ The new admin. Cannot be `address(0)`.
   */
  function setAdmin(address admin_) public onlyAdmin {
    require(admin_ != address(0), "AccessControlled/0xAdmin");
    ACS.getStorage().admin = admin_;
    emit SetAdmin(admin_);
  }
}
