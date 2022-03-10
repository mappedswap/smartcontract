## Centralization

- COT-03 Centralization Related Risks in `PoolCore` and `PoolManagement` (Major)

- COT-04 Centralization Related Risks in Multiple Contracts (Major)

- MST-01 Centralization Related Risks in `MappedSwapToken` (Major)

- SWP-01 Centralization Related Risks in `RaijinSwap` (Major)

---

## Partially Fixed

- COT-05 Function Visibility Optimization (Informational)

Changed visibility of `setManagementContract()` in `PoolCore`

Proxy contracts are already deployed and running so decide not to change

Visibility of functions inherited from `OwnableUpgradeable` cannot be changed

---

## Not the Use Case

- COT-01 Incompatibility With Deflationary Tokens (Informational)

We do not have deflationary tokens when using these contracts

- PAB-02 Missing Input Validation (Minor)

The input are controlled by backend programs

- COT-02 Potential Misalignment between `owner` role and `DEFAULT_ADMIN_ROLE` (Informational)

We must change them at the same time; we do not renounce roles at most of the time

---

## External Dependencies

- MPB-01 Third Party Dependencies on External UniswapV3 Pool (Informational)

- MST-02 Third Party Dependency on Eurus-specific Settings (Informational)

---

## Non Upgradeable Contracts are Deployed and Running

- RSF-01 Unnecessary Array as Counter (Informational)

`allPairsLength()`

- RSP-01 Replace Libraries with Inherited Contract in Contract Template (Informational)

Contracts are deployed to Eurus, which has low gas price

- RSP-02 Missing Sanity Check in `RaijinSwapPair` (Informational)

In this situation the transaction is reverted, which is our expectation

---

## Others

- PAB-01 Potential Sandwich Attacks (Minor)
