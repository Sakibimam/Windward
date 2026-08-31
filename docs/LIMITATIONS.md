# docs/LIMITATIONS.md — the complete list

The README carries the six that most affect how the result should be read. **All ten are here,
verbatim and unabridged.**

## Limitations

1. **Windward is a HEURISTIC, and the word *optimal* does not describe it.** It is a volatility-
   adaptive fee computed from the pool's own tick history, motivated by the loss-versus-rebalancing
   literature — **not** an implementation of any optimal policy from it, and **not** validated as
   improving LP outcomes (`DECISIONS.md` D-0019). The primary artifact is the **measurement
   study**; the hook is the instrument that produced it (D-0018).
2. **The LP benefit is unvalidated.** We measure *fee revenue*, not LP PnL, with no
   demand-elasticity model. `test_sanity_…` proves `10000 > 500` and is **not evidence**.
3. **The replay covers the 5 busiest pools only.** **136,167 swaps across 227 pools (31.9% of
   the window) were never replayed** — and those are the thin, low-activity pools where the
   estimator is least tested. **The thin-pool regime is untested.**
4. **The fee is charged to the trader after the mover.** Property of every reactive dynamic fee.
5. **The estimator conflates transient and permanent price impact.** LVR depends on the
   permanent component.
6. **The tick is steerable.** A funded actor can raise a pool's fee by trading it.
7. **All four hook parameters are underived deployment choices, not results.** `feeMin` (500),
   `feeMax` (10000), `feePerSigma` (200) and `halfLife` (300s) are constructor arguments picked
   by hand. **Nothing in the study derives, fits, or optimises any of them**, and no sensitivity
   analysis was run. They are `immutable`, so a pool that wants different values needs a
   different deployment.
8. **One chain, one 7-day window, one public RPC, a 6,000-transaction sample.** Pool identities
   come from Transfer-log heuristics, not a registry.
9. **C-1 is open.** A same-block round trip can strand the tick anchor and raise the fee an
   honest trader pays. Accepted, not fixed — see Security above.
10. **The lift result is a correlation, not a causal or welfare claim.** It shows the fee is
   charged at the right *times*. It does not show the revenue exceeds the adverse selection it is
   meant to offset. See #2.
