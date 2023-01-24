// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.9;

import {ERC20Base, ERC20} from "mgv_src/toy/ERC20.sol";
import {UsualTokenInterface} from "mgv_src/usual/UsualTokenInterface.sol";
import {PLUsTakerProxy} from "mgv_src/usual/PLUsTakerProxy.sol";

/// @title This contract is a Meta token for the PLUsDAO Token.
/// @notice This contract will have a restricted transfer method, so that only specific address can transfer the PLUsDAO Token.
contract MetaPLUsDAOToken is ERC20 {
  /// @notice used to check balance, totalSupply, unlocking and transering.
  UsualTokenInterface public immutable _pLUsDAOToken;

  /// @notice used to check the recipient address and get the current taker.
  PLUsTakerProxy public _pLUsTakerProxy;

  /// @notice used to check for the mangrove address.
  address public immutable _mangrove;

  /// @notice used to check for the PLUsMgvStrat address and for transfering.
  address public _pLUsMgvStrat;

  /// @notice used controll the admin of the contract.
  address public _admin;

  /// @notice MetaPLUsDAOToken contructor.
  /// @param admin The admin address for the contract.
  /// @param _name The name for the Token.
  /// @param _symbol The symbol for the Token.
  /// @param pLUsDAOToken The PLUsDAO Token contract used.
  /// @param mangrove The mangrove address used for the transfers.
  constructor(
    address admin,
    string memory _name,
    string memory _symbol,
    UsualTokenInterface pLUsDAOToken,
    address mangrove
  ) ERC20Base(_name, _symbol) ERC20(_name) {
    _pLUsDAOToken = pLUsDAOToken;
    _mangrove = mangrove;
    _admin = admin;
  }

  /// @notice This modifer verifies that the `msg.sender` is the admin of the contract.
  modifier onlyAdmin() {
    require(msg.sender == _admin, "MetaPLUsDAOToken/adminOnly");
    _;
  }

  /// @notice This sets the PLUsTakerProxy contract used by this contract.
  /// @notice This can only be called by the admin of the contract.
  /// @param pLUsTakerProxy The PLUsTakerProxy contract the be set.
  function setPLUsTakerProxy(PLUsTakerProxy pLUsTakerProxy) external onlyAdmin {
    _pLUsTakerProxy = pLUsTakerProxy;
  }

  /// @notice This sets the address of the PLUsMgvStrat contract used by this contract.
  /// @notice This can only be called by the admin of the contract.
  /// @param pLUsMgvStrat The address PLUsMgvStrat contract to be set.
  function setPLUsMgvStrat(address pLUsMgvStrat) external onlyAdmin {
    _pLUsMgvStrat = pLUsMgvStrat;
  }

  /// @notice This gets the total supply of the underlying token PLUsDAO
  function totalSupply() public view virtual override returns (uint) {
    return _pLUsDAOToken.totalSupply();
  }

  /// @notice This gets the balance of a current address for the underlying token PLUsDAO
  /// @param account The address to get the balance for
  function balanceOf(address account) public view virtual override returns (uint) {
    return _pLUsDAOToken.balanceOf(account);
  }

  /// @notice This checks wether the given `owner` and `recipient` are allowed. And if the `msg.sender` is mangrove
  /// @notice The owner has to be the PLUsMgvStrat with recipient being Mangrove
  /// * or owner being Mangrove and the recipient being the PLUsTakerProxy
  /// @notice When mangrove is the owner, then the underlying token PLUsDAO will be transfered to the taker. And the the PLUsDAO tokens will be unlocked for the taker.
  /// @param owner The owner of the token
  /// @param recipient The recipient of the token
  /// @param amount The amount the be transfered.
  /// @dev Only allow the following transfers:
  /// * PLUsMgvStrat -> Mangrove
  /// * Mangrove     -> any address
  /// * When owner = Mangrove  =>  transfer & unlock
  function _transfer(address owner, address recipient, uint amount) internal override {
    require(
      (
        (owner == address(_pLUsMgvStrat) && recipient == _mangrove)
          || owner == _mangrove && recipient == address(_pLUsTakerProxy)
      ) && msg.sender == _mangrove,
      "MetaPLUsDAOToken/nonMangroveTransfer"
    );

    if (owner == _mangrove) {
      address currentTaker = _pLUsTakerProxy.currentTaker();
      bool result = _pLUsDAOToken.transferFrom(_pLUsMgvStrat, currentTaker, amount);
      require(result, "MetaPLUsDAOToken/transferFailed");
      result = _pLUsDAOToken.unlockFor(currentTaker, amount);
      require(result, "MetaPLUsDAOToken/PLUsDAOUnlockFailed");
    }
  }
}
