// SPDX-License-Identifier:	BSD-2-Clause

// IOfferLogicMulti.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity >=0.7.0;
pragma abicoder v2;

import "./IOfferLogic.sol";

interface IOfferLogicMulti is IOfferLogic {
  /** Multi offer specific Events */
  // Offer management
  event NewOwnedOffer(
    IMangrove mangrove,
    IEIP20 indexed outbound_tkn,
    IEIP20 indexed inbound_tkn,
    uint indexed offerId,
    address owner
  );

  // user provision on Mangrove has increased
  event CreditMgvUser(
    IMangrove indexed mangrove,
    address indexed user,
    uint amount
  );

  // user provision on Mangrove has decreased
  event DebitMgvUser(
    IMangrove indexed mangrove,
    address indexed user,
    uint amount
  );

  // user token balance on contract has increased
  event CreditUserTokenBalance(
    address indexed user,
    IEIP20 indexed token,
    uint amount
  );

  // user token balance on contract has decreased
  event DebitUserTokenBalance(
    address indexed user,
    IEIP20 indexed token,
    uint amount
  );

  function tokenBalance(IEIP20 token, address owner)
    external
    view
    returns (uint);

  function balanceOnMangrove(address owner) external view returns (uint);

  function offerOwners(
    IEIP20 outbound_tkn,
    IEIP20 inbound_tkn,
    uint[] calldata offerIds
  ) external view returns (address[] memory __offerOwners);

  function ownerOf(
    IEIP20 outbound_tkn,
    IEIP20 inbound_tkn,
    uint offerId
  ) external view returns (address owner);

  function depositToken(IEIP20 token, uint amount)
    external
    returns (
      //override
      bool success
    );

  function fundMangrove() external payable;
}
