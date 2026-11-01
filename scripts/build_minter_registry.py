#!/usr/bin/env python3
"""Build a registry batch from Cappybara NFT mint Transfer events.

Usage:
  python3 scripts/build_minter_registry.py --start-block <NFT_DEPLOYMENT_BLOCK> \
    --rpc <BNB_CHAIN_RPC> --out minter-registry.json

The deployed NFT contract cannot call the claim registry automatically. The
project registry owner submits the generated tokenIds/originalMinters arrays to
registerMinters(). For later mints, rerun for only the new block range and
register each new batch. Confirm every batch against a second source before
submitting it.
"""
import argparse
import json
import time
import urllib.request
from pathlib import Path

NFT_ADDRESS = "0xba33f7ff4134af69af19ecdf141221666b577c32"
TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
ZERO_TOPIC = "0x" + "0" * 64
DEFAULT_RPC = "https://bsc-dataseed.binance.org/"
CHUNK_BLOCKS = 2_000
DEFAULT_BATCH_SIZE = 100


def rpc(url, method, params):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=45) as resp:
        result = json.loads(resp.read())
    if "error" in result:
        raise RuntimeError(f"RPC {method} error: {result['error']}")
    return result["result"]


def decode_mint_log(log):
    topics = log.get("topics", [])
    # ERC-721 Transfer indexes from, to, and tokenId: topic0..topic3.
    # Its standard event data field is empty.
    if len(topics) < 4:
        return None
    token_id = int(topics[3], 16)
    original_minter = "0x" + topics[2][-40:].lower()
    if original_minter == "0x" + "0" * 40:
        raise ValueError(f"Mint to zero address for token #{token_id}")
    return {
        "tokenId": str(token_id),
        "originalMinter": original_minter,
        "mintTx": log.get("transactionHash"),
        "blockNumber": int(log["blockNumber"], 16),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start-block", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--end-block", type=lambda x: int(x, 0))
    parser.add_argument("--rpc", default=DEFAULT_RPC)
    parser.add_argument("--out", default="minter-registry.json")
    parser.add_argument("--batch-size", type=int, default=DEFAULT_BATCH_SIZE)
    args = parser.parse_args()
    if not 1 <= args.batch_size <= 100:
        parser.error("--batch-size must be from 1 to 100")

    chain_id = int(rpc(args.rpc, "eth_chainId", []), 16)
    if chain_id != 56:
        parser.error(f"Wrong chain ID {chain_id}; expected BNB Smart Chain 56")
    latest = int(rpc(args.rpc, "eth_blockNumber", []), 16)
    end = args.end_block if args.end_block is not None else latest
    if args.start_block < 0 or end < args.start_block or end > latest:
        parser.error("Invalid block range; end must be at or below the latest block")

    records_by_id = {}
    cursor = args.start_block
    while cursor <= end:
        hi = min(cursor + CHUNK_BLOCKS - 1, end)
        logs = rpc(args.rpc, "eth_getLogs", [{
            "fromBlock": hex(cursor), "toBlock": hex(hi), "address": NFT_ADDRESS,
            "topics": [TRANSFER_TOPIC, ZERO_TOPIC],
        }])
        for log in logs:
            record = decode_mint_log(log)
            if record is None:
                continue
            token_id = int(record["tokenId"])
            if token_id in records_by_id:
                raise ValueError(f"Duplicate mint event for token ID {token_id}")
            records_by_id[token_id] = record
        print(f"Scanned blocks {cursor:,}-{hi:,}; mint events in range: {len(records_by_id):,}", flush=True)
        cursor = hi + 1
        time.sleep(0.05)

    records = [records_by_id[k] for k in sorted(records_by_id)]
    if not records:
        parser.error("No mint events found; verify start block, RPC, and NFT contract")
    batches = []
    for i in range(0, len(records), args.batch_size):
        batch = records[i:i + args.batch_size]
        batches.append({
            "tokenIds": [r["tokenId"] for r in batch],
            "originalMinters": [r["originalMinter"] for r in batch],
            "records": batch,
        })
    output = {
        "schema": "cappybara-minter-registry-v1",
        "chainId": 56,
        "nftContract": NFT_ADDRESS,
        "claimRewardPerNft": "10000000000000000000000",
        "claimFeeWei": "300000000000000",
        "scanStartBlock": args.start_block,
        "scanEndBlock": end,
        "mintedNftCountInRange": len(records),
        "batchSize": args.batch_size,
        "registrationBatches": batches,
        "records": records,
    }
    out = Path(args.out)
    out.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    print(f"\nMint records: {len(records)}\nRegistration batches: {len(batches)}\nOutput: {out.resolve()}")
    print("Audit token IDs and original minters against the mint Transfer events before submitting any registry transaction.")


if __name__ == "__main__":
    main()
