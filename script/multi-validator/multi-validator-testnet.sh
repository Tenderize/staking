#!/bin/bash
set -x
pkill -9 anvil
nohup bash -c "anvil --fork-url https://arb-mainnet.alchemyapi.io/v2/ISHp9nyZwKlfoSfS3-Hv-05CRiklcRBt --hardfork shanghai --chain-id 5000 --block-base-fee-per-gas 0 &" >/dev/null 2>&1 && sleep 5

forge build

curl -H "Content-Type: application/json" -X POST --data '{"jsonrpc":"2.0","id":67,"method":"anvil_setCode","params": ["0x4e59b44847b379578588920ca78fbf26c0b4956c","0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"]}' 127.0.0.1:8545

export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

forge script script/MultiValidatorLST.s.sol:MultiValidatorLST_Deploy --rpc-url http://127.0.0.1:8545 --broadcast -vvv

LPT=0x289ba1701C2F088cf0faf8B3705246331cB8A839
MINTER=0xc20DE37170B45774e6CD3d2304017fc962f27252
AMOUNT=100000000000000000000000
ME=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
cast rpc anvil_impersonateAccount $MINTER
cast send $LPT --from $MINTER "transfer(address,uint256)(bool)" $ME $AMOUNT --unlocked

# init round
cast send 0xdd6f56DcC28D3F5f27084381fE8Df634985cc39f --from $ME "initializeRound()" --unlocked

read -r -d '' _ </dev/tty
echo "Closing Down Anvil"
pkill -9 anvil