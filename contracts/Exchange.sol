// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.0;
// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// import "./utils/SafeTransfer.sol";

// // import "./NFT_TypeERC721.sol";

// contract ExchangeNFTToSoba is Ownable, SafeTransfer {
//     address public SobaToken;

//     struct Rate {
//         uint256 rate;
//         uint256 tier;
//     }

//     mapping(address => Rate) public rateToSoba;

//     mapping(address => mapping(uint256 => bool)) public DataClaims;

//     constructor(
//         address[] memory nftList,
//         uint256[] memory _tierList,
//         address _sobaToken
//     ) {
//         for (uint i = 0; i < nftList.length; i++) {
//             rateToSoba[nftList[i]].rate = _tierList[i];
//             rateToSoba[nftList[i]].tier = i + 1;
//         }

//         SobaToken = _sobaToken;
//     }

//     // ONLY ADMIN
//     function changeRate(address _nft, uint256 _rate) public onlyOwner {
//         require(rateToSoba[_nft].rate != 0, "Invalid NFT address");
//         rateToSoba[_nft].rate = _rate;
//     }

//     function getRate(address _nft) public returns (uint256) {
//         rateToSoba[_nft].rate;
//     }

//     function claimSoba(
//         address _nftAddress,
//         uint256[] memory listId
//     ) external payable {
//         require(rateToSoba[_nftAddress].rate != 0, "Invalid NFT address");
//         require(
//             IERC721(_nftAddress).balanceOf(msg.sender) > 0,
//             "You not have NFT!"
//         );

//         uint totalId = 0;
//         for (uint i = 0; i < listId.length; i++) {
//             if (
//                 // NFT(_nftAddress).checkIfTokenExist(listId[i]) != false &&
//                 IERC721(_nftAddress).ownerOf(listId[i]) == msg.sender &&
//                 DataClaims[_nftAddress][listId[i]] == false
//             ) {
//                 totalId = totalId + 1;
//                 DataClaims[_nftAddress][listId[i]] = true;
//             }
//         }

//         require(totalId > 0, "Not available to claims");

//         safeTokenTransfer(
//             SobaToken,
//             payable(msg.sender),
//             totalId *
//                 rateToSoba[_nftAddress].rate *
//                 (10 ** ERC20(SobaToken).decimals())
//         );
//     }
// }
