# Integrating Tenderize **Sei** Native-Asset Multi-Validator LST (tSEI)

> **Audience:** Oracle providers, lending protocol developers, risk teams

Tenderize's multi-validator Liquid Staking Token for **SEI (`tSEI`)** continuously accrues staking rewards and is fully backed by on-chain, non-custodial validator positions managed by the Tenderize Protocol on the Sei Network.  
This guide explains how developers can integrate **tSEI** into their protocols:

1. **Redemption-Rate Oracles** – track the exchange-rate between an LST and its underlying native asset (e.g. `tSEI ⇆ SEI`).  
2. **Lending Protocols** – consume redemption-rate oracles, account for staking yield, and execute liquidations via Tenderize-specific mechanisms or third-party liquidity pools (`unstake`, `withdraw` or `flashUnstake`).

---

## 1. Redemption-Rate Oracles

### 1.1  What is the *redemption rate*?

The redemption rate is the amount of underlying native asset redeemable per 1 unit of LST:

$$R(t) = \frac{\text{Underlying Balance at } t}{\text{tSEI Supply at } t}$$

Because staking rewards are auto-compounded inside Tenderize, `R(t)` increases monotonically.

### 1.2  Why use a redemption-rate oracle?

• Removes reliance on secondary-market prices which can de-peg during stress.  
• Accurately reflects accrued rewards.  
• Enables lending protocols to value LST collateral precisely and trigger liquidations before the position becomes under-collateralized.

### 1.3  Oracle reference implementation

Oracle providers can derive `R(t)` directly from the **MultiValidatorLST** contract:

```solidity
interface IMultiValidatorLST {
    function exchangeRate() external view returns (uint256);
}

contract SeiRedemptionOracle {
    IMultiValidatorLST public immutable tSEI;

    constructor(address _tSEI) {
        tSEI = IMultiValidatorLST(_tSEI);
    }

    // Returns the redemption rate scaled to 1e18 (uSEI per tSEI)
    function latestAnswer() external view returns (uint256) {
        return tSEI.exchangeRate();
    }
}
```

`exchangeRate()` is a `1e18`-scaled fixed-point number representing **underlying SEI per 1 tSEI**.

### 1.4  Recommended parameters

• **Heartbeat:** 15 minutes – LSTs update slowly; more frequent pushes offer diminishing returns.  
• **Deviation threshold:** 0.01% – Redemption rate increments are small but monotonic; flag larger jumps.  
• **Decimals:** 18 – matches underlying native token.

### 1.5  Sei-specific considerations

• **Decimals:** Sei's native token uses **6 decimals** (`1 SEI = 1,000,000 uSEI`). `tSEI` keeps the standard **18 decimals**. The adapter internally scales values by `1e12` when interacting with the precompile.  
• **Validator IDs:** Tenderize represents validators as `bytes32`. The Sei adapter converts these to **bech32** validator addresses (`seivaloper…`) under the hood; integrators never need to supply bech32 manually.  
• **Conversion helpers:** For convenience, the `SeiAdapter` now exposes `validatorStringToBytes32()` and `validatorBytes32ToString()` so external tools can convert between the `seivaloper…` address format and the internal `bytes32` representation if desired.  
• **Unbonding period:** 21 days.

---

## 2. Lending Protocol Integration

### 2.1  Valuing collateral

Use the redemption-rate oracle to convert a user's LST balance to underlying native units, then price via your existing native-asset oracle.

\[
\text{Collateral Value} = R(t) \times P_{\text{native}}
\]

Where `P_native` is the USD price of the native asset.

### 2.2  Accounting for staking yield

Because `R(t)` grows, collateral value increases automatically.  
No additional accounting is required from the protocol side.

### 2.3  Liquidation workflow

When a borrower falls below the liquidation threshold, governors may choose between four execution paths:

1. **Unstake & Wait (gas-efficient)**  
   • Call `unstake(shares, minAmount)` on the `tSEI` contract. The tx returns an `unstakeID`.  
   • After the 21-day Sei unbonding period, call `withdraw(unstakeID)` to receive SEI.  

2. **Immediate withdraw (if mature)**  
   If 21 days have already passed, go straight to `withdraw(unstakeID)` and seize the SEI.

3. **Instant exit via Flash Unstake (`FlashUnstakeNative`)**  
   Use the helper at ``FlashUnstakeNative.flashUnstake(...)` to unwrap the validator positions and swap into SEI within a single transaction. This uses TenderSwap underneath, the amount received depends on the available liquidity:

   ```solidity
   FlashUnstake(0xFlashUnstake).flashUnstake(
       0xtSEI,        // tSEI token address
       0xTenderSwap,  // TenderSwap pool that holds SEI liquidity
       tseiAmount,    // amount of tSEI to liquidate
       minSeiOut      // slippage guard
   );
   ```

4. **Sell on DEX**  
   If sufficient secondary-market liquidity exists, liquidators can simply swap `tSEI → SEI` on a DEX.

Liquidators can choose between these paths based on gas costs, urgency, and liquidity conditions.

---

## 3. Contract Addresses (Mainnet)

| Asset | tToken | Flash Unstake contract | Oracle feed |
|-------|--------|------------------------|-------------|
| SEI   | `0xtSEI` | `0xFlashUnstake` | `TBD` |
| ETH   | `0x…` | `0x…` | TBD (Chainlink feed) |
| MATIC | `0x…` | `0x…` | TBD |
| …     | | | |

> 📌  **Note:** Addresses will be finalized after audit and mainnet deployment. Follow [Tenderize deployments](../deployments.md) for updates.

---

## 4. Monitoring Tips

• **Validator Slashing:** Slashing is socialized across the stake set; the redemption rate can **decrease**. Keep a guard-rail that halts borrowing if the oracle ever reports a negative delta.  
• **Oracle Staleness:** Set a circuit-breaker if the feed is older than your chosen heartbeat interval.

---

## 5. FAQ

**Q:** *Why redemption rate rather than price oracle?*  
**A:** Redemption rate is deterministic, resistant to manipulation, and aligns with underlying yield.

**Q:** *Yield-bearing interest conflicts with lending interest?*  
**A:** LST yield is implicit in collateral value growth. Lending interest rates can be set independently (similar to cTokens accruing interest on supplied assets).
