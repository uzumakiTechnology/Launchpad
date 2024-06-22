// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
// import "@openzeppelin/contracts/utils/Pausable.sol";

// contract DropNFT is ERC721, SafeTransfer, Pausable, Ownable {
//   using Strings for uint256;

//   struct TierInfo {
//     uint256 supply;
//     uint256 maxPerSale;
//     uint256 price;
//     address payment;
//     address beneficiary;
//   }

//   address private constant ETH_ADDRESS =
//         0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

//   mapping(address => TierInfo) public tiers;

//   function createDrops(
//       address[] memory _tiers,
//       address[] memory _payments,
//       uint256[] memory supply,
//       uint256[] memory _maxPerSales,
//       uint256[] memory _prices,
//       address[] memory _beneficiaries
//   ) public whenNotPaused {
//     require(
//       _tiers.length === supply.length &&
//       _tiers.length === _payments.length &&
//       _tiers.length === _prices.length &&
//       _tiers.length === _maxPerSales.length &&
//       _tiers.length === _beneficiaries.length
//       , "invalid data");
//     for (uint i = 0; i < _tiers.length; i++) {
//       _createDrop(_tiers[i], _payments[i], supply[i], _maxPerSales[i], _prices[i], _beneficiaries[i]);
//     }
//   }

//   function pause() external onlyOwner {
// 		_pause();
// 	}

// 	function unpause() external onlyOwner {
// 		_unpause();
// 	}

//   function buy(address tier, uint256 amount) public payable whenNotPaused {
//     TierInfo currentTier = tiers[tier];
//     require(amount + IERC721(tier).totalSupply() <= currentTier.supply, "Sold out");
//     if (currentTier.maxPerSale !== 0) {
//       require(amount + IERC721(tier).balanceOf(_msgSender()) <= currentTier.maxPerSale, "Exceed max sale")
//     }
//     uint256 totalPaid = amount * currentTier.price;
//     if (currentTier.payment != ETH_ADDRESS) {
//       require(IERC20(payment).balanceOf(_msgSender()) >= totalPaid, "Insufficient fund");
//     } else {
//       require(_msgSender().value >= totalPaid, "Insufficient fund");
//     }

//     safeTokenTransfer(currentTier.payment, currentTier.beneficiary, totalPaid);
//     for (uint256 i = 1; i <= amount; ++i) {
//       _safeMint(_msgSender(), IERC721(tier).totalSupply() + 1);
//     }
//   }

//   function _createDrop(
//       address tier,
//       address payment,
//       uint256 supply,
//       uint256 maxPerSale,
//       uint256 price,
//       address beneficiary
//   ) internal {
//     tiers[tier] = {
//       supply,
//       maxPerSale,
//       price,
//       payment,
//       beneficiary
//     };
//   }
// }
