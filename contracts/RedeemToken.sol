// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./utils/SafeTransfer.sol";
import "./utils/math/SafeMath.sol";
import "./utils/EnumerableSet.sol";
import "./utils/Context.sol";

contract RedeemToken is SafeTransfer, Context {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct Item {
        uint256 amount;
        uint256 unlockTime;
        address owner;
        uint256 userIndex;
    }

    struct UserInfo {
        mapping(address => uint256[]) lockToItems;
        EnumerableSet.AddressSet lockedItemsWithUser;
    }

    mapping(address => UserInfo) users;
    uint256 public depositId;
    uint256[] public allDepositIds;
    mapping(uint256 => Item) public lockedItem;

    event onLock(address tokenAddress, address user, uint256 amount);
    event onUnlock(address tokenAddress, uint256 amount);

    /**
     * @notice Locking tokens in the vault
     * @param _tokenAddress Address of the token locked
     * @param _amount Number of tokens locked
     * @param _unlockTime Timestamp number marking when tokens get unlocked
     * @param _withdrawer Address where tokens can be withdrawn after unlocking
     */
    function lockTokens(
        address _tokenAddress,
        uint256 _amount,
        uint256 _unlockTime,
        address payable _withdrawer
    ) public returns (uint256 _id) {
        require(_amount > 0, "RedeemToken: token amount is Zero");
        require(
            _unlockTime < 10000000000,
            "ReddemToken: timestamp should be in seconds"
        );
        require(
            _withdrawer != address(0),
            "ReddemToken: withdrawer is zero address"
        );
        _safeTransferFrom(_tokenAddress, _msgSender(), _amount);

        _id = ++depositId;

        lockedItem[_id].amount = _amount;
        lockedItem[_id].unlockTime = _unlockTime;
        lockedItem[_id].owner = _withdrawer;

        allDepositIds.push(_id);

        UserInfo storage userItem = users[_withdrawer];
        userItem.lockedItemsWithUser.add(_tokenAddress);
        userItem.lockToItems[_tokenAddress].push(_id);
        uint256 userIndex = userItem.lockToItems[_tokenAddress].length - 1;
        lockedItem[_id].userIndex = userIndex;

        emit onLock(_tokenAddress, _msgSender(), lockedItem[_id].amount);
    }

    /**
     * @notice Withdrawing tokens from the vault
     * @param _tokenAddress Address of the token to withdraw
     * @param _index Index number of the list with Ids
     * @param _id Id number
     * @param _amount Number of tokens to withdraw
     */
    function withdrawTokens(
        address _tokenAddress,
        uint256 _index,
        uint256 _id,
        uint256 _amount
    ) external {
        require(_amount > 0, "RedeemToken: token amount is zero");
        uint256 id = users[_msgSender()].lockToItems[_tokenAddress][_index];
        Item storage userItem = lockedItem[id];
        require(
            id == _id && userItem.owner == _msgSender(),
            "RedeemToken: not found"
        );
        require(
            userItem.unlockTime < block.timestamp,
            "RedeemToken: not unlocked yet"
        );
        userItem.amount = userItem.amount.sub(_amount);

        if (userItem.amount == 0) {
            uint256[] storage userItems = users[_msgSender()].lockToItems[
                _tokenAddress
            ];
            userItems[_index] = userItems[userItems.length - 1];
            userItems.pop();
        }

        _safeTransfer(_tokenAddress, _msgSender(), _amount);
        emit onUnlock(_tokenAddress, _amount);
    }

    /**
     * @notice Retrieve data from the item under user index number
     * @param _index Index number of the list with item ids
     * @param _tokenAddress Address of the token corresponding to this item
     * @param _user User address
     * @return Items token amount number, Items unlock timestamp, Items owner address, Items Id number
     */
    function getitemAtUserIndex(
        uint256 _index,
        address _tokenAddress,
        address _user
    ) external view returns (uint256, uint256, address, uint256) {
        uint256 id = users[_user].lockToItems[_tokenAddress][_index];
        Item storage item = lockedItem[id];
        return (item.amount, item.unlockTime, item.owner, id);
    }

    /**
     * @notice Function to retrieve token address at desired index for the specified user.
     * @param _user User address.
     * @param _index Index number.
     * @return Token address.
     */
    function getUserLockedItemAtIndex(
        address _user,
        uint256 _index
    ) external view returns (address) {
        UserInfo storage user = users[_user];
        return user.lockedItemsWithUser.at(_index);
    }

    /**
     * @notice Function to retrieve all the data from Item struct under given Id.
     * @param _id Id number.
     * @return All the data for this Id (token amount number, unlock time number, owner address and user index number)
     */
    function getLockedItemAtId(
        uint256 _id
    ) external view returns (uint256, uint256, address, uint256) {
        Item storage item = lockedItem[_id];
        return (item.amount, item.unlockTime, item.owner, item.userIndex);
    }
}
