//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

interface IERC20Mintable {
  function mint( uint256 amount_ ) external;

  function mint( address account_, uint256 ammount_ ) external;

  function transfer(address recipient, uint256 amount) external returns (bool);

  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IERC1155Mintable {
    function mint( address account_, uint256 id_, uint256 amount_, bytes memory data_ ) external;

    function safeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external;
}

contract PoXMigration is Ownable, ERC1155Holder {
    using Math for uint256;
    using SignedMath for int256;

    struct UserInfo {
        uint256 deposited;
        uint256 minted;
        uint256 lastDeposit;
        uint256 memberships;
        uint256 affiliates;
    }

    struct GetUserInfo {
        uint256 deposited;
        uint256 minted;
        uint256 lastDeposit;
        uint256 memberships;
        uint256 affiliates;
    }

    IERC20 public euler;
    address public poxme;
    IERC1155 public membershipNFT;
    IERC721 public affiliateNFT;
    uint256 public eulerTxFee = 100;
    uint256 public minDepositAmount = 4000 * 10**18;
    bool public isMigrationActive = false;

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event StartMigration(address indexed user, uint256 startBlock);
    event StopMigration(address indexed user, uint256 stopBlock);
    event ClaimTokens(address indexed user, uint256 amount);
    event ClaimMemberships(address indexed user, uint256 amount);
    event ClaimAffiliates(address indexed user, uint256 amount);

    constructor(address _owner) Ownable(_owner) {}

    bool private initialized = false;

    function initialize(IERC20 _euler, address _poxme, IERC1155 _membershipNFT, IERC721 _affiliateNFT) external onlyOwner {
        require(!initialized, "Already initialized");
        require(address(_euler) != address(0), "Old Token address is not valid");
        require(address(_poxme) != address(0), "New Token address is not valid");
        require(address(_affiliateNFT) != address(0), "Affiliate address is not valid");
        require(address(_membershipNFT) != address(0), "Membership NFT address is not valid");

        euler = _euler;
        poxme = _poxme;
        membershipNFT = _membershipNFT;
        affiliateNFT = _affiliateNFT;

        initialized = true;
    }

    function initializeMemberships() external onlyOwner {
        IERC1155Mintable membershipNFTMintable = IERC1155Mintable(address(membershipNFT));
        // mint 25000 memberships
        membershipNFTMintable.mint(address(this), 1, 25000, "");
    }

    function startMigration() external onlyOwner {
        isMigrationActive = true;
        // use current block
        uint256 startBlock = block.number;
        emit StartMigration(msg.sender, startBlock);
    }

    function stopMigration() external onlyOwner {
        isMigrationActive = false;
        uint256 startBlock = block.number;
        emit StartMigration(msg.sender, startBlock);
    }

    function getUserInfo(address _user)
        public
        view
        returns (GetUserInfo memory) {
                UserInfo storage user = userInfo[_user];
                GetUserInfo memory userAux;
                userAux.deposited = user.deposited;
                userAux.minted = user.minted;
                userAux.lastDeposit = user.lastDeposit;
                userAux.memberships = user.memberships;
                userAux.affiliates = user.affiliates;
                return userAux;
    }

    function deposit(uint256 amount) external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 sumAmount = amount + user.deposited;

        require(
            sumAmount >= minDepositAmount,
            "The minimum deposit amount is 4000 tokens!"
        );

        if (amount > 0) {
            euler.transferFrom(address(msg.sender), address(this), amount);
            user.deposited = user.deposited + amount;
            user.lastDeposit = block.number;
        }

        emit Deposit(msg.sender, amount);
    }

    function claimTokens() external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.deposited;
        uint256 minted = user.minted;
        uint256 lastDeposit = user.lastDeposit;

        require(amount > 0, "You don't have any migrated tokens!");
        // validate that the user has not deposited in the last 100 blocks
        require(block.number > lastDeposit + 100, "You have deposited in the last 100 blocks!");

        uint256 amountToMint = amount;

        if (amountToMint > 0) {
            IERC20Mintable(poxme).mint(address(msg.sender), amountToMint);
            user.minted = minted + amountToMint;
        }
        emit ClaimTokens(msg.sender, amountToMint);
    }

    function claimMemberships() external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.deposited;
        uint256 memberships = user.memberships;
        uint256 lastDeposit = user.lastDeposit;

        require(amount > 0, "You don't have any migrated tokens!");
        // validate that the user has not deposited in the last 100 blocks
        require(block.number > lastDeposit + 100, "You have deposited in the last 100 blocks!");

        // calculate the amount of memberships to mint by dividing the amount deposited by 4000 * 10 **18
        (bool overflowsDiv, uint256 amountToMint) = amount.tryDiv(4000 * 10 ** 18);
        // round to the floor integer
        (bool overflowsSub, uint256 mintable) = amountToMint.trySub(memberships);

        uint104 max = 1;

        if(overflowsDiv || overflowsSub) {
            max = 1;
        }

        if (amountToMint > 0 && max > 0) {
            // transfer the memberships to the user
            IERC1155Mintable(poxme).safeBatchTransferFrom(address(this), address(msg.sender), new uint256[](1), new uint256[](mintable), "");
            user.memberships = memberships + mintable;
        }

        emit ClaimMemberships(msg.sender, amountToMint);
    }
}