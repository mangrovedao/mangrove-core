// SPDX-License-Identifier: BSL 1.1 - Copyright 2024 MetaLayer Labs Ltd.
pragma solidity ^0.8.15;

import {Predeploys} from "./Predeploys.sol";
import {Ownable} from "./Ownable.sol";

contract BlastPoints is Ownable {
  event PointsOperator(address contractAddress, address operator);

  mapping(address => address) public operatorMap;
  mapping(address => bool) public banMap;

  constructor() Ownable() {
    banMap[Predeploys.L2_CROSS_DOMAIN_MESSENGER] = true;
  }

  function isOperator(address contractAddress) public view returns (bool) {
    return msg.sender == operatorMap[contractAddress];
  }

  function operatorNotSet(address contractAddress) internal view returns (bool) {
    return operatorMap[contractAddress] == address(0);
  }

  function isAuthorized(address contractAddress) public view returns (bool) {
    if (banMap[contractAddress]) {
      return false;
    }
    return isOperator(contractAddress) || (operatorNotSet(contractAddress) && msg.sender == contractAddress);
  }

  function configurePointsOperator(address operator) external {
    require(isAuthorized(msg.sender), "not authorized to configure points operator");
    setOperator(msg.sender, operator);
  }

  function configurePointsOperatorOnBehalf(address contractAddress, address newOperator) external {
    require(isAuthorized(msg.sender), "not authorized to configure points operator");
    setOperator(contractAddress, newOperator);
  }

  function readStatus(address contractAddress) external view returns (address operator, bool isBanned, uint codeLength) {
    return (operatorMap[contractAddress], banMap[contractAddress], contractAddress.code.length);
  }

  function adminConfigureBan(address contractAddress, bool banStatus) external onlyOwner {
    banMap[contractAddress] = banStatus;
    setOperator(contractAddress, address(0xdead));
  }

  function adminConfigureOperator(address contractAddress, address operator) external onlyOwner {
    setOperator(contractAddress, operator);
  }

  function setOperator(address contractAddress, address operator) internal {
    operatorMap[contractAddress] = operator;
    emit PointsOperator(contractAddress, operator);
  }
}
