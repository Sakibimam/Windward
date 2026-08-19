# CHANGELOG — Keel

Human-readable evolution of the project. The technical decision log is `DECISIONS.md`.

## [Unreleased]

### 2026-08-28 — Phase 0: bootstrap (sessions 1 and 2)

Project scaffolded, environment verified, and durable memory established. No protocol code
written yet — by design.

**Verified the ground we are standing on.** Recorded the Claude Code environment and its exact
configuration syntax from current documentation rather than from memory; captured the toolchain
versions; confirmed a working Unichain RPC endpoint that also serves historical state, which
makes a fork-based reproduction plausible later without a paid provider.

**Resolved dependencies properly.** Rather than taking the newest release of each library, we
pinned v4-core to the exact commit v4-periphery was actually built against, and pinned
forge-std, solmate, and OpenZeppelin to v4-core's own choices. Mixing versions that were never
tested together is a classic source of subtle breakage. A throwaway "canary" contract proves the
whole set compiles and runs together.

**Found two things that would have hurt later.** A commit hash in the evidence file had been
mistranscribed, and the pins recorded in git did not match the pins actually resolved — a fresh
clone would have built something different from what we verified. Both are fixed and both are
written down as incidents, because the lesson matters more than the fix.

**Wrote down what we already know we will not build.** Two earlier versions of this project were
rejected on their merits; the reasoning is recorded so no future session wastes time
rediscovering it. What survives is a deliberately narrow idea: a runtime backing check for the
small class of v4 hooks that issue share-like claims.

**Set up guardrails.** Permissions, hooks, coding rules, and four review subagents — including
one whose only job is to argue the project should be killed. The reviewers deliberately cannot
edit code: a reviewer that can make its own findings disappear is not a review.

**Status:** Phase 0 complete, awaiting approval to begin Phase 1. The core thesis is still an
untested hypothesis, and Phases 2–4 are explicitly allowed to kill it.
