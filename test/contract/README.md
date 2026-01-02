# Test contract (TTY-only fork)

This directory is the source of truth for which test entrypoints are expected
to pass in this fork, and which tests are intentionally skipped due to removed
features (GUI backends, nativecomp, dynamic modules).

Files
- `smoke.logtargets`: must-pass fast suite (used by `mise run test:smoke`)
- `allowed-skip.logtargets`: tests we deliberately do not run (should be small)
- `known-fail.logtargets`: temporary failures we tolerate (should trend to empty)

Usage
- Run must-pass smoke: `mise run test:smoke`
- Run the contract gate: `mise run test:contract -- --level check`

Policy
- Prefer adding to `allowed-skip.logtargets` (with a clear reason) over deleting
  tests to “get green”.
- Keep `known-fail.logtargets` as short-lived as possible.
