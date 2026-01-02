# Dev Notes (Step 0/1 iteration)

This file records issues, discoveries, and tooling lessons from the first large
TTY-only trimming + build/test iteration (steps 0 and 1 in `plan.md`).

## Summary of what worked

- Out-of-tree **TTY** build on macOS is repeatable via `mise`.
- A tight verification loop exists and is practical during trimming:
  - `mise run trim:check`
  - `mise run verify -- --level check` (and `--force` when needed)
- Removing GUI/toolkit directories (`nextstep/`, `lwlib/`, `oldXMenu/`) is
  workable as long as build glue is updated immediately and tests are run.

## Problems encountered (and lessons)

### 1) Commit-message hooks are strict

- Symptom: commit hooks complain about long lines/words in messages.
- Lesson: ASCII-only, short subject, wrapped body (~72 cols).

### 2) "Full tests" entrypoints can do extra work

- Symptom: running `make -C <build> check` can build docs and other subdirs,
  which is slow and noisy for a trimming verification loop.
- What we did: `mise run test:check` now runs `make -C <build>/test check`
  directly.
- Lesson: prefer narrow, explicit entrypoints for agent loops.

### 3) Native-comp disabling needs bootstrapping-safe stubs

- Symptom: pdump/bootstrap can trip over missing file-local vars such as
  `no-native-compile` / `no-byte-compile`.
- What we did: keep minimal stubs in `lisp/emacs-lisp/comp*.el` plus C-side
  `native-comp-available-p` returning nil.
- Lesson: "remove a feature" often still requires compatibility shims so the
  rest of Emacs loads cleanly.

### 4) Edebug backtrace navigation broke in subtle ways

- Symptoms:
  - `edebug-tests-backtrace-goto-source` originally hit
    `max-lisp-eval-depth` (deep recursion via `edebug-unwrap*`).
  - After limiting unwrapping, the test still failed due to frame indexing
    mismatches in the Edebug backtrace buffer.
- What we did:
  - Stop unwrapping already-evaluated frame args (avoid descending into large
    cyclic structures).
  - Strip leading debugger-internal frames without `:source-available`.
  - Drop the `while` special-form frame (it shifts navigation in a way the
    test suite considers wrong).

### 5) Obsolete `cl` `labels` macro blew the stack under `macroexpand-all`

- Symptom: `test/lisp/obsolete/cl-tests.el` failed with `excessive-lisp-nesting`
  while expanding `labels`.
- What we did: when `lexical-binding` is non-nil, make `labels` delegate to
  `cl-labels` (keep the legacy `lexical-let` path only for old dynamic-scope
  contexts).
- Lesson: prefer the modern, maintained macro implementations when they exist.

### 6) Dynamic module tests segfaulted on macOS

- Symptom: `src/emacs-module-tests.log` crashed reproducibly in
  `mod-test-sleep-until`.
- What we did: configure the TTY build with `--with-modules=no` to keep the
  baseline editor stable while trimming.
- Lesson: when a feature is both out-of-scope and unstable, disable it at
  configure time so the default verification loop stays green.

### 7) Bash `set -u` + empty arrays is a trap

- Symptom: expanding `"${arr[@]}"` when `arr=()` triggers "unbound variable"
  under `set -u`.
- What we did: switch to explicit `if` branches for optional `make -B` flags in
  `.mise/tasks/test/*`.
- Lesson: keep task scripts boring and shell-portable; avoid clever array
  expansions under `-u`.

## Tooling improvements made (now present)

- `mise run trim:check`: grep-based guardrails (removed GUI dirs, native-comp
  probing).
- `mise run verify`: single-command verification loop with `--level` and
  `--force` (forces `-B` for smoke/check).
- `mise run test:smoke -- --force`: forces rebuilding selected smoke logs.
- `mise run test:check -- --force`: forces rebuilding the full default suite.

## Next tooling proposals (not done yet)

1) Add `mise run doctor`
   - Quick sanity checks: required tools present, build dir layout, expected
     invariants (e.g. `(native-comp-available-p)` is nil).

2) Add `mise run clean` / `clobber`
   - Safe cleanup of `build/<name>` with confirm/dry-run.

3) Add doc tasks (`docs:info`, `docs:pdf`)
   - Opt-in and separate from the main build/test loop.

4) Re-enable modules as a tracked milestone
   - Only after we have a reliable debugging path for macOS crashes and a
     reproducible module test runner under `mise`.

## Verification checklist for each trimming change

- `mise run trim:check`
- `mise run verify -- --level check` (use `--force` when you need guaranteed reruns)
