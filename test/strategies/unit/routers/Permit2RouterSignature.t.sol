// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {Permit2Router} from "mgv_src/strategies/routers/Permit2Router.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {PermitSignature} from "lib/permit2/test/utils/PermitSignature.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";

contract Permit2RouterSignatureTest is MangroveTest, DeployPermit2, PermitSignature {
  address owner;
  uint ownerPrivateKey;
  TestToken weth;
  TestToken usdc;
  uint NONCE = 0;

  bytes32 DOMAIN_SEPARATOR;
  uint48 EXPIRATION;
  uint AMOUNT = 25;

  Permit2Router router;
  IPermit2 permit2;

  function setUp() public virtual override {
    super.setUp();
    ownerPrivateKey = 0x12341234;
    owner = vm.addr(ownerPrivateKey);

    weth = new TestToken(owner, "WETH", "WETH", 18);
    usdc = new TestToken(owner, "USDC", "USDC", 18);
    permit2 = IPermit2(deployPermit2());
    DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

    router = new Permit2Router(permit2);

    EXPIRATION = uint48(block.timestamp + 1000);

    router.bind(address(this));

    deal($(weth), owner, cash(weth, 50));

    vm.startPrank(owner);
    weth.approve(address(permit2), type(uint).max);
    usdc.approve(address(permit2), type(uint).max);
    permit2.approve(address(weth), address(router), type(uint160).max, type(uint48).max);
    permit2.approve(address(usdc), address(router), type(uint160).max, type(uint48).max);
    vm.stopPrank();
  }

  function getPermitTransferSignatureWithSpecifiedAddress(
    ISignatureTransfer.PermitTransferFrom memory permit,
    uint privateKey,
    bytes32 domainSeparator,
    address addr
  ) internal pure returns (bytes memory sig) {
    bytes32 tokenPermissions = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
    bytes32 msgHash = keccak256(
      abi.encodePacked(
        "\x19\x01",
        domainSeparator,
        keccak256(abi.encode(_PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissions, addr, permit.nonce, permit.deadline))
      )
    );

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
    return bytes.concat(r, s, bytes1(v));
  }

  function test_pull_with_permit() public {
    ISignatureTransfer.PermitTransferFrom memory permit = defaultERC20PermitTransfer(address(weth), NONCE);
    bytes memory sig =
      getPermitTransferSignatureWithSpecifiedAddress(permit, ownerPrivateKey, DOMAIN_SEPARATOR, address(router));

    uint startBalanceFrom = weth.balanceOf(owner);
    uint startBalanceTo = weth.balanceOf(address(this));

    router.pull(weth, owner, AMOUNT, true, permit, sig);

    assertEq(weth.balanceOf(owner), startBalanceFrom - AMOUNT);
    assertEq(weth.balanceOf(address(this)), startBalanceTo + AMOUNT);
  }
}
