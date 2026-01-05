---
name: clemacs-ert-bringup
description: "Expand upstream ERT bring-up under clemacs safely and monotonically: grow `clemacs/contract/ert-upstream.tests`, manage `ert-upstream.known-fail.tests` with dated reasons (XPASS is a gate failure), and run `clemacs:test:contract --level check` to prevent regressions. Use when adding upstream ERT coverage or fixing regressions in the clemacs ERT must-pass set."
---

# clemacs upstream ERT bring-up

The gate is `mise run clemacs:test:contract -- --level check`.

## Safe expansion protocol (monotonic)

1) Run the current gate:

```sh
mise run clemacs:test:contract -- --level check
```

2) Add tests in small batches to `clemacs/contract/ert-upstream.tests` (must-pass list).

3) Re-run `check`. If a new test fails:
- Prefer fixing the underlying missing primitive/semantics.
- If temporarily unavoidable, move the test to
  `clemacs/contract/ert-upstream.known-fail.tests` with a dated reason.
- Treat XPASS as a gate failure: once fixed, remove from known-fail.

4) Record any semantic discovery:
- Add a microtest (`clemacs/contract/semantics.microtests.sexp`).
- If divergence is intentional, document it in `plans/clemacs-compat.md`.
