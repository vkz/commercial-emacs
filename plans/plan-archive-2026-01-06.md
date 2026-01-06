# Plan archive (2026-01-06)

This file archives completed and superseded plan items from `plan.md` so the
active plan stays short and high-leverage.

## DONE (2026-01-05)

- Fix out-of-tree dump/startup load-path to prefer build-tree `.elc` files (vs source `.el`).
- Make `mise run build` generate shipped snapshot files (`lisp/cus-load.el`, `lisp/finder-inf.el`) when missing.
- Fix `clemacs:report:startup-delta` to resolve pdump load paths to real `lisp/**` files.
- Grow clemacs startup manifests (check/editor-core): add fill/comment/replace/tabulated-list/buff-menu and related TTY bits.
- Raise several startup.check checkpoints (fill, replace, tabulated-list, buff-menu, isearch) and uncap timer/newcomment/fringe/select.
- Add core editor ELisp shims (BOL/EOL motion, indentation, string/window width) and capture behavior in semantics microtests.
- Stub char-script-table and char-table helpers to advance fill.el checkpoint (now loads past the previous char-script-table failure).

## DONE (2026-01-06)

- Bind `text-property-default-nonsticky`, add minimal text property surface (text-properties-at/get/put/add), and uncap fill.el (loads cleanly).
- Add common shims used by fill/comment and keymaps (string-empty-p, prefix-numeric-value, following/preceding-char, char-syntax, invisible-p, left-margin stubs, run-hook-with-args-until-success).
- Fix ELisp append/assoc behavior needed by key parsing during `defvar-keymap` expansion; uncap tabulated-list.el and buff-menu.el in startup manifests.

## DONE (2026-01-06, later)

- Promote the remaining upstream ERT blockers:
  - Buffer name/list hygiene (`rename-buffer`, `kill-buffer`, `buffer-list`) for ERT buffer and help tests.
  - Minimal `emacs-lisp-mode`/`font-lock-mode` handling for indentation-related tests.
  - `*Messages*` truncation semantics (message-log-max) for truncation tests.
  - Preserve string/buffer text properties across `concat`/`substring`/insert/delete-region for ERT explainers.
  - Fix `symbol-file` for `defun` by shadowing ELisp `member` (equal-based) so `load-history` lookup works.
- Expand `startup.check.files` with next TTY-relevant pdump candidates and raise caps:
  - Add `progmodes/elisp-mode.el`, `emacs-lisp/eldoc.el`, `emacs-lisp/cconv.el`, `cus-start.el`, `international/iso-transl.el`, `emacs-lisp/rmc.el` (low caps).
  - Raise `emacs-lisp/lisp-mode.el` to `200` and `progmodes/elisp-mode.el` to `20`.
  - Add missing `cl-progv` + `string-to-char`, and extend `rx` bring-up to support lisp-mode's patterns.
  - Prevent SBCL `CONTROL-STACK-EXHAUSTED` during macroexpansion by restoring clemacs' stack-safe `macroexpand-all` after `macroexp.el` loads.
