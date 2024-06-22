// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ILaunchpad {
  // enum LaunchpadResult {
  //   Cancel,
  //   Failure,
  //   Success,
  //   Overflow
  // }

  // struct LaunchpadInfo {
  //   uint256 startTime;
  //   uint256 endTime;
  //   uint256 softcap;
  //   uint256 hardcap;
  //   uint256 price;
  //   uint256 individualCap;
  //   uint256 totalTokenSale;
  //   uint256 overflowFarm;
  // }

  // struct LaunchpadStatus {
  //   uint256 totalCommitment;
  //   bool finalized;
  //   LaunchpadResult result;
  // }

  function getEntryFee() external view returns(uint256);
  function getServiceFee() external view returns(uint16);
  function getBeneficiary() external view returns(address payable);
  function getAllLaunchpad() external view returns(address[] memory);
  // function getLaunchpadInfo() external view returns (
  //   bytes32,
  //   address,
  //   address,
  //   address,
  //   LaunchpadInfo memory,
  //   LaunchpadStatus memory
  // );
}