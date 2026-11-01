// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Claim {
    function transfer(address to, uint256 value) external returns (bool);
}

/**
 * @title CappyNftClaim
 * @notice One-time CAPPY allocation per NFT, reserved for its original minter.
 * @dev Merkle root is generated from NFT mint Transfer events (zero address ->
 *      original minter). Fund this distributor with CAPPY before enabling claims.
 */
contract CappyNftClaim {
    uint256 public constant CLAIM_FEE = 0.0003 ether;
    address public immutable token;
    address public immutable nft;
    address payable public immutable treasury;
    bytes32 public immutable merkleRoot;
    uint256 public immutable rewardPerNft;
    address public immutable snapshotPublisher;

    mapping(uint256 => bool) public claimed;

    event Claimed(uint256 indexed tokenId, address indexed originalMinter, uint256 amount, uint256 fee);

    error InvalidAddress();
    error InvalidRoot();
    error InvalidReward();
    error IncorrectFee();
    error NotOriginalMinter();
    error AlreadyClaimed();
    error InvalidProof();
    error TreasuryTransferFailed();
    error TokenTransferFailed();

    constructor(
        address token_,
        address nft_,
        address payable treasury_,
        bytes32 merkleRoot_,
        uint256 rewardPerNft_
    ) {
        if (token_ == address(0) || nft_ == address(0) || treasury_ == address(0)) revert InvalidAddress();
        if (merkleRoot_ == bytes32(0)) revert InvalidRoot();
        if (rewardPerNft_ == 0) revert InvalidReward();
        token = token_;
        nft = nft_;
        treasury = treasury_;
        merkleRoot = merkleRoot_;
        rewardPerNft = rewardPerNft_;
        snapshotPublisher = msg.sender;
    }

    /**
     * @param tokenId NFT token ID in the published mint snapshot.
     * @param originalMinter Wallet that received the NFT at its original mint.
     * @param proof Sorted-pair Merkle proof from the published snapshot JSON.
     * Fee is 0.0003 BNB per NFT claimed, paid to the project treasury.
     */
    function claim(uint256 tokenId, address originalMinter, bytes32[] calldata proof) external payable {
        if (msg.value != CLAIM_FEE) revert IncorrectFee();
        if (msg.sender != originalMinter) revert NotOriginalMinter();
        if (claimed[tokenId]) revert AlreadyClaimed();

        bytes32 node = keccak256(abi.encodePacked(nft, tokenId, originalMinter));
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 sibling = proof[i];
            node = node < sibling
                ? keccak256(abi.encodePacked(node, sibling))
                : keccak256(abi.encodePacked(sibling, node));
        }
        if (node != merkleRoot) revert InvalidProof();

        // Effects before external calls; any failed transfer reverts the whole transaction.
        claimed[tokenId] = true;
        (bool feeSent, ) = treasury.call{value: CLAIM_FEE}("");
        if (!feeSent) revert TreasuryTransferFailed();
        if (!IERC20Claim(token).transfer(originalMinter, rewardPerNft)) revert TokenTransferFailed();
        emit Claimed(tokenId, originalMinter, rewardPerNft, CLAIM_FEE);
    }
}
