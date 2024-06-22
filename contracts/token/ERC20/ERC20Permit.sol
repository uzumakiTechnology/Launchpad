// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "../../utils/math/SafeMath.sol";
import "../../utils/EIP712.sol";

abstract contract ERC20Permit is ERC20, EIP712 {
  using SafeMath for uint256;

  mapping(address => uint256) public nonces;

  bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  constructor(string memory _name, string memory _symbol, string memory _version) ERC20(_name, _symbol) {
    uint256 chainId;
    assembly {
      chainId := chainid()
    }

    DOMAIN_SEPARATOR = hash(EIP712Domain({
      name: _name,
      version: _version,
      chainId: chainId,
      verifyingContract: address(this)
    }));
  }

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    require(expiry >= block.timestamp, "NST: expiry");
    bytes32 digest = keccak256(
      abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, expiry))
      )
    );
    address recoveredAddress = ecrecover(digest, v, r, s);
    require(recoveredAddress != address(0) && recoveredAddress == owner, "NST: invalid signature");
    _approve(owner, spender, value);
  }
}