// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.10;

import "@mgv/src/core/MgvLib.sol";
import {MgvOfferTaking} from "./MgvOfferTaking.sol";
import {TickTreeLib} from "@mgv/lib/core/TickTreeLib.sol";

abstract contract MgvOfferTakingWithPermit is MgvOfferTaking {
  // Since DOMAIN_SEPARATOR is immutable, it cannot use MgvAppendix to provide an accessor (because the value will come from code, not from storage), so we generate the accessor here.
  bytes32 public immutable DOMAIN_SEPARATOR;

  constructor(string memory contractName) {
    /* Initialize [EIP712](https://eips.ethereum.org/EIPS/eip-712) `DOMAIN_SEPARATOR`. */
    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes(contractName)),
        keccak256(bytes("1")),
        block.chainid,
        address(this)
      )
    );
  }

  /* # Delegation public functions */

  /* Adapted from [Uniswap v2 contract](https://github.com/Uniswap/uniswap-v2-core/blob/55ae25109b7918565867e5c39f1e84b7edd19b2a/contracts/UniswapV2ERC20.sol#L81) */
  function permit(
    address outbound_tkn,
    address inbound_tkn,
    address owner,
    address spender,
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    unchecked {
      require(deadline >= block.timestamp, "mgv/permit/expired");

      uint nonce = _nonces[owner]++;
      bytes32 digest = keccak256(
        abi.encodePacked(
          "\x19\x01",
          DOMAIN_SEPARATOR,
          keccak256(abi.encode(_PERMIT_TYPEHASH, outbound_tkn, inbound_tkn, owner, spender, value, nonce, deadline))
        )
      );
      address recoveredAddress = ecrecover(digest, v, r, s);
      require(recoveredAddress != address(0) && recoveredAddress == owner, "mgv/permit/invalidSignature");

      _allowance[outbound_tkn][inbound_tkn][owner][spender] = value;
      emit Approval(outbound_tkn, inbound_tkn, owner, spender, value);
    }
  }

  function approve(address outbound_tkn, address inbound_tkn, address spender, uint value) external returns (bool) {
    unchecked {
      _allowance[outbound_tkn][inbound_tkn][msg.sender][spender] = value;
      emit Approval(outbound_tkn, inbound_tkn, msg.sender, spender, value);
      return true;
    }
  }

  /* The delegate version of `marketOrder` is `marketOrderFor`, which takes a `taker` address as additional argument. Penalties incurred by failed offers will still be sent to `msg.sender`, but exchanged amounts will be transferred from and to the `taker`. If the `msg.sender`'s allowance for the given `outbound_tkn`,`inbound_tkn` and `taker` are strictly less than the total amount eventually spent by `taker`, the call will fail. */

  /* *Note:* `marketOrderFor` and `cleanByImpersonation` may emit ERC20 `Transfer` events of value 0 from `taker`, but that's already the case with common ERC20 implementations. */
  function marketOrderForByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants, address taker)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid)
  {
    unchecked {
      require(uint160(takerWants) == takerWants, "mgv/mOrder/takerWants/160bits");
      require(uint160(takerGives) == takerGives, "mgv/mOrder/takerGives/160bits");
      uint fillVolume = fillWants ? takerWants : takerGives;
      Tick tick = TickLib.tickFromVolumes(takerGives, takerWants);
      return marketOrderForByTick(olKey, tick, fillVolume, fillWants, taker);
    }
  }

  function marketOrderForByTick(OLKey memory olKey, Tick maxTick, uint fillVolume, bool fillWants, address taker)
    public
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid)
  {
    unchecked {
      (takerGot, takerGave, bounty, feePaid) = generalMarketOrder(olKey, maxTick, fillVolume, fillWants, taker, 0);
      /* The sender's allowance is verified after the order complete so that `takerGave` rather than `takerGives` is checked against the allowance. The former may be lower. */
      deductSenderAllowance(olKey.outbound_tkn, olKey.inbound_tkn, taker, takerGave);
    }
  }

  /* # Misc. low-level functions */

  /* Used by `*For` functions, it both checks that `msg.sender` was allowed to use the taker's funds, and decreases the former's allowance. */
  function deductSenderAllowance(address outbound_tkn, address inbound_tkn, address owner, uint amount) internal {
    unchecked {
      mapping(address => uint) storage curriedAllow = _allowance[outbound_tkn][inbound_tkn][owner];
      uint allowed = curriedAllow[msg.sender];
      require(allowed >= amount, "mgv/lowAllowance");
      curriedAllow[msg.sender] = allowed - amount;

      emit Approval(outbound_tkn, inbound_tkn, owner, msg.sender, allowed - amount);
    }
  }
}
