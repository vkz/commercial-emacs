# Plan archive (2026-01-07)

This file archives completed and superseded plan items from `plan.md` so the
active plan stays short and high-leverage.

## DONE (2026-01-07)

- Add a one-command high-signal loop: `mise run clemacs:loop:elisp-core` (runs elisp-core gate; on failure generates the startup-check first-failure report).
- Extend `plans/agent-playbook.md` with a non-loader failure section (SBCL stack exhaustion/type errors/read errors) and cap-raise defaults (larger jumps + bisection when unclear).
- Split `clemacs/elisp-compat.lisp` into `clemacs/elisp-compat/*.lisp` domain modules to improve navigation and reduce incremental rebuild surface (thin REPL loader retained at `clemacs/elisp-compat.lisp`).
- Fix macroexpansion-time semantics for `eval-when-compile` / `eval-and-compile` (match Emacs `byte-run.el`) and capture behavior in `clemacs/contract/semantics.microtests.sexp`.
- Unblock `startup.check` bring-up by implementing missing file/load primitives used by `loaddefs.el` / `subr.el`:
  - `get-load-suffixes`, `locate-file`, and an ELisp `load` shim (shadowing `cl:load` in the `ELISP` package).
- Advance `clemacs/contract/startup.check.files` caps (TTY-relevant only):
  - `lisp/loaddefs.el` → 3100
  - `lisp/emacs-lisp/seq.el` → 800
  - `lisp/disp-table.el` → 250
- Add a pragmatic skip entry for `lisp/international/ucs-normalize.el` in `clemacs/contract/lisp.allowed-skip.files` (too compile-time heavy for source-loading during bring-up; revisit once Unicode/translation infra is ready).
- Work around upstream ELisp symbols containing `:` (e.g. `GUI:bottom`) by defining a stub `GUI` CL package in `clemacs/package.lisp` (pragmatic reader hack during bring-up).
