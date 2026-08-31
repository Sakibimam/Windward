# CHANGELOG — Windward

Human-readable evolution of the project. The technical decision log is `DECISIONS.md`.

## [Unreleased]

### 2026-08-29 — Deployed to Unichain Sepolia

`WindwardHook` is live on Unichain Sepolia (chain 1301) at
`0x7FEe02329eEc22dADEd64642B9ED47cE9b5110c0`, transaction
`0x7666c778926c9dcd2ecf7fd9161be97e56b0c36df5d49c1b7e8130f50d2dfc2c`, block 61165939.

The address was mined so its low 14 bits encode exactly the permissions the hook declares —
in Uniswap v4 the address *is* the permission set, and the constructor refuses to deploy at an
address that disagrees with it. All four returns-delta bits are clear, so the protocol itself
prevents this hook from moving funds; it can only price them.

Read back from the chain afterwards: 5,517 bytes of code, the right PoolManager, the same fee
parameters the study used, and no owner, pause, upgrade path or setter.

Testnet only, unaudited, and no pool has been created against it yet. Evidence in
`docs/DEPLOYMENT.md`; decision and preflight findings in `DECISIONS.md` D-0021.

### 2026-08-28 — Bootstrap

Project scaffolded and environment verified. No protocol code written yet — by design.

**Verified the ground we were standing on.** Recorded the toolchain versions and confirmed a
working Unichain RPC endpoint that also serves historical state, which makes a fork-based
reproduction plausible later without a paid provider. Every API fact was read from source on
disk or from current documentation rather than from memory.

**Resolved dependencies properly.** Rather than taking the newest release of each library, we
pinned v4-core to the exact commit v4-periphery was actually built against, and pinned
forge-std, solmate, and OpenZeppelin to v4-core's own choices. Mixing versions that were never
tested together is a classic source of subtle breakage. A throwaway "canary" contract proves the
whole set compiles and runs together.

**Found two things that would have hurt later.** A commit hash in the evidence file had been
mistranscribed, and the pins recorded in git did not match the pins actually resolved — a fresh
clone would have built something different from what we verified. Both are fixed and both are
written down as incidents (`DECISIONS.md` D-0009, D-0010), because the lesson matters more than
the fix.

**Wrote down what we already knew we would not build.** Two earlier versions of this project
were rejected on their merits and the reasoning recorded, so the ground would not be re-covered.

**Set up guardrails.** Coding rules, a pre-release checklist, and a standing review process in
which one review's only brief is to argue the project should be abandoned. Reviews are
read-only: a review that can edit the code can make its own findings disappear.
