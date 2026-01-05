---
name: clemacs-loader-debug
description: "Debug clemacs ELisp loader failures by turning `elisp-load-error` output into an actionable fix: run `clemacs:report:first-failure`, interpret path/form-index/recommended checkpoint, use inventory mapping for missing primitives, bisect unstable checkpoints, and capture loader backtraces. Use when `clemacs:test:startup*` or `clemacs:test:contract --level elisp-core` fails due to ELisp loading."
---

# clemacs loader debug

## Convert failure output into a next action

1) Capture the first failure (and include a backtrace):

```sh
mise run clemacs:report:first-failure -- --mode startup-check --debug
```

2) Read:
- `build/clemacs/reports/first-failure.md` (human)
- `build/clemacs/reports/first-failure.json` (machine)

3) Act on the fields:
- **Path**: which file checkpoint to adjust or port.
- **Form index**: exact top-level form that failed.
- **Recommended checkpoint (max-forms)**: safe checkpoint to set in the startup manifest while fixing.
- **Inventory**: maps missing primitives to `inventory/c-elisp.tsv` source location.

## When checkpoints feel unstable, bisect

```sh
mise run clemacs:bisect:file -- --file lisp/.../foo.el --manifest clemacs/contract/startup.check.files
```

Use the reported max passing checkpoint while implementing the missing piece.

## When to turn on additional debugging

- Use `--debug` on `clemacs:report:first-failure` to populate `build/clemacs/tmp/load-debug.<mode>.out`.
- If you need raw loader output, capture the task log and run:

```sh
mise run clemacs:report:scan-load-log -- --log <path-to-log>
```
