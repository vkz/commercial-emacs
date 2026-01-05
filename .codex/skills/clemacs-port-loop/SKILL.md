---
name: clemacs-port-loop
description: "Run the standard clemacs bring-up loop (SBCL-hosted Emacs Lisp): run the constant contract gate, interpret first-failure reports, adjust startup manifest checkpoints, implement missing primitives/shims, and leave required breadcrumbs. Use when working on clemacs port iterations, raising `startup.*.files` checkpoints, or unblocking shipped `lisp/` loads under clemacs."
---

# clemacs port loop

Follow `plans/agent-playbook.md` as the source of truth. Use this skill as the
“do the next right thing” loop when you’re actively moving checkpoints/tests.

## Quick start

1) Run the constant gate:

```sh
mise run clemacs:test:contract -- --level elisp-core
```

2) If it fails, extract the first actionable failure (and capture debug backtrace):

```sh
mise run clemacs:report:first-failure -- --mode startup-check --debug
```

3) Apply the fix, leave breadcrumbs, repeat.

## Breadcrumb rules (do these in the same patch)

- Semantics change: update `clemacs/contract/semantics.microtests.sexp`.
- Intentional divergence: add dated rationale to `plans/clemacs-compat.md`.
- Startup changes: update `clemacs/contract/startup.*.files` monotonically.
- Upstream ERT bring-up changes: update `clemacs/contract/ert-upstream.tests` /
  `clemacs/contract/ert-upstream.known-fail.tests` monotonically.

## Output artifacts (attach these in reports/PRs)

- `build/clemacs/reports/first-failure.md`
- `build/clemacs/reports/progress.md`
- `build/clemacs/reports/bisect-*.md` (if you bisected)
