// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Claim {
    function transfer(address to, uint256 value) external returns (bool);
}

interface IERC721Claim {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/**
 * @title CappyNftClaim
 * @notice CAPPY claims for current Cappybara NFT holders.
 * @dev No minter registry: whoever holds the NFT at claim time may claim,
 *      once per NFT. A transfer moves the claim right to the new holder.
 *      The claim contract never needs to know who minted the NFT.
 */
contract CappyNftClaim {
    uint256 public constant CLAIM_FEE = 0.00022 ether;
    uint256 public constant REWARD_FREE = 2_000 * 10 ** 18;
    uint256 public constant REWARD_PAID = 6_000 * 10 ** 18;
    uint256 public constant FREE_MAX_TOKEN_ID = 5_000;
    uint256 public constant MAX_NFTS = 10_000;

    address public immutable token;
    address public immutable nft;
    address payable public immutable treasury;
    address public owner;

    mapping(uint256 => bool) public claimed;
    uint256 public claimedCount;

    event Claimed(uint256 indexed tokenId, address indexed holder, uint256 amount, uint256 fee);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error InvalidAddress();
    error NotOwner();
    error IncorrectFee();
    error NotCurrentHolder();
    error AlreadyClaimed();
    error TreasuryTransferFailed();
    error TokenTransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address token_, address nft_, address payable treasury_) {
        if (token_ == address(0) || nft_ == address(0) || treasury_ == address(0)) revert InvalidAddress();
        token = token_;
        nft = nft_;
        treasury = treasury_;
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /** Reward for a token ID: 2,000 CAPPY for free mints (ID <= 5,000),
     *  6,000 CAPPY for paid mints (ID > 5,000). */
    function rewardFor(uint256 tokenId) public pure returns (uint256) {
        return tokenId <= FREE_MAX_TOKEN_ID ? REWARD_FREE : REWARD_PAID;
    }

    /** One NFT per claim transaction; exact 0.00022 BNB fee goes to treasury.
     *  Only the wallet currently holding the NFT may claim, once per NFT. */
    function claim(uint256 tokenId) external payable {
        if (msg.value != CLAIM_FEE) revert IncorrectFee();
        if (claimed[tokenId]) revert AlreadyClaimed();
        if (IERC721Claim(nft).ownerOf(tokenId) != msg.sender) revert NotCurrentHolder();

        claimed[tokenId] = true;
        claimedCount++;
        (bool feeSent, ) = treasury.call{value: CLAIM_FEE}("");
        if (!feeSent) revert TreasuryTransferFailed();
        uint256 reward = rewardFor(tokenId);
        if (!IERC20Claim(token).transfer(msg.sender, reward)) revert TokenTransferFailed();
        emit Claimed(tokenId, msg.sender, reward, CLAIM_FEE);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
