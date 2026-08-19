# Rule — Research and evidence

## Tag every substantive claim

| Tag | Meaning |
|---|---|
| `FACT` | Verified **this session**: source on disk, a live query, or official documentation. Record the source and date. |
| `INFERENCE` | Reasoned from verified evidence. State the reasoning so it can be attacked. |
| `HYPOTHESIS` | Currently being tested. Not yet evidence for anything. |
| `UNVERIFIED` | Not checked. **May not be relied on.** |

**Never silently promote a tag.** Moving `UNVERIFIED` → `FACT` requires new evidence recorded at
the same time.

## The verification rule

> Never write an API call, import path, function signature, struct field, version number, commit
> hash, or contract address you have not verified this session.

Training data is stale. Two failures already caught by this rule, both recorded in
`docs/RECON.md` §6: `SwapParams` moved to `types/PoolOperation.sol`, and `BaseHook.sol` does not
exist in v4-periphery at our pin — the import every tutorial suggests is simply wrong here.

**When you cannot verify something, write `UNVERIFIED` and stop.** Stopping is correct
behaviour. Guessing is the worst available outcome, because the product owner will not catch it.

## Recording evidence

- Cite **file path and line number** for anything read from source, at the pinned commit.
- Cite **URL and date** for anything read from documentation.
- **Never hand-transcribe command output.** Redirect it to the file. A block labelled "verbatim"
  that is not verbatim has already happened once here (`DECISIONS.md` D-0009).
- **Verify that a verified fact was actually persisted.** A correct fact in a file that a future
  session will not inherit is worth nothing (`DECISIONS.md` D-0010).
- Two independent sources for anything that will be deployed against — an address read from
  documentation must also be confirmed on-chain.

## Where things live

`CURRENT_STATE.md` → `DECISIONS.md` → `RESEARCH.md` → this conversation (**last**).

The repository is the source of truth. The conversation is not. A future session must be able to
reconstruct the project from the repo alone.
