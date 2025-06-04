import subprocess
import json

# Config
rpcuser = "Jw2Fresh420"
rpcpassword = "0dvsiwbrbi0BITC0IN2021"
start_height = 898738
end_height = 899737

headers = []

for height in range(start_height, end_height + 1):
    print(f"Fetching block at height {height}...")
    
    # Get block hash
    hash_cmd = [
        "bitcoin-cli",
        f"-rpcuser={rpcuser}",
        f"-rpcpassword={rpcpassword}",
        "getblockhash",
        str(height)
    ]
    block_hash = subprocess.check_output(hash_cmd).decode().strip()
    
    # Get block header
    header_cmd = [
        "bitcoin-cli",
        f"-rpcuser={rpcuser}",
        f"-rpcpassword={rpcpassword}",
        "getblockheader",
        block_hash,
        "false"  # Set to true if you want JSON; false for raw hex
    ]
    block_header = subprocess.check_output(header_cmd).decode().strip()
    
    headers.append({
        "height": height,
        "hash": block_hash,
        "header_hex": block_header
    })

# Save to file
with open("oracle/block_headers.json", "w") as f:
    json.dump(headers, f, indent=2)

print("✅ Done. Saved 1000 block headers to oracle/block_headers.json")
