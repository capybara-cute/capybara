# CAPPY NFT claim — deployment and operation (holder-based)

## Rules implemented

- Each NFT can be claimed **once**, by the wallet **currently holding it** at claim time. A transfer moves the claim right to the new holder.
- Free-minted NFTs (IDs 1-5,000) receive **2,000 CAPPY**; paid-minted NFTs (IDs 5,001-10,000) receive **6,000 CAPPY** (3x the free reward) (18 decimals).
- The claim pool is **40,000,000 CAPPY** (40% of the 100,000,000 supply: 5,000 x 2,000 + 5,000 x 6,000); **60,000,000 CAPPY** (60%) is reserved for liquidity.
- One NFT is claimed per transaction, once. The fixed fee is **0.00022 BNB per NFT**, sent to treasury `0xea92a9df3ad64b2de2e84ccb2cf96b216b06c9bb`. If a claim fails, the entire transaction, including the fee transfer, reverts.
- There is **no minter registry**. The claim contract reads `ownerOf(tokenId)` from the NFT contract directly, so no registration, no admin trust, and no batch transactions are needed. `minter-registry.json`, `registry.html`, and `scripts/build_minter_registry.py` are obsolete and no longer used.

## Deploy and fund

On BNB Smart Chain (chain ID 56), deploy `contracts/CappyNftClaim.sol` with Solidity 0.8.20 or later. Constructor arguments:

1. CAPPY token: `0x1129d5541475ab514dd3127654a9ff72c08645db`
2. NFT contract: `0xba33f7ff4134af69af19ecdf141221666b577c32`
3. Treasury: `0xea92a9df3ad64b2de2e84ccb2cf96b216b06c9bb`

The deploying wallet becomes claim owner. Transfer enough CAPPY to the claim contract to cover claims. The contract has no owner withdrawal function, so fund in stages: for example, **2,994,000 CAPPY** covers the 1,497 free mints so far (1,497 x 2,000). Funding the full **40,000,000 CAPPY** covers all 10,000 possible NFTs. Unclaimed CAPPY that was never sent to the contract stays in the owner wallet and can be added to liquidity later. Verify the deployed token/NFT/treasury addresses, owner, claimed count, and CAPPY balance before opening claims. Deployment, ownership transfer, and funding all require the project owner's own wallet approvals.

## Activate the website

1. Set `CLAIM_CONTRACT` in `claim.html` to the verified deployed claim address.
2. Test on BNB Chain with a current NFT holder: a holder passes; a non-holder fails; a duplicate claim fails; exactly 0.00022 BNB reaches treasury; exactly 2,000 CAPPY (free mint) or 6,000 CAPPY (paid mint) reaches the holder.
3. Only after those checks, change the coming-soon label/status on `index.html` to indicate claims are open and publish.

The site asks holders to approve transactions in their own wallet. It never requests a seed phrase or private key.
