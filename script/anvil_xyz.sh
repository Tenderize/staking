#!/bin/bash
set -x
nohup bash -c "anvil --chain-id 1337 &" >/dev/null 2>&1 && sleep 5

forge build

curl -H "Content-Type: application/json" -X POST --data '{"jsonrpc":"2.0","id":67,"method":"anvil_setCode","params": ["0x4e59b44847b379578588920ca78fbf26c0b4956c","0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"]}' 127.0.0.1:8545

export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export REGISTRY=0x8A89ee359EF0C92e3A8c3af11d1D675d3DF16B2f
export FACTORY=0x3cB1E8d050E126bBE05782c7206Cf53856FDaA77

forge script script/Tenderize_Deploy.s.sol:Tenderize_Deploy --fork-url http://127.0.0.1:8545 --broadcast --private-key $PRIVATE_KEY -vvvv


# Deploy Livepeer
# Parameters
export NAME="Livepeer"
export SYMBOL="LPT"
export BASE_APR="280000"
export UNLOCK_TIME="604800"
export TOTAL_SUPPLY="30000000000000000000000000"
export ID=0
forge script script/XYZ_Deploy.s.sol:XYZ_Deploy --fork-url http://127.0.0.1:8545 --broadcast --private-key $PRIVATE_KEY -vvvv

# Deploy Graph 
export NAME="The Graph"
export SYMBOL="GRT"
export BASE_APR="170000"
export UNLOCK_TIME="2419200"
export TOTAL_SUPPLY="10000000000000000000000000000"
export ID=1
forge script script/XYZ_Deploy.s.sol:XYZ_Deploy --fork-url http://127.0.0.1:8545 --broadcast --private-key $PRIVATE_KEY -vvvv

# Deploy Polygon 
export NAME="Polygon"
export SYMBOL="POL"
export BASE_APR="110000"
export UNLOCK_TIME="201600"
export TOTAL_SUPPLY="10000000000000000000000000000"
export ID=2
forge script script/XYZ_Deploy.s.sol:XYZ_Deploy --fork-url http://127.0.0.1:8545 --broadcast --private-key $PRIVATE_KEY -vvvv


read -r -d '' _ </dev/tty
echo "Closing Down Anvil"
pkill -9 anvil