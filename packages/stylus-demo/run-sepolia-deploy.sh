#!/bin/bash
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Exit on error
set -e

# Arbitrum Sepolia RPC URL
SEPOLIA_RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"

# Check for PRIVATE_KEY environment variable
if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Error: PRIVATE_KEY environment variable is not set."
  echo "Please set your private key: export PRIVATE_KEY=your_private_key_here"
  exit 1
fi

# Optionally, check for required tools
for cmd in cast cargo; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: $cmd is not installed."
    exit 1
  fi
done

# Check if we can connect to Arbitrum Sepolia
echo "Checking connection to Arbitrum Sepolia..."
if ! curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_version","params":[],"id":1}' \
  "$SEPOLIA_RPC_URL" > /dev/null; then
    echo "Error: Cannot connect to Arbitrum Sepolia RPC"
    exit 1
fi
echo "Connected to Arbitrum Sepolia!"

# Deploy Cache Manager Contract
# (Replace the bytecode below with your actual contract bytecode if needed)
# echo "Deploying Cache Manager contract to Arbitrum Sepolia..."
# cache_deploy_output=$(cast send --private-key "$PRIVATE_KEY" \
#   --rpc-url "$SEPOLIA_RPC_URL" \
#   --create 0x60a06040523060805234801561001457600080fd5b50608051611d1c61003060003960006105260152611d1c6000f3fe)

# # Extract cache manager contract address using more precise pattern
# cache_manager_address=$(echo "$cache_deploy_output" | grep "contractAddress" | grep -oE '0x[a-fA-F0-9]{40}')

# if [[ -z "$cache_manager_address" ]]; then
#   echo "Error: Failed to extract Cache Manager contract address. Full output:"
#   echo "$cache_deploy_output"
#   exit 1
# fi

# echo "Cache Manager contract deployed at address: $cache_manager_address"

# Register the deployed Cache Manager contract
# echo "Registering Cache Manager contract as a WASM cache manager..."
# registration_output=$(cast send --private-key "$PRIVATE_KEY" \
#   --rpc-url "$SEPOLIA_RPC_URL" \
#   0x0000000000000000000000000000000000000070 \
#   "addWasmCacheManager(address)" "$cache_manager_address")

# if [[ "$registration_output" == *"error"* ]]; then
#   echo "Failed to register Cache Manager contract. Registration output:"
#   echo "$registration_output"
#   exit 1
# fi
echo "Deploying the Stylus contract using cargo stylus..."
deploy_output=$(cargo stylus deploy -e "$SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" --no-verify 2>&1)

# Check if deployment was successful
if [[ $? -ne 0 ]]; then
    echo "Error: Contract deployment failed"
    echo "Deploy output: $deploy_output"
    exit 1
fi

# Extract deployment transaction hash using more precise pattern
deployment_tx=$(echo "$deploy_output" | grep -i "transaction\|tx" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)

# Extract contract address using more precise pattern
contract_address=$(echo "$deploy_output" | grep -i "contract\|deployed" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)

# If the above patterns don't work, try alternative patterns for cargo stylus output
if [[ -z "$deployment_tx" ]]; then
    deployment_tx=$(echo "$deploy_output" | grep -oE '0x[a-fA-F0-9]{64}' | head -1)
fi

if [[ -z "$contract_address" ]]; then
    contract_address=$(echo "$deploy_output" | grep -oE '0x[a-fA-F0-9]{40}' | head -1)
fi

# Verify extraction was successful
if [[ -z "$deployment_tx" ]]; then
    echo "Error: Could not extract deployment transaction hash from output"
    echo "Deploy output: $deploy_output"
    exit 1
fi

echo "Stylus contract deployed successfully!"
echo "Transaction hash: $deployment_tx"

if [[ ! -z "$contract_address" ]]; then
    echo "Contract address: $contract_address"
fi

############################################
# Generate the ABI for the deployed contract
echo "Generating ABI for the deployed contract..."
cargo stylus export-abi > stylus-contract.abi

# Verify if ABI generation was successful
if [[ $? -ne 0 ]]; then
  echo "Error: ABI generation failed."
  exit 1
fi

echo "ABI generated successfully and saved to stylus-contract.abi"

# Create build directory if it doesn't exist
mkdir -p build

# Save deployment info to JSON file
echo "{
  \"network\": \"arbitrum-sepolia\",
  \"cache_manager_address\": \"$cache_manager_address\",
  \"contract_address\": \"${contract_address:-'N/A'}\",
  \"transaction_hash\": \"$deployment_tx\",
  \"rpc_url\": \"$SEPOLIA_RPC_URL\",
  \"deployment_time\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"
}" > build/stylus-deployment-info.json

echo "Deployment info saved to build/stylus-deployment-info.json"
echo "Deployment completed successfully on Arbitrum Sepolia!" 
