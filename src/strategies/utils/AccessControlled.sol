// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

/// @title This contract is used to restrict access to privileged functions of inheriting contracts through modifiers.
/// @notice The contract stores an admin address which is checked against `msg.sender` in the `onlyAdmin` modifier.
/// @notice Additionally, a specific `msg.sender` can be verified with the `onlyCaller` modifier.
contract AccessControlled {
  /**
   * @notice logs new `admin` of `this`
   * @param admin The new admin.
   */
  event SetAdmin(address admin);
  /**
   * @notice The admin address.
   */

  address internal _admin;

  /**
   * @notice `AccessControlled`'s constructor
   * @param admin_ The address of the admin that can access privileged functions and also allowed to change the admin. Cannot be `address(0)`.
   */
  constructor(address admin_) {
    require(admin_ != address(0), "AccessControlled/0xAdmin");
    _admin = admin_;
  }

  /**
   * @notice This modifier verifies that `msg.sender` is the admin.
   */
  modifier onlyAdmin() {
    require(msg.sender == _admin, "AccessControlled/Invalid");
    _;
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
   * @notice This modifier verifies that `msg.sender` is either caller or the admin
   * @param caller The address of a caller that can access the modified function.
   */
  modifier adminOrCaller(address caller) {
    // test _admin second to save a storage read when possible
    require(msg.sender == caller || msg.sender == _admin, "AccessControlled/Invalid");
    _;
  }

  /**
   * @notice Retrieves the current admin.
   * @return current admin.
   */
  function admin() public view returns (address current) {
    return _admin;
  }

  /**
   * @notice This sets the admin. Only the current admin can change the admin.
   * @param admin_ The new admin. Cannot be `address(0)`.
   */
  function setAdmin(address admin_) public onlyAdmin {
    require(admin_ != address(0), "AccessControlled/0xAdmin");
    _admin = admin_;
    emit SetAdmin(admin_);
  }
}
