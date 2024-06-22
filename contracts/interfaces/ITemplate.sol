// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITemplate {
    enum LaunchpadResult {
        Cancel,
        Failure,
        Success,
        Overflow
    }

    struct LaunchpadInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 softcap;
        uint256 hardcap;
        uint256 price;
        uint256 individualCap;
        uint256 totalTokenSale;
        uint256 overflow;
    }

    struct LaunchpadStatus {
        uint256 totalCommitment;
        bool finalized;
        LaunchpadResult result;
    }

    struct SocialMetadata {
        string logoURL;
        string githubURL;
        string discordURL;
        string websiteLink;
        string descriptions;
    }

    struct LaunchpadVesting {
        bool isVesting;
        uint256[] vestingTime;
        uint256[] vestingPercent;
        uint256 finalizeTime;
    }

    function initLaunchpad(address incubator, bytes calldata data) external;

    function finalize() external;

    function launchpadTemplate() external view returns (uint256);

    function getLaunchpadInfo()
        external
        view
        returns (
            bytes32,
            address,
            address,
            address,
            LaunchpadInfo memory,
            LaunchpadStatus memory
        );

    function cancel() external returns (bool);
}
