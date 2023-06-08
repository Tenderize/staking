# Tenderize Deployments

## Deploy Tenderizer

The Tenderizer Factory and all associated components need to be deployed only once per network by setting the vars in
`.env` and running:

```sh
source env
forge script deploy/1_Tenderizer.s.sol --broadcast --rpc-url $GOERLI_RPC_URL --verify
```

This script will execute following calls:

1. Deploy Registry (without initialization)
   - Deploy `Registry` implementation
   - Deploy `ERC1967` Proxy
2. Deploy `Tenderizer` Implementation
3. Deploy `Unlocks`
   - Deploy `Renderer` Implementation
   - Deploy `Renderer` ERC-1967 UUPS Proxy
   - Deploy `Unlocks`
4. Initialize `Registry` with `Tenderizer` implementation address and `Unlocks` address as arguments
5. Deploy `Factory` with `Registry` address as argument
   - Set `FACTORY_ROLE` on `Registry` for `Factory`

## Deploy New Adapter

We can deploy adapters for each supported protocol on a network using:

```sh
forge script deploy/2_Adapter.s.sol --broadcast --rpc-url $GOERLI_RPC_URL --verify
```

1. Deploy `Adapter` Implementation
2. Set `Adapter` address on `Registry`

TBD.

## Deploy TenderSwap

TBD.

## Deploy Router

TBD.
