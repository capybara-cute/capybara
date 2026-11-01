# CAPPY NFT claim — deployment and activation

## Rules implemented

- Every NFT ID in the verified mint snapshot earns **10,000 CAPPY** (18 decimals).
- A claim is restricted to the wallet that received the NFT in its original mint `Transfer(address(0), minter, tokenId)` event. Later owners cannot claim that NFT's allocation.
- Each NFT can be claimed once. One transaction claims one NFT.
- Each successful claim requires exactly **0.0003 BNB**, sent to the project treasury `0xea92a9df3ad64b2de2e84ccb2cf96b216b06c9bb` embedded at deployment. If the claim fails, the whole transaction—including the fee transfer—reverts.
- If all 10,000 NFTs are minted and claimed, the total allocation is 100,000,000 CAPPY. Since the fixed-supply token has no mint function, unminted/unclaimed NFT allocations remain unused; this contract has no owner withdrawal function.

## Important: not live yet

`claim.html` is deliberately fail-closed: `CLAIM_CONTRACT` is blank and no snapshot JSON is included. Do not link it as an active claim page until the mint snapshot is audited, the contract is deployed, and the distributor is funded. No on-chain transaction has been performed by this repository change.

## Build the original-minter snapshot

1. Confirm the NFT deployment block and choose a stable BNB Chain RPC.
2. In a Python environment with PyCryptodome (`python3 -m pip install pycryptodome`), run:

   ```sh
   python3 scripts/build_claim_snapshot.py --start-block <NFT_DEPLOYMENT_BLOCK> --rpc <BNB_RPC_URL> --out claim-snapshot.json
   ```

3. Independently audit all mint events, the number of distinct token IDs, and representative minter addresses against BscScan or a second RPC. Do not deploy the root until this check passes. The script fails if it finds duplicate IDs or more than 10,000 mint events.
4. Preserve the generated JSON and published Merkle root as the canonical snapshot. The root is immutable once the claim contract is deployed.

## Deploy and fund

On BNB Smart Chain (chain ID 56), deploy `contracts/CappyNftClaim.sol` with Solidity 0.8.20 or later. Constructor arguments, in order:

1. CAPPY token: `0x1129d5541475ab514dd3127654a9ff72c08645db`
2. NFT contract: `0xba33f7ff4134af69af19ecdf141221666b577c32`
3. Treasury: `0xea92a9df3ad64b2de2e84ccb2cf96b216b06c9bb`
4. `merkleRoot` from the verified snapshot JSON
5. Reward per NFT in base units: `10000000000000000000000` (10,000 × 10^18)

The deployer must then transfer enough CAPPY to the claim contract. Funding it with **100,000,000 CAPPY** covers the full 10,000-NFT allocation. Check the claim contract balance and verify `merkleRoot`, `rewardPerNft`, `token`, `nft`, and `treasury` on-chain before opening claims. Contract deployment and token funding require the owner's own wallet approvals; they are not performed by the website code.

## Activate the website

1. Put the audited `claim-snapshot.json` beside `claim.html` in the hosted site.
2. Set `CLAIM_CONTRACT` near the top of the inline script in `claim.html` to the verified deployed address.
3. Test with a test wallet/minter and verify: wrong wallet rejected, wrong proof rejected, duplicate claim rejected, exactly 0.0003 BNB reaches the treasury, and exactly 10,000 CAPPY reaches the original minter.
4. The main site's `index.html` now links to `claim.html` with a clear coming-soon status. After these checks, configure the deployed contract and audited snapshot, then change the CTA/status from coming-soon to open and publish the snapshot.

The site asks users to approve transactions in their own wallet; it never requests a seed phrase or private key.
