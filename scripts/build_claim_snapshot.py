#!/usr/bin/env python3
"""Build the original-minter Merkle snapshot for Cappybara NFTs.

Requires: pip install pycryptodome
Usage: python3 scripts/build_claim_snapshot.py --start-block <NFT_CONTRACT_DEPLOYMENT_BLOCK>
Optional: --end-block <block>, --rpc <BNB_CHAIN_RPC>, --out claim-snapshot.json

Leaves use keccak256(abi.encodePacked(address NFT, uint256 tokenId, address minter));
sorted Merkle pairs are used, matching contracts/CappyNftClaim.sol.
"""
import argparse
import json
import sys
import time
import urllib.request
from pathlib import Path

from Crypto.Hash import keccak

NFT_ADDRESS = "0xba33f7ff4134af69af19ecdf141221666b577c32"
TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
ZERO_TOPIC = "0x" + "0" * 64
DEFAULT_RPC = "https://bsc-dataseed.binance.org/"
MAX_NFTS = 10_000
CHUNK_BLOCKS = 2_000


def keccak256(data: bytes) -> bytes:
    h = keccak.new(digest_bits=256)
    h.update(data)
    return h.digest()


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=45) as resp:
        result = json.loads(resp.read())
    if "error" in result:
        raise RuntimeError(f"RPC {method} error: {result['error']}")
    return result["result"]


def leaf_hash(token_id: int, minter: str) -> bytes:
    # abi.encodePacked(address,uint256,address): 20 bytes + 32 bytes + 20 bytes.
    nft = bytes.fromhex(NFT_ADDRESS[2:])
    return keccak256(nft + token_id.to_bytes(32, "big") + bytes.fromhex(minter[2:]))


def pair_hash(a: bytes, b: bytes) -> bytes:
    return keccak256(a + b) if a < b else keccak256(b + a)


def make_tree(records):
    leaves = [leaf_hash(r["tokenId"], r["originalMinter"]) for r in records]
    levels = [leaves]
    while len(levels[-1]) > 1:
        row = levels[-1]
        next_row = []
        for i in range(0, len(row), 2):
            right = row[i + 1] if i + 1 < len(row) else row[i]
            next_row.append(pair_hash(row[i], right))
        levels.append(next_row)
    proofs = []
    for index in range(len(leaves)):
        proof, pos = [], index
        for row in levels[:-1]:
            sibling = pos ^ 1
            proof.append("0x" + (row[sibling] if sibling < len(row) else row[pos]).hex())
            pos //= 2
        proofs.append(proof)
    return "0x" + levels[-1][0].hex(), proofs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start-block", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--end-block", type=lambda x: int(x, 0))
    parser.add_argument("--rpc", default=DEFAULT_RPC)
    parser.add_argument("--out", default="claim-snapshot.json")
    args = parser.parse_args()

    chain_id = int(rpc(args.rpc, "eth_chainId", []), 16)
    if chain_id != 56:
        sys.exit(f"Wrong chain ID {chain_id}; expected BNB Smart Chain 56.")
    latest = int(rpc(args.rpc, "eth_blockNumber", []), 16)
    end = args.end_block if args.end_block is not None else latest
    if args.start_block < 0 or end < args.start_block or end > latest:
        sys.exit("Invalid block range; end must be at or below the latest block.")

    address = NFT_ADDRESS.lower()
    records_by_id = {}
    cursor = args.start_block
    while cursor <= end:
        hi = min(cursor + CHUNK_BLOCKS - 1, end)
        logs = rpc(args.rpc, "eth_getLogs", [{
            "fromBlock": hex(cursor), "toBlock": hex(hi), "address": address,
            "topics": [TRANSFER_TOPIC, ZERO_TOPIC],
        }])
        for log in logs:
            topics = log.get("topics", [])
            if len(topics) < 3:
                continue
            token_id = int(log["data"], 16)
            minter = "0x" + topics[2][-40:]
            minter = minter.lower()
            if minter == "0x" + "0" * 40:
                raise ValueError(f"Mint to zero address for token #{token_id}")
            if token_id in records_by_id:
                raise ValueError(f"Duplicate mint event for token ID {token_id}")
            records_by_id[token_id] = {
                "tokenId": token_id,
                "originalMinter": minter,
                "mintTx": log.get("transactionHash"),
                "blockNumber": int(log["blockNumber"], 16),
            }
            if len(records_by_id) > MAX_NFTS:
                raise ValueError(f"More than {MAX_NFTS} mint events; aborting snapshot.")
        print(f"Scanned blocks {cursor:,}-{hi:,}; eligible NFT mints: {len(records_by_id):,}", flush=True)
        cursor = hi + 1
        time.sleep(0.05)

    records = [records_by_id[k] for k in sorted(records_by_id)]
    if not records:
        sys.exit("No mint events found; verify start block, RPC, and contract address.")
    root, proofs = make_tree(records)
    claims = {}
    for record, proof in zip(records, proofs):
        claims.setdefault(record["originalMinter"], []).append({
            "tokenId": str(record["tokenId"]), "proof": proof,
            "mintTx": record["mintTx"], "blockNumber": record["blockNumber"],
        })
    output = {
        "schema": "cappybara-original-minter-claim-v1",
        "chainId": 56,
        "nftContract": NFT_ADDRESS,
        "snapshotStartBlock": args.start_block,
        "snapshotEndBlock": end,
        "mintedNftCount": len(records),
        "rewardPerNft": "10000000000000000000000",
        "claimFeeWei": "300000000000000",
        "merkleRoot": root,
        "claimsByOriginalMinter": claims,
        "records": records,
    }
    out = Path(args.out)
    out.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    print(f"\nMerkle root: {root}\nEligible NFTs: {len(records)}\nSnapshot: {out.resolve()}")
    print("Before deployment: independently audit mint events and confirm this root; do not deploy a root built from an unverified range.")


if __name__ == "__main__":
    main()
