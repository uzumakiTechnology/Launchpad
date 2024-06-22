// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";
import "../utils/SafeTransfer.sol";
import "../utils/access/Ownable.sol";
import "../utils/Pausable.sol";
import "../utils/ReentrancyGuard.sol";
import "../utils/math/SafeMath.sol";
import "../utils/cryptography/MerkleProof.sol";

contract MultiSale is SafeTransfer, Ownable, Pausable, ReentrancyGuard {
  using SafeMath for uint256;

  struct SaleInfo {
    uint256 startTime;
    uint256 endTime;
    uint256 softcap;
    uint256 hardcap;
    uint256 price;
    uint256 individualCap;
    uint256 totalTokenSale;
    uint256 claimPeriod;
  }

  struct SaleStatus {
    uint256 totalCommitment;
    bool finalized;
  }

  address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  bytes32 public saleData;
  
  SaleInfo public saleInfo;
  SaleStatus public saleStatus;

  address public saleToken;
  address public paymentToken;
  address payable public beneficiary;

  mapping(address => uint256) public commitments;
  mapping(address => uint256) public allocations;
  mapping(address => bool) public claimable;
  mapping(address => bool) public refundsUser;


  event InitializedSale(
    address saleToken,
    address paymentToken,
    uint256 startTime,
    uint256 endTime,
    uint256 claimPeriod,
    uint256 softcap,
    uint256 hardcap,
    uint256 price,
    uint256 totalTokenSale,
    uint256 individualCap
  );
  event FinalizedSale(bytes32 saleData);
  event CancelledSale(uint256 timestamp);
  event Commit(address addr, uint256 amount);
  event Claim(address addr, uint256 tokenBuy, uint256 refund);
  event WithdrawToken(address owner, address token, uint256 amount);

  constructor() {}

  function getSaleInfo() external view returns(
    address,
    address,
    address,
    SaleInfo memory,
    SaleStatus memory
  ) {
    return (
      beneficiary,
      saleToken,
      paymentToken,
      saleInfo,
      saleStatus
    );
  }

  function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}

  function initSale(
    address _funder,
    address payable _beneficiary,
    address _saleToken,
    address _paymentToken,
    uint256 _startTime,
    uint256 _endTime,
    uint256 _claimPeriod,
    uint256 _softcap,
    uint256 _hardcap,
    uint256 _price,
    uint256 _totalTokenSale,
    uint256 _individualCap
  ) external onlyOwner {
    _initSale(
      _saleToken,
      _paymentToken,
      _startTime,
      _endTime,
      _claimPeriod,
      _softcap,
      _hardcap,
      _price,
      _totalTokenSale,
      _individualCap,
      _funder,
      _beneficiary
    );
  }

  function commit(uint256 amount) public payable whenNotPaused {
    require(
      saleInfo.startTime <= block.timestamp &&
      saleInfo.endTime >= block.timestamp,
      "Sale not in live"
    );
    require(amount > 0, "Zero commitment");
    require(
        amount >= saleInfo.price,
        "Commit less than price"
    );
    require(!saleStatus.finalized, "Sale ended");
    _addCommitment(_msgSender(), amount);
  }

  function claim(
        uint256 amount,
        bytes32[] memory proof
    ) external payable whenNotPaused {
        require(saleStatus.finalized, "Sale not finalized");
        require(_checkClaim(_msgSender(), amount, proof), "Not Claimable");
        require(!claimable[_msgSender()], "Already claimed");
        uint256 commitment = commitments[_msgSender()];
        uint256 tokenToClaim = saleToken != address(0)
            ? amount.mul(10 ** IERC20(saleToken).decimals()).div(saleInfo.price)
            : 0;
        if (amount < commitment && !refundsUser[_msgSender()]) {
            _payoutPayment(_msgSender(), commitment.sub(amount));
        }

        _handlePayoutLaunchpadToken(
            _msgSender(),
            tokenToClaim,
            amount,
            amount < commitment ? commitment.sub(amount) : 0
        );

        if (commitment > 0 && !refundsUser[_msgSender()]) {
            if (amount > commitment) {
                _payoutPayment(beneficiary, commitment);
            } else {
                _payoutPayment(beneficiary, amount);
            }
        }

        if (!refundsUser[_msgSender()]) {
            refundsUser[_msgSender()] = true;
        }
    }
    emit Claim(_msgSender(), tokenToClaim, amount < commitment ? commitment.sub(amount) : 0);
  }

  function finalize(bytes32 _saleData) external onlyOwner {
    require(saleInfo.endTime <= block.timestamp, "Sale not ended yet");
    saleData = _saleData;
    saleStatus.finalized = true;
    emit FinalizedSale(_saleData);
  }

  function cancel() external onlyOwner {
    require(saleInfo.startTime <= block.timestamp, "Sale already started");
    saleStatus.finalized = true;
    safeTokenTransfer(saleToken, _msgSender(), saleInfo.totalTokenSale);
    emit CancelledSale(block.timestamp);
  }

  function updateSaleData(bytes32 _saleData) public onlyOwner whenPaused {
    require(saleStatus.finalized, "Sale not end");
    saleData = _saleData;
  }

  function withdrawSaleToken() external onlyOwner {
    require(saleStatus.finalized, "Sale not ended yet");
    require(saleInfo.endTime + saleInfo.claimPeriod <= block.timestamp, "Time not expired");
    safeTokenTransfer(saleToken, _msgSender(), IERC20(saleToken).balanceOf(address(this)));
  }

  function withdrawToken(address token, uint256 amount) public onlyOwner whenPaused {
		safeTokenTransfer(token, payable(_msgSender()), amount);
		emit WithdrawToken(_msgSender(), token, amount);
	}

  function _initSale(
    address _saleToken,
    address _paymentToken,
    uint256 _startTime,
    uint256 _endTime,
    uint256 _claimPeriod,
    uint256 _softcap,
    uint256 _hardcap,
    uint256 _price,
    uint256 _totalTokenSale,
    uint256 _individualCap,
    address _funder,
    address payable _beneficiary
  ) private {
    require(
      _startTime >= block.timestamp,
      "Invalid start time"
    );
    require(_startTime <= _endTime, "Invalid timestamp");
    require(_softcap > 0, "Zero softcap");
    require(_softcap < _hardcap, "Invalid cap");
    require(_price > 0, "Zero price");
    require(_individualCap > 0, "Zero individualCap");
    if (_paymentToken != ETH_ADDRESS) {
      require(
        IERC20(_paymentToken).decimals() > 0,
        "Payment token is not ERC20"
      );
    }

    uint256 totalTokenSale =_saleToken != address(0) ? (_hardcap / _price) *
            (10 ** IERC20(_saleToken).decimals()) : _totalTokenSale;

    saleToken = _saleToken;
    paymentToken = _paymentToken;
    beneficiary = _beneficiary;

    saleInfo.startTime = _startTime;
    saleInfo.endTime = _endTime;
    saleInfo.claimPeriod = _claimPeriod;
    saleInfo.softcap = _softcap;
    saleInfo.hardcap = _hardcap;
    saleInfo.price = _price;
    saleInfo.individualCap = _individualCap;
    saleInfo.totalTokenSale = totalTokenSale;

    if (_saleToken != address(0)) _safeTransferFrom(_saleToken, _funder, totalTokenSale);

    emit InitializedSale(
      _saleToken,
      _paymentToken,
      _startTime,
      _endTime,
      _claimPeriod,
      _softcap,
      _hardcap,
      _price,
      _totalTokenSale,
      _individualCap
    );
  }

  function _addCommitment(address _addr, uint256 _amount) internal {
    uint256 newCommitment = commitments[_addr].add(_amount);
    require(
        newCommitment <= saleInfo.individualCap,
        "Excceed individual cap"
    );
    if (paymentToken == ETH_ADDRESS) {
      require(msg.value >= _amount, "Insufficient Fund");
      uint256 diff = uint256(msg.value).sub(_amount);
      if (diff > 0) {
          _safeTransferETH(_msgSender(), diff);
      }
    } else {
        require(msg.value == 0, "Invalid value");
        _safeTransferFrom(paymentToken, _addr, _amount);
    }

    commitments[_addr] = newCommitment;
    saleStatus.totalCommitment = saleStatus.totalCommitment.add(
        _amount
    );
    emit Commit(_addr, _amount);
  }

  function _payoutPayment(address payable _to, uint256 _amount) internal {
    safeTokenTransfer(paymentToken, _to, _amount);
  }

  function _payoutSaleToken(
    address payable _to,
    uint256 _amount
  ) internal {
    if (saleToken != address(0)) safeTokenTransfer(saleToken, _to, _amount);
  }

  function _checkClaim(address _addr, uint256 _amount, bytes32[] memory _proof) internal view returns (bool) {
    bytes32 node = keccak256(abi.encodePacked(_addr, _amount));
    return MerkleProof.verify(_proof, saleData, node);
  }
}
