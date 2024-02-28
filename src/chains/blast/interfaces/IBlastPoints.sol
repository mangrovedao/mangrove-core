// SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

/// @title IBlastPoints
/// @notice Interface to configure Blast Points
/// @dev Copied from the following sources on 2024-02-27:
///   - https://blastpublic.notion.site/PUBLIC-Blast-Mainnet-Points-API-f8abea9d6e67417890d4a300ecbe5827
///   - https://testnet.blastscan.io/address/0x2fc95838c71e76ec69ff817983BFf17c710F34E0/contract/168587773/code
interface IBlastPoints {
  /// @notice Set the Blast Points operator for the calling contract.
  /// @param operator The address of the Blast Points operator.
  /// @dev Note that the operator address should be an EOA whose private key is accessible
  ///   to an internet connected server. We recommended setting this value to a distinct
  ///   address so that other admin responsibilities are not co-mingled with this address,
  ///   whose key must live on a hot server.
  function configurePointsOperator(address operator) external;

  function isOperator(address contractAddress) external view returns (bool);

  function isAuthorized(address contractAddress) external view returns (bool);

  function configurePointsOperatorOnBehalf(address contractAddress, address newOperator) external;

  function readStatus(address contractAddress) external view returns (address operator, bool isBanned, uint codeLength);
}
