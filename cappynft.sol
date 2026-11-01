// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Claim {
    function transfer(address to, uint256 value) external returns (bool);
}

/**
 * @title CappyNftClaim
 * @notice Registry-based CAPPY claims for original NFT minters.
 * @dev The deployed NFT contract cannot call this registry automatically, so
 *      the project registry admin must record each original minter from the
 *      NFT's on-chain mint Transfer event. This supports future mints without
 *      changing the already-deployed NFT contract.
 */
contract CappyNftClaim {
    uint256 public constant CLAIM_FEE = 0.0003 ether;
    uint256 public constant REWARD_PER_NFT = 10_000 * 10 ** 18;
    uint256 public constant MAX_NFTS = 10_000;

    address public immutable token;
    address public immutable nft;
    address payable public immutable treasury;
    address public owner;

    mapping(uint256 => address) public originalMinterOf;
    mapping(uint256 => bool) public claimed;
    uint256 public registeredCount;
    uint256 public claimedCount;

    event MinterRegistered(uint256 indexed tokenId, address indexed originalMinter);
    event Claimed(uint256 indexed tokenId, address indexed originalMinter, uint256 amount, uint256 fee);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error InvalidAddress();
    error NotOwner();
    error InvalidArrayLength();
    error InvalidMinter();
    error AlreadyRegistered();
    error SupplyLimitReached();
    error IncorrectFee();
    error NotOriginalMinter();
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

    /** Register one original mint recipient. Use the recipient from the NFT
     *  contract's mint Transfer event (from address(0)), never the current NFT owner.
     */
    function registerMinter(uint256 tokenId, address originalMinter) external onlyOwner {
        _register(tokenId, originalMinter);
    }

    /** Batch registration reduces gas for initial and future mint batches. */
    function registerMinters(uint256[] calldata tokenIds, address[] calldata originalMinters) external onlyOwner {
        if (tokenIds.length != originalMinters.length) revert InvalidArrayLength();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _register(tokenIds[i], originalMinters[i]);
        }
    }

    function _register(uint256 tokenId, address originalMinter) private {
        if (originalMinter == address(0)) revert InvalidMinter();
        if (originalMinterOf[tokenId] != address(0)) revert AlreadyRegistered();
        if (registeredCount >= MAX_NFTS) revert SupplyLimitReached();
        originalMinterOf[tokenId] = originalMinter;
        registeredCount++;
        emit MinterRegistered(tokenId, originalMinter);
    }

    /** One NFT per claim transaction; exact 0.0003 BNB fee goes to treasury. */
    function claim(uint256 tokenId) external payable {
        if (msg.value != CLAIM_FEE) revert IncorrectFee();
        if (originalMinterOf[tokenId] != msg.sender) revert NotOriginalMinter();
        if (claimed[tokenId]) revert AlreadyClaimed();

        claimed[tokenId] = true;
        claimedCount++;
        (bool feeSent, ) = treasury.call{value: CLAIM_FEE}("");
        if (!feeSent) revert TreasuryTransferFailed();
        if (!IERC20Claim(token).transfer(msg.sender, REWARD_PER_NFT)) revert TokenTransferFailed();
        emit Claimed(tokenId, msg.sender, REWARD_PER_NFT, CLAIM_FEE);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
