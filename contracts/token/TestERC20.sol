// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
  constructor(uint256 _genesisMint) ERC20("Test", "TEST") {
    _mint(msg.sender, _genesisMint);
  }
}