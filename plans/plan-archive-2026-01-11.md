# Plan archive — 2026-01-11

This file records DONE work since `plans/plan-archive-2026-01-10.md`, so we
don’t keep rediscovering the same fixes during clemacs bring-up.

## DONE (2026-01-11)

### Upstream ERT bring-up: `cl-generic` cluster

- Promoted the upstream `test/lisp/emacs-lisp/cl-generic-tests.el` suite into
  the clemacs must-pass list: `clemacs/contract/ert-upstream.tests`.
- Made the upstream ERT harness load extra ELisp files via
  `clemacs/contract/ert-upstream.load.files`, using `elisp:load-elisp-manifest`
  so `clemacs/ported/` overrides win and `load-path` is sane.
- Implemented a minimal set of compat shims required by the cl-generic tests:
  - `length>`/`length<`/`length=` (needed by `cl--map-methods-documentation`).
  - `apply` “single list arg” extension: `(apply (list FN ARG...))`.
  - `find-lisp-object-file-name` stub (describe-function integration; safe nil).
  - `gv-deref` `setf` support for host CL `setf` (via a `define-setf-expander`).
  - `defalias` bridging for gv’s `"(setf foo)"` naming into CL’s `(setf foo)`.
  - `defun-declarations-alist` plumbing for
    `advertised-calling-convention` declarations during bring-up.
  - Help/doc stubs sufficient for `cl--generic-describe` output.
- Fixed a batch-only cl-generic failure mode:
  - `fmakunbound` must clear clemacs’s internal function-cell table so `fboundp`
    reflects the unbound state and `cl-generic-define` correctly throws away
    previous methods/dispatches.

### Smoke gate made fast again

- Decoupled the full ELisp semantics microtest corpus from `clemacs:test:smoke`
  by making the `clemacs-micro` suite independent (instead of nested under the
  smoke suite).
  - Run the full corpus explicitly via `mise run clemacs:test:micro`.
  - Keep `mise run clemacs:test:smoke` representative and fast (CL-level +
    a small ELisp bring-up slice).

## Breadcrumbs added

- `clemacs/contract/semantics.microtests.sexp`:
  - Added microtests covering `(apply (list ...))` and `length>`/`length<`/`length=`.

## Verification

- `mise run clemacs:test:contract -- --level check`
- `mise run clemacs:test:micro -- --name sequences-length`

## Notes / stance reminders

- UTF-8 only: legacy encodings/LEIM must not block clemacs milestones.
