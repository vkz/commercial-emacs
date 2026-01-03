# clemacs compatibility report (living)

This is a living report for the SBCL-hosted clemacs bring-up (Option B1).
It records what is currently supported, what is intentionally different from
upstream Emacs Lisp, and how we expect migration to work.

## Current stance

- clemacs is a **CL-hosted dialect** that aims to run a useful subset of Emacs
  Lisp with mechanical migration where needed.
- CL is the host language and runtime; C exists only as a substrate dylib.
- When in doubt, prefer **explicit, documentable semantics** over historical
  quirks, but keep the surface close enough that porting is straightforward.

## Supported today (2026-01-03)

Reader / syntax
- `[]` vectors read as CL vectors.
- `?x` reads as an integer character code (with a small set of escapes).

Compatibility shims (ELISP package)
- `plist-get`, `plist-put`.
- `setq`:
  - preserves lexical bindings inside `let`,
  - otherwise assigns via `(setf (symbol-value 'x) ...)` to model global `setq`
    and avoid CL undefined-variable warnings.

Runtime
- A minimal TTY loop exists (`clemacs:tty-main`) with:
  - insert/backspace, cursor motion (horizontal + vertical),
  - save/quit chords: `C-x C-s`, `C-x C-c` (legacy `C-s` / `C-q` remain).

## Known differences / missing pieces

- This is not a full Emacs Lisp implementation:
  - no `defun`/`defvar`/dynamic binding model yet,
  - no `symbol-function`/function cells yet,
  - no macroexpander/bytecode compatibility.
- Data model is CL-native; there is no `Lisp_Object` identity to preserve.

## Contract gate (clemacs)

The clemacs contract is separate from upstream Emacs' `test/contract/*`.

- Smoke gate: `mise run clemacs:test:contract -- --level smoke`
- Today this runs:
  - `clemacs:test:smoke` (FiveAM)
  - `clemacs:test:tty` (PTY-driven TTY edit/save/quit)

## ERT strategy (planned)

Goal: run an expanding subset of upstream ERT tests under clemacs, with an
explicit skip list for unsupported features.

Proposed steps:
- Implement enough of `ert.el` (or load it) to run `ert-run-tests-batch`.
- Start with a tiny curated set of upstream tests that require only:
  - reader + basic special forms + lists/vectors/strings,
  - plists + a handful of predicates.
- Add a compatibility report section per test file as it is enabled.
