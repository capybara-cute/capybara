// SPDX-License-Identifier: MIT
// Cappybara community token (BEP20 / ERC20 on BNB Chain).
// APPROVED DRAFT 2026-11-01 (user: "Ini sudah bagus dan pembagiannnya").
// Fixed supply, minted once to the deployer at construction, no further
// minting, no sale function, no tax. Name/symbol are constructor args so
// the owner decides the FINAL name/symbol at deploy signing time.
// WARNING: the Cappybara NFT contract already uses symbol CAPY on BNB
// Chain (see capybara deploy.html). Using CAPY again for this token can
// confuse wallets/explorers — consider CAPPY at deploy time. After deploy,
// name/symbol can NEVER be changed.
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CappybaraToken is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 100_000_000 * 10 ** 18; // 100,000,000 tokens (proposal, approved)

    constructor(string memory tokenName, string memory tokenSymbol) ERC20(tokenName, tokenSymbol) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
