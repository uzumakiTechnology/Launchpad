// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// contract TierNFT is ERC721, Ownable {
//     using Strings for uint256;

//     string public baseTokenURI;

//     event BaseTokenURIChanged(string baseTokenURI);

//     constructor(
//         string memory name,
//         string memory symbol,
//         string memory baseURI
//     ) ERC721(name, symbol) {
//         baseTokenURI = baseURI;
//     }

//     function tokenURI(uint256 id) public view override returns (string memory) {
//         return string(abi.encodePacked(baseTokenURI, Strings.toString(id)));
//     }

//     function setBaseTokenURI(string memory _baseTokenURI) public onlyOwner {
//         baseTokenURI = _baseTokenURI;
//         emit BaseTokenURIChanged(_baseTokenURI);
//     }

//     function mint(address to, uint256 tokenId) external onlyOwner {
//         _safeMint(to, tokenId);
//     }
// }
