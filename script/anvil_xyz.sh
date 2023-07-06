#!/bin/bash
set -x
nohup bash -c "anvil &" >/dev/null 2>&1 && sleep 5

forge build

curl -H "Content-Type: application/json" -X POST --data '{"jsonrpc":"2.0","id":67,"method":"anvil_setCode","params": ["0x4e59b44847b379578588920ca78fbf26c0b4956c","0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"]}' 127.0.0.1:8545

export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export REGISTRY=0x296dB3C224c7f3104f22Be3D4c1FBfFdE4A4431B
export FACTORY=0x4eF71bD00395C447A43dB077Abe05f0C7910B3A8

forge script script/Tenderize_Deploy.s.sol:Tenderize_Deploy --fork-url http://127.0.0.1:8545 --broadcast --private-key $PRIVATE_KEY

forge script script/XYZ_Deploy.s.sol:XYZ_Deploy --fork-url http://127.0.0.1:8545 --broadcast --private-key $PRIVATE_KEY

read -r -d '' _ </dev/tty
echo "Closing Down Anvil"
pkill -9 anvil