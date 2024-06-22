// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./access/AccessManager.sol";
import "./utils/math/SafeMath.sol";
import "./utils/SafeTransfer.sol";
import "./utils/Pausable.sol";
import "./interfaces/ILaunchpad.sol";
import "./interfaces/ITemplate.sol";
import "./interfaces/IERC20.sol";
import "./template/FairLaunch.sol";
import "./template/WhitelistLaunch.sol";

contract Launchpad is ILaunchpad, Pausable, SafeTransfer {
    using SafeMath for uint256;

    struct LaunchpadStruct {
        bool exists;
        uint256 templateId;
        uint256 index;
    }

    struct LaunchpadFee {
        uint256 entryFee;
        uint16 serviceFee;
        address payable beneficiary;
    }

    // bytes32 public constant MARKET_MINTER_ROLE = keccak256("MARKET_MINTER_ROLE");
    uint16 public constant INVERSE_BASIC_POINT = 10000;
    address private constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    AccessManager public accessManager;
    LaunchpadFee public launchpadFee;

    address[] public launchpads;
    uint256 public currentTemplateId;
    bool public locked;

    mapping(uint256 => address) private templates;
    mapping(address => LaunchpadStruct) public launchpadInfo;


    event LaunchpadTemplateAdded(address templateAddress, uint256 templateId);
    event LaunchpadTemplateRemoved(address auction, uint256 templateId);
    event LaunchpadCreated(
        address indexed owner,
        address indexed addr,
        address launchpadTemplate
    );

    event LaunchpadSocialDataUpdated(
        address indexed launchpadAddress,
        string logoURL,
        string githubURL,
        string discordURL,
        string websiteLink
    );

    modifier onlyAdmin() {
        require(
            accessManager.hasAdminRole(_msgSender()),
            "Launchpad: only admin"
        );
        _;
    }
    

    modifier checkLock() {
        if (locked) {
            require(
                accessManager.hasOperatorRole(_msgSender()),
                "Launchpad: only operator"
            );
        }
        _;
    }



    constructor(address _accessManager, address[] memory _templates) {
        require(
            _accessManager != address(0),
            "Launchpad: zero address accessManager"
        );
        accessManager = AccessManager(_accessManager);

        // currentTemplateId = 1;
        for (uint i = 0; i < _templates.length; i++) {
            _addLaunchpadTemplate(_templates[i]);
        }
        locked = true;
    }

    function getTemplateAddress(
        uint256 _templateId
    ) external view returns (address) {
        return templates[_templateId];
    }

    function numberOfLaunchpad() external view returns (uint) {
        return launchpads.length;
    }

    function getEntryFee() external view override returns (uint256) {
        return launchpadFee.entryFee;
    }

    function getServiceFee() external view override returns (uint16) {
        return launchpadFee.serviceFee;
    }

    function getBeneficiary() external view override returns (address payable) {
        return launchpadFee.beneficiary;
    }

    function getAllLaunchpad()
        external
        view
        override
        returns (address[] memory)
    {
        return launchpads;
    }

    function getLaunchpadInfo(
        address launchpadAddress
    )
        external
        view
        returns (
            bytes32 launchpadType,
            address owner,
            address token,
            address payment,
            ITemplate.LaunchpadInfo memory info,
            ITemplate.LaunchpadStatus memory status
        )
    {
        (launchpadType, owner, token, payment, info, status) = ITemplate(
            launchpadAddress
        ).getLaunchpadInfo();
    }

    function setEntryFee(uint256 _entryFee) external onlyAdmin {
        launchpadFee.entryFee = _entryFee;
    }

    function setServiceFee(uint16 _serviceFee) external onlyAdmin {
        require(_serviceFee <= 1000, "Launchpad: > 10%");
        launchpadFee.serviceFee = _serviceFee;
    }

    function setBeneficiary(address payable _beneficiary) external onlyAdmin {
        require(
            _beneficiary != address(0),
            "Launchpad: zero address beneficiary"
        );
        launchpadFee.beneficiary = _beneficiary;
    }

    function setLocked(bool _locked) external onlyAdmin {
        locked = _locked;
    }

    function pauseLaunchpad() external onlyAdmin {
        _pause();
    }

    function unpauseLaunchpad() external onlyAdmin {
        _unpause();
    }

    function addTemplate(address _templateAddress) external onlyAdmin {
        _addLaunchpadTemplate(_templateAddress);
    }

    function removeTemplate(uint256 _templateId) external onlyAdmin {
        address template = templates[_templateId];
        require(template != address(0), "Launchpad: zero address template");
        templates[_templateId] = address(0);
        emit LaunchpadTemplateRemoved(template, _templateId);
    }

    function replaceTemplate(
        uint256 templateId,
        address templateAddress
    ) external onlyAdmin whenPaused {
        require(
            templates[templateId] != address(0),
            "Launchpad: template not exists"
        );
        require(
            templateId == ITemplate(templateAddress).launchpadTemplate(),
            "Launchpad: invalid templateId"
        );
        templates[templateId] = templateAddress;
    }

    function finalizeExpiredLaunchpad(
        address _launchAddress
    ) external onlyAdmin {
        ITemplate(_launchAddress).finalize();
    }

    function createLaunchpad(
        uint256 _templateId,
        address _token,
        uint256 _totalToken,
        bytes calldata _data
    ) external payable checkLock whenNotPaused returns (address) {
        require(
            _templateId <= currentTemplateId,
            "Launchpad: invalid templateId"
        );
        require(_totalToken > 0, "Launchpad: zero launch token");
        if (launchpadFee.entryFee > 0) {
            require(
                msg.value >= launchpadFee.entryFee,
                "Launchpad: inssufficient fund"
            );
            launchpadFee.beneficiary.transfer(msg.value);
        }

        address newLaunchpad = _deployTemplate(_templateId);
        _safeTransferFrom(_token, _msgSender(), _totalToken);
        IERC20(_token).approve(newLaunchpad, _totalToken);
        ITemplate(newLaunchpad).initLaunchpad(address(this), _data);

        uint256 remainingToken = IERC20(_token).balanceOf(address(this));
        if (remainingToken > 0) {
            _safeTransfer(_token, _msgSender(), remainingToken);
        }

        return newLaunchpad;
    }

    function deleteTemplate(
        address template
    ) public onlyAdmin() {
        bytes memory payload = abi.encodeWithSignature("cancel()");
        (bool _success, ) = template.call{value: 0}(payload);
        require(_success, "Failed to cancel launchpad");
    }

    function _addLaunchpadTemplate(address _templateAddress) internal {
        require(
            _templateAddress != address(0),
            "Launchpad: Incorrect template"
        );
        uint256 templateId = ITemplate(_templateAddress).launchpadTemplate();
        ++currentTemplateId;
        require(
            templateId == currentTemplateId,
            "Launchpad: Incorrect templateId "
        );
        templates[templateId] = _templateAddress;
        emit LaunchpadTemplateAdded(_templateAddress, templateId);
    }

    function _deployTemplate(
        uint256 _templateId
    ) internal returns (address newLaunchpad) {
        address template = templates[_templateId];
        require(template != address(0), "Launchpad: template doesn't exist");
        if (_templateId == 1) {
            bytes memory deploymentData = abi.encodePacked(
                type(FairLaunch).creationCode,
                uint256(uint160(template))
            );
            // solhint-disable-next-line no-inline-assembly
            assembly {
                newLaunchpad := create(
                    0,
                    add(deploymentData, 32),
                    mload(deploymentData)
                )
            }
        } else {
            bytes memory deploymentData = abi.encodePacked(
                type(WhitelistLaunch).creationCode,
                uint256(uint160(template))
            );
            // solhint-disable-next-line no-inline-assembly
            assembly {
                newLaunchpad := create(
                    0,
                    add(deploymentData, 32),
                    mload(deploymentData)
                )
            }
        }
        launchpadInfo[newLaunchpad] = LaunchpadStruct(
            true,
            _templateId,
            launchpads.length
        );
        launchpads.push(newLaunchpad);
        emit LaunchpadCreated(_msgSender(), newLaunchpad, template);
    }


}
