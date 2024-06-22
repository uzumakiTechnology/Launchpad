// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../utils/ReentrancyGuard.sol";
import "../utils/Context.sol";
import "../utils/SafeTransfer.sol";
import "../utils/math/SafeMath.sol";
import "../interfaces/ILaunchpad.sol";
import "../interfaces/ITemplate.sol";
import "../interfaces/IERC20.sol";

contract FairLaunch is ITemplate, Context, SafeTransfer, ReentrancyGuard {
    using SafeMath for uint256;

    uint256 public constant override launchpadTemplate = 1;
    bytes32 public constant LAUNCHPAD_TYPE = keccak256("OVERFLOW_FAIRLAUNCH");
    uint256 public constant DEFAULT_DELAY_TIME = 2;
    address private constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    LaunchpadInfo public launchpadInfo;
    LaunchpadStatus public launchpadStatus;
    LaunchpadVesting public launchpadVesting;

    address public incubator;

    address public launchpadToken;
    address public paymentCurrency;
    address payable public launchpadOwner;

    mapping(address => uint256) public commitments;
    mapping(address => uint256) public allocations;
    mapping(address => uint256) public alreadyClaim;
    mapping(address => SocialMetadata) public launchpadMetadata;

    event LaunchpadInitialized(
        address launchpadToken,
        address paymentCurrency,
        uint256 startTime,
        uint256 endTime,
        uint256 softcap,
        uint256 hardcap,
        uint256 price,
        uint256 totalTokenSale,
        uint256 overflow,
        uint256 individualCap
    );
    event LaunchpadSocialDataUpdated(
        address indexed launchpadAddress,
        string logoURL,
        string githubURL,
        string discordURL,
        string websiteLink,
        string descriptions
    );
    event LaunchpadVestingUpdated(
        bool isVesting,
        uint256[] vestingTime,
        uint256[] vestingPercent
    );
    event LaunchpadTimestampUpdated(uint256 startTime, uint256 endTime);
    event LaunchpadResultUpdated(LaunchpadResult result);
    event LaunchpadFinalized();
    event LaunchpadCancelled();
    event CommitAdded(address addr, uint256 commitment);
    event Claim(address addr, address token, uint256 amount);

    modifier onlyOwnerOfLaunchpad(address launchpadAddress) {
        (, address launchpadOwners, , , , ) = ITemplate(launchpadAddress)
            .getLaunchpadInfo();
        require(
            msg.sender == launchpadOwners,
            "Launchpad: Not the launchpad owner"
        );
        _;
    }

    function getLaunchpadInfo()
        external
        view
        override
        returns (
            bytes32,
            address,
            address,
            address,
            LaunchpadInfo memory,
            LaunchpadStatus memory
        )
    {
        return (
            LAUNCHPAD_TYPE,
            launchpadOwner,
            launchpadToken,
            paymentCurrency,
            launchpadInfo,
            launchpadStatus
        );
    }

    /// @notice Returns true if 7 days have passed since the end of the auction
    function finalizeTimeExpired() public view returns (bool) {
        return launchpadInfo.endTime + DEFAULT_DELAY_TIME <= block.timestamp;
    }

    function initLaunchpad(
        address _incubator,
        bytes calldata _data
    ) public override {
        (
            address _funder,
            address _token,
            address payable _launchpadOwner,
            address _paymentCurrency,
            uint256 _startTime,
            uint256 _endTime,
            uint256 _softcap,
            uint256 _hardcap,
            uint256 _price,
            uint256 _individualCap,
            uint256 _overflow
        ) = abi.decode(
                _data,
                (
                    address,
                    address,
                    address,
                    address,
                    uint256,
                    uint256,
                    uint256,
                    uint256,
                    uint256,
                    uint256,
                    uint256
                )
            );
        incubator = _incubator;
        _initLaunchpad(
            _funder,
            _token,
            _launchpadOwner,
            _paymentCurrency,
            _startTime,
            _endTime,
            _softcap,
            _hardcap,
            _price,
            _individualCap,
            _overflow
        );
    }

    /// @notice Fairlaunch finishes successfully above the reserve
    /// @dev Transfer contract funds to initialized launchpadOwner.
    function finalize() public override nonReentrant {
        require(
            launchpadOwner == _msgSender() ||
                (incubator == _msgSender() && finalizeTimeExpired()),
            "FairLaunch: not authorize"
        );

        require(!launchpadStatus.finalized, "FairLaunch: already finalized");
        require(
            launchpadInfo.endTime < block.timestamp,
            "Launchpad not end yet!"
        );

        if (launchpadStatus.totalCommitment < launchpadInfo.softcap) {
            _payoutLaunchpadToken(
                launchpadOwner,
                launchpadInfo.totalTokenSale.add(launchpadInfo.overflow)
            );
            launchpadStatus.result = LaunchpadResult.Failure;
        } else if (launchpadStatus.totalCommitment <= launchpadInfo.hardcap) {
            uint256 remainingToken = launchpadInfo.totalTokenSale.sub(
                launchpadStatus.totalCommitment.div(launchpadInfo.price).mul(
                    10 ** IERC20(launchpadToken).decimals()
                )
            );
            remainingToken = remainingToken.add(launchpadInfo.overflow);
            _payoutLaunchpadToken(launchpadOwner, remainingToken);
            uint256 fee = uint256(ILaunchpad(incubator).getServiceFee())
                .mul(launchpadStatus.totalCommitment)
                .div(10000);
            if (fee > 0)
                _payoutPayment(ILaunchpad(incubator).getBeneficiary(), fee);
            _payoutPayment(
                launchpadOwner,
                launchpadStatus.totalCommitment.sub(fee)
            );
            launchpadStatus.result = LaunchpadResult.Success;
        } else {
            uint256 fee = uint256(ILaunchpad(incubator).getServiceFee())
                .mul(launchpadInfo.hardcap)
                .div(10000);
            if (fee > 0)
                _payoutPayment(ILaunchpad(incubator).getBeneficiary(), fee);
            _payoutPayment(launchpadOwner, launchpadInfo.hardcap.sub(fee));
            launchpadStatus.result = LaunchpadResult.Overflow;
        }

        launchpadStatus.finalized = true;
        launchpadVesting.finalizeTime = block.timestamp;

        emit LaunchpadFinalized();
        emit LaunchpadResultUpdated(launchpadStatus.result);
    }

    /**
     * @notice Cancel Auction
     * @dev Admin can cancel the auction before it starts
     */
    function cancel() external nonReentrant returns (bool) {
        require(
            launchpadOwner == _msgSender() || incubator == _msgSender(),
            "FairLaunch: not authorize"
        );
        require(!launchpadStatus.finalized, "FairLaunch: already finalized");
        require(
            launchpadStatus.totalCommitment == 0,
            "FairLaunch: Funds already raised"
        );

        safeTokenTransfer(
            launchpadToken,
            launchpadOwner,
            launchpadInfo.totalTokenSale.add(launchpadInfo.overflow)
        );
        launchpadStatus.finalized = true;
        launchpadVesting.finalizeTime = block.timestamp;

        launchpadStatus.result = LaunchpadResult.Cancel;
        emit LaunchpadCancelled();
        emit LaunchpadResultUpdated(launchpadStatus.result);
        return true;
    }

    /**
     * @notice Buy Tokens by commiting approved ERC20 tokens to this contract address.
     * @param amount Amount of tokens to commit.
     */
    function commit(uint256 amount) public payable {
        require(
            launchpadInfo.startTime <= block.timestamp &&
                launchpadInfo.endTime >= block.timestamp,
            "Fairlaunch: launchpad not in live"
        );
        require(amount > 0, "FairLaunch: zero commitment");
        require(
            amount >= launchpadInfo.price,
            "FairLaunch: commit less than price"
        );
        _addCommitment(_msgSender(), amount);
    }

    function claim() external payable {
        require(launchpadStatus.finalized, "FairLaunch: not finalized");
        if (launchpadStatus.result == LaunchpadResult.Failure) {
            uint256 fundsCommitted = commitments[_msgSender()];
            require(fundsCommitted > 0, "FairLaunch: No funds committed");
            commitments[_msgSender()] = 0;
            _payoutPayment(_msgSender(), fundsCommitted);
            emit Claim(_msgSender(), paymentCurrency, fundsCommitted);
        } else if (launchpadStatus.result == LaunchpadResult.Success) {
            uint256 tokensToClaim = commitments[_msgSender()]
                .div(launchpadInfo.price)
                .mul(10 ** IERC20(launchpadToken).decimals());
            require(tokensToClaim > 0, "FairLaunch: No tokens to claim");

            _handlePayoutLaunchpadToken(
                _msgSender(),
                tokensToClaim,
                commitments[_msgSender()],
                0
            );
        } else {
            require(
                allocations[_msgSender()] == 0,
                "Fairlaunch: alrealdy claimed"
            );
            uint256 commitment = commitments[_msgSender()];
            uint256 tokensToClaim = commitment
                .mul(launchpadInfo.hardcap)
                .div(launchpadStatus.totalCommitment)
                .mul(10 ** IERC20(launchpadToken).decimals())
                .div(launchpadInfo.price);
            require(tokensToClaim > 0, "FairLaunch: No tokens to claim");
            uint256 allocation = commitment.mul(launchpadInfo.hardcap).div(
                launchpadStatus.totalCommitment
            );
            uint256 paymentRemaining = commitment.sub(allocation);

            _payoutPayment(_msgSender(), paymentRemaining);
            _handlePayoutLaunchpadToken(
                _msgSender(),
                tokensToClaim,
                allocation,
                commitments[_msgSender()]
            );

            emit Claim(_msgSender(), paymentCurrency, paymentRemaining);
        }
    }

    function claimReward() public {
        require(launchpadStatus.finalized, "FairLaunch: not finalized");
        require(
            launchpadStatus.result == LaunchpadResult.Overflow,
            "FairLaunch: not overflow"
        );
        require(
            allocations[_msgSender()] != 0,
            "FairLaunch: need to claim first"
        );

        uint256 over = commitments[_msgSender()].sub(allocations[_msgSender()]);
        uint256 reward = over.mul(launchpadInfo.overflow).div(
            launchpadStatus.totalCommitment.sub(launchpadInfo.hardcap)
        );
        _payoutLaunchpadToken(_msgSender(), reward);
        emit Claim(_msgSender(), launchpadToken, reward);
    }

    /**
     * @notice Admin can set start and end time through this function.
     * @param _startTime Auction start time.
     * @param _endTime Auction end time.
     */
    function setTimestamp(uint256 _startTime, uint256 _endTime) external {
        require(_msgSender() == launchpadOwner);
        require(
            _startTime >= block.timestamp,
            "FairLaunch: invalid start time"
        );
        require(
            _startTime + 1 days <= _endTime,
            "FairLaunch: too short duration"
        );
        require(
            _endTime - _startTime <= 30 days,
            "FairLaunch: too long duration"
        );

        require(
            launchpadInfo.startTime > block.timestamp,
            "FairLaunch: fairlaunch already started"
        );

        launchpadInfo.startTime = _startTime;
        launchpadInfo.endTime = _endTime;

        emit LaunchpadTimestampUpdated(_startTime, _endTime);
    }

    /**
     * @notice Initializes main contract variables and transfers funds for the auction.
     * @dev Init function.
     * @param _token Address of the token being sold.
     * @param _startTime Auction start time.
     * @param _endTime Auction end time.
     * @param _paymentCurrency The currency the FairLaunch accepts for payment. Can be ETH or token address.
     * @param _individualCap Minimum amount collected at which the auction will be successful.
     * @param _launchpadOwner Address where collected funds will be forwarded to.
     */
    function _initLaunchpad(
        address _funder,
        address _token,
        address payable _launchpadOwner,
        address _paymentCurrency,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _softcap,
        uint256 _hardcap,
        uint256 _price,
        uint256 _individualCap,
        uint256 _overflow
    ) internal {
        require(
            _startTime >= block.timestamp,
            "FairLaunch: invalid start time"
        );
        require(_startTime <= _endTime, "FairLaunch: too short duration");
        require(
            _endTime - _startTime <= 10 days,
            "FairLaunch: too long duration"
        );
        require(_softcap > 0, "FairLaunch: zero softcap");
        require(_softcap < _hardcap, "FairLaunch: invalid cap");
        require(_price > 0, "FairLaunch: zero price");
        require(_individualCap > 0, "FairLaunch: zero individualCap");
        require(
            _launchpadOwner != address(0),
            "FairLaunch: launchpadOwner is the zero address"
        );

        if (_paymentCurrency != ETH_ADDRESS) {
            require(
                IERC20(_paymentCurrency).decimals() > 0,
                "FairLaunch: Payment currency is not ERC20"
            );
        }

        uint256 totalTokenSale = (_hardcap / _price) *
            (10 ** IERC20(_token).decimals());

        launchpadInfo.startTime = _startTime;
        launchpadInfo.endTime = _endTime;
        launchpadInfo.softcap = _softcap;
        launchpadInfo.hardcap = _hardcap;
        launchpadInfo.price = _price;
        launchpadInfo.totalTokenSale = totalTokenSale;
        launchpadInfo.overflow = _overflow;
        launchpadInfo.individualCap = _individualCap;

        emit LaunchpadInitialized(
            _token,
            _paymentCurrency,
            _startTime,
            _endTime,
            _softcap,
            _hardcap,
            _price,
            totalTokenSale,
            _overflow,
            _individualCap
        );

        launchpadToken = _token;
        paymentCurrency = _paymentCurrency;
        launchpadOwner = _launchpadOwner;

        _safeTransferFrom(_token, _funder, totalTokenSale.add(_overflow));
    }

    /// @notice Commits to an amount during an auction
    /**
     * @notice Updates commitment for this address and total commitment of the auction.
     * @param _addr Auction participant address.
     * @param _commitment The amount to commit.
     */
    function _addCommitment(address _addr, uint256 _commitment) internal {
        uint256 newCommitment = commitments[_addr].add(_commitment);
        require(
            newCommitment <= launchpadInfo.individualCap,
            "FairLaunch: excceed individual cap"
        );
        if (paymentCurrency == ETH_ADDRESS) {
            require(msg.value >= _commitment, "FairLaunch: invalid amount");
            uint256 diff = uint256(msg.value).sub(_commitment);
            if (diff > 0) {
                _safeTransferETH(_msgSender(), diff);
            }
        } else {
            require(msg.value == 0, "FairLaunchpad: invalid value");
            _safeTransferFrom(paymentCurrency, _addr, _commitment);
        }

        commitments[_addr] = newCommitment;
        launchpadStatus.totalCommitment = launchpadStatus.totalCommitment.add(
            _commitment
        );
        emit CommitAdded(_addr, _commitment);
    }

    function _payoutPayment(address payable _to, uint256 _amount) internal {
        safeTokenTransfer(paymentCurrency, _to, _amount);
    }

    function _payoutLaunchpadToken(
        address payable _to,
        uint256 _amount
    ) internal {
        safeTokenTransfer(launchpadToken, _to, _amount);
    }

    function setLaunchpadSocialInfo(
        address launchpadAddress,
        string memory logoURL,
        string memory githubURL,
        string memory discordURL,
        string memory websiteLink,
        string memory descriptions
    ) public onlyOwnerOfLaunchpad(launchpadAddress) {
        launchpadMetadata[launchpadAddress] = SocialMetadata(
            logoURL,
            githubURL,
            discordURL,
            websiteLink,
            descriptions
        );

        emit LaunchpadSocialDataUpdated(
            launchpadAddress,
            logoURL,
            githubURL,
            discordURL,
            websiteLink,
            descriptions
        );
    }

    function setLaunchpadVesting(
        address launchpadAddress,
        uint256[] memory vestingTime,
        uint256[] memory vestingPercent,
        bool isVesting
    ) public onlyOwnerOfLaunchpad(launchpadAddress) {
        require(!launchpadStatus.finalized, "Launchpad is finalized!");

        if (!isVesting) {
            require(
                vestingPercent.length == 0 && vestingTime.length == 0,
                "Wrong TP"
            );
            launchpadVesting.isVesting = isVesting;
            launchpadVesting.vestingTime = vestingTime;
            launchpadVesting.vestingPercent = vestingPercent;
        } else {
            require(
                vestingPercent.length == vestingTime.length,
                "time-percent not match!"
            );

            uint _totalPercent = 0;
            for (uint i = 0; i < vestingPercent.length; i++) {
                _totalPercent += vestingPercent[i];
            }
            require(_totalPercent == 100, "Invalid percent");

            launchpadVesting.isVesting = isVesting;
            launchpadVesting.vestingTime = vestingTime;
            launchpadVesting.vestingPercent = vestingPercent;
        }

        emit LaunchpadVestingUpdated(isVesting, vestingTime, vestingPercent);
    }

    function _handlePayoutLaunchpadToken(
        address payable _to,
        uint256 _amount,
        uint256 _allocation,
        uint256 _commitment
    ) internal {
        if (!launchpadVesting.isVesting) {
            _payoutLaunchpadToken(_to, _amount);

            commitments[_to] = _commitment;
            allocations[_to] = _allocation;
            emit Claim(_to, launchpadToken, _amount);
        } else {
            require(alreadyClaim[_to] < _amount, "Already claim");

            uint256 i = 0;
            uint256 percent = 0;
            uint256 _value = 0;
            while (i < launchpadVesting.vestingTime.length) {
                if (block.timestamp < launchpadVesting.vestingTime[i]) break;
                _value = (
                    _amount.mul(launchpadVesting.vestingPercent[i]).div(100)
                );
                if (_value > alreadyClaim[_to]) {
                    percent = percent.add(launchpadVesting.vestingPercent[i]);
                }
                i++;
            }
            require(percent > 0, "Not able to claim");

            uint256 reward = _amount.mul(percent).div(100);
            alreadyClaim[_to] = alreadyClaim[_to].add(reward);

            if (i == launchpadVesting.vestingTime.length) {
                commitments[_to] = _commitment;
                allocations[_to] = _allocation;
            }

            _payoutLaunchpadToken(_to, reward);
            emit Claim(_to, launchpadToken, reward);
        }
    }
}
