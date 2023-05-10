## Deploy

### Tenderizer Factory

The Tenderizer Factory and all associated components need to be deployed only once per network by setting the vars in
`.env` and running:

```
source env
forge script deploy/1_Tenderizer.s.sol --broadcast --rpc-url $GOERLI_RPC_URL --verify
```

### Adpaters

We can deploy adapters for each integration on the network using:

```
forge script deploy/2_Adapter.s.sol --broadcast --rpc-url $GOERLI_RPC_URL --verify --sig "run(address,string,address)" <REGISTRY>
<NAME{Graph,Livepeer}> <UNDERYLING_TOKEN>
```

Note: when a new adapter is added, the deploy script has to be modified to include the new adapter.
