// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TokenPresale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 bought;
        bool claimed;
        bool whitelisted;
    }

    uint256 public constant BUY_INTERVAL = 0.01 ether;

    uint256 public open_for_all; // timestamp of when can people join

    IERC20 public TOKEN;
    uint256 public totalRaise;
    uint256 public whitelistedUsers;
    uint256 public totalBuyers;
    bool public claimable;
    bool public endSale;
    uint256 public tokensToDistribute;

    mapping(address => UserInfo) public userInfo;

    event BoughtToken(address indexed _user, uint256 amount);
    event ClaimToken(address indexed _user, uint256 amount);
    event TokenSet(address _token);
    event AuditLog(string message);

    receive() external payable {}

    function buyToken() external payable nonReentrant {
        uint256 _amount = msg.value;
        require(!endSale, "Sale ended");
        require(_amount % BUY_INTERVAL == 0, "Only intervals of 0.01 BNB");
        UserInfo storage user = userInfo[msg.sender];
        require(user.whitelisted || open_for_all > 0, "Only whitelist");
        totalRaise += _amount;
        user.bought += _amount;

        emit BoughtToken(msg.sender, _amount);
    }

    function claimTokens() external nonReentrant {
        require(claimable, "Not yet");
        UserInfo storage user = userInfo[msg.sender];
        require(!user.claimed && user.bought > 0, "Already claimed");
        user.claimed = true;
        uint256 claimableTokens = (user.bought * tokensToDistribute) /
            totalRaise;
        TOKEN.safeTransfer(msg.sender, claimableTokens);
        emit ClaimToken(msg.sender, claimableTokens);
    }

    function addPrivateTokens(uint256 _amount) external onlyOwner {
        TOKEN.safeTransferFrom(msg.sender, address(this), _amount);
        tokensToDistribute += _amount;
    }

    function ownerClaim() external onlyOwner nonReentrant {
        uint256 _bal = address(this).balance;
        (bool succ, ) = payable(owner()).call{value: _bal}("");
        require(succ, "Error transferring ETH");
        emit AuditLog("Owner Claimed Funds");
    }

    function addWhitelist(address _user) external onlyOwner {
        require(!userInfo[_user].whitelisted, "Already whitelisted");
        userInfo[_user].whitelisted = true;
        whitelistedUsers++;
    }

    function whitelistMultiple(address[] calldata _users) external onlyOwner {
        uint256 len = _users.length;
        require(len > 0, "Non zero");
        for (uint8 i = 0; i < len; i++) {
            userInfo[_users[i]].whitelisted = true;
        }
        whitelistedUsers += len;
    }

    function openForAll() external onlyOwner {
        open_for_all = true;
        emit AuditLog("Private Sale Open For All");
    }

    function endTheSale() external onlyOwner {
        endSale = true;
        emit AuditLog("Sale ended");
    }

    function tokensClaimable() external onlyOwner {
        claimable = true;
        emit AuditLog("Tokens Claimable");
    }
}
