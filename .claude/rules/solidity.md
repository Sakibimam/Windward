# Rule — Solidity

Applies to everything in `src/`, `test/`, and `script/`.

## Non-negotiable

1. **Checks-Effects-Interactions, always.** State changes before external calls. If an ordering
   looks like it must be violated, it must not be; restructure.
2. **Custom errors, never string reverts.** `error InsufficientBacking(uint256 claims, uint256 assets);`
   not `require(x, "bad")`. Errors carry the values that make a revert diagnosable.
3. **Every division states its rounding direction and who it favours**, in a comment on the line
   or immediately above:
   ```solidity
   // Rounds DOWN, favouring the protocol: a redeemer never receives more than their share.
   assets = (shares * totalAssets) / totalSupply;
   ```
   Rounding is the failure class this project exists to catch. Unexamined rounding inside the
   guard would be the worst possible bug.
4. **Every `unchecked` block carries explicit overflow reasoning.** State the bound that makes
   overflow impossible, not "this is safe".
5. **No unbounded loops on a swap or liquidity path.** Griefing and gas-limit DoS. If a loop's
   iteration count depends on anything a caller controls, it is unbounded.
6. **Solidity `0.8.26` exactly**, `evm_version = cancun`. Pin the pragma, do not float it
   (`pragma solidity 0.8.26;`, not `^0.8.26`).
7. **No new external call from the guard** beyond reads of the PoolManager and the guarded hook.
   Every external call is a reentrancy edge.

## Guard-specific

- The guard **observes and reverts. It never touches accounting.** Hook callbacks return zero
  deltas. `returnDelta = false`, always. See `SECURITY.md` §1.
- No token transfers, no balance mutations, no state writes the guarded protocol depends on.
- No admin, owner, pause, or upgrade path. A pause on a withdrawal path is a fund-freezing
  switch.
- Any parameter that survives Phase 4 must be `immutable`, set in the constructor.

## Style

- `forge fmt` before commit. Config is in `foundry.toml` (120 cols, 4 spaces, long int types).
- NatSpec on every external and public function: `@notice`, `@param`, `@return`, and `@dev` for
  anything subtle.
- Name the invariant in the code. A reader should find the property, not reconstruct it.
- Prefer explicit over clever. This code is read by an owner who cannot audit it and by
  reviewers under time pressure.

## Assume, always

- Every token is hostile: reentrant, fee-on-transfer, rebasing, missing return value,
  non-18-decimals, reverting on zero-value transfer.
- Every caller is an adversary who can order, repeat, and sandwich their own calls, and can call
  the hook thousands of times in one transaction.
- Every external read can reenter.
