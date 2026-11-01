# CAPPY NFT claim registry — deployment and operation

## Rules implemented

- Each registered NFT ID receives **10,000 CAPPY** (18 decimals), whether it was free-minted or paid-minted.
- Only the wallet that received the NFT in the original mint `Transfer(address(0), minter, tokenId)` event can claim. A later NFT owner cannot claim that NFT's allocation.
- One NFT is claimed per transaction, once. The fixed fee is **0.0003 BNB per NFT**, sent to treasury `0xea92a9df3ad64b2de2e84ccb2cf96b216b06c9bb`. If a claim fails, the entire transaction, including the fee transfer, reverts.
- The registry contract supports up to 10,000 IDs. At 10,000 registrations, the full 100,000,000 CAPPY supply is allocated. It has no owner withdrawal function.

## Important limitation of the existing NFT contract

The NFT contract is already deployed and cannot be modified to call a new claim contract during mint. Therefore, the registry cannot automatically know a minter. The project registry owner must read the original mint event and register each NFT's first recipient on-chain. This works for both existing and future mints, but future claims become available only after the admin registers them. Registration is an explicit trust in the project admin; audit every address and token ID before submitting a registration transaction.

The public page `claim.html` uses the user's connected BNB Chain wallet and an NFT token ID to read the registry. It is deliberately fail-closed until its `CLAIM_CONTRACT` address is set. No on-chain transaction has been performed by the repository changes.

## Build registry batches

1. Find the NFT contract deployment block for `0xba33f7ff4134af69af19ecdf141221666b577c32`.
2. In Python, run:

   ```sh
   python3 scripts/build_minter_registry.py --start-block <NFT_DEPLOYMENT_BLOCK> --rpc https://bsc-dataseed.binance.org/ --out minter-registry.json
   ```

3. Audit the `records` and each batch's `tokenIds` / `originalMinters` against the NFT mint `Transfer` events in BscScan and preferably a second RPC. The `originalMinters` must be the `to` address in the mint event where `from` is the zero address—not current NFT owners.
4. Submit each audited batch with the registry contract owner's wallet by calling `registerMinters(uint256[] tokenIds,address[] originalMinters)`. The admin page at `https://capyybara.fun/registry.html` validates the chain, contract's token/NFT/treasury addresses, and connected owner wallet before offering the signing action. Enter the verified registry address, connect the owner wallet, upload the audited JSON file, review the batch, and approve each wallet transaction only after checking it. Keep batches at or below 100 IDs, as the script outputs. Verify `originalMinterOf(tokenId)` on-chain after registration.
5. For future mints, rerun the script beginning at **last scanned end block + 1**, audit only the new records, and register them. Do not include already-registered IDs; the contract rejects duplicates. Keep the last completed scan block and registration transaction hashes in project records.

## Deploy and fund

On BNB Smart Chain (chain ID 56), deploy `contracts/CappyNftClaim.sol` with Solidity 0.8.20 or later. Constructor arguments:

1. CAPPY token: `0x1129d5541475ab514dd3127654a9ff72c08645db`
2. NFT contract: `0xba33f7ff4134af69af19ecdf141221666b577c32`
3. Treasury: `0xea92a9df3ad64b2de2e84ccb2cf96b216b06c9bb`

The deploying wallet becomes registry owner. Register and audit all existing NFT minters, then transfer enough CAPPY to the registry contract. Funding it with **100,000,000 CAPPY** covers all 10,000 possible NFTs. Verify the deployed token/NFT/treasury addresses, owner, registration count, and CAPPY balance before opening claims. Deployment, registration, ownership transfer, and funding all require the project owner's own wallet approvals.

## Activate the website

1. Set `CLAIM_CONTRACT` in `claim.html` to the verified deployed registry address.
2. Test on BNB Chain with a registered minter: correct minter passes; unregistered ID and wrong wallet fail; a duplicate claim fails; exactly 0.0003 BNB reaches treasury; exactly 10,000 CAPPY reaches the original minter.
3. Only after those checks, change the coming-soon label/status on `index.html` to indicate claims are open and publish.

The site asks minters to approve transactions in their own wallet. It never requests a seed phrase or private key.
