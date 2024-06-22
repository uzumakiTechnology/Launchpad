// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./token/ERC721/ERC721.sol";
import "./utils/cryptography/MerkleProof.sol";
import "./utils/access/Ownable.sol";
import "./utils/Pausable.sol";
import "./utils/math/SafeMath.sol";
import "./utils/EnumerableSet.sol";
import "./utils/ReentrancyGuard.sol";

contract SobaNFT is ERC721, Ownable, Pausable, ReentrancyGuard {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  string public baseTokenURI;
  bytes32 public merkleRoot;
  EnumerableSet.AddressSet _members;

  event BaseTokenURIChanged(string baseTokenURI);
  event MerkleRootUpdated(bytes32 merkleRoot);
  event Claimed(uint256 tokenId, address indexed claimer);

  constructor(
    string memory _name,
    string memory _symbol,
    string memory _baseTokenURI
  ) ERC721(_name, _symbol) {
    baseTokenURI = _baseTokenURI;
  }

  function pause() external onlyOwner {
		_pause();
	}

	function unpause() external onlyOwner {
		_unpause();
	}

  function tokenURI(uint256 id) public view override returns (string memory) {
		return string(abi.encodePacked(baseTokenURI, Strings.toString(id), ".json"));
	}

  function members(uint256 cursor, uint256 sizePage) public view returns (address[] memory values, uint256 newCursor) {
		uint256 length = sizePage;
		if (length > _members.length() - cursor) {
			length = _members.length() - cursor;
		}

		values = new address[](length);
		for (uint256 i = 0; i < length; i++) {
			values[i] = _members.at(cursor + i);
		}

		return (values, cursor + length);
	}

  function checkMember() public view returns (bool) {
    return _members.contains(_msgSender());
  }

  function setBaseTokenURI(string memory _baseTokenURI) public onlyOwner {
		baseTokenURI = _baseTokenURI;
		emit BaseTokenURIChanged(_baseTokenURI);
	}

  function updateMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
    merkleRoot = _merkleRoot;
    emit MerkleRootUpdated(_merkleRoot);
  }

  function mint(address[] memory users, uint256[] memory tokenIds) external onlyOwner {
    require(users.length == tokenIds.length, "Invalid data");
    for (uint256 i = 0; i < users.length; i++) {
      _safeMint(users[i], tokenIds[i]);
    }
  }

  function claim(uint256 tokenId, bytes32[] memory merkleProof) external whenNotPaused nonReentrant {
    require(!_members.contains(_msgSender()), "Already Claimed");
    require(_canClaim(_msgSender(), tokenId, merkleProof), "Not Claimable");
    _safeMint(_msgSender(), tokenId);
    _members.add(_msgSender());
    emit Claimed(tokenId, _msgSender());
  }

  function _canClaim(address _user, uint256 _tokenId, bytes32[] memory _merkleProof) internal view returns (bool) {
    bytes32 node = keccak256(abi.encodePacked(_user, _tokenId));
    return MerkleProof.verify(_merkleProof, merkleRoot, node);
  }
}