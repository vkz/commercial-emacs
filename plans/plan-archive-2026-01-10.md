# plan archive: 2026-01-10

This file archives completed and/or superseded items that were previously in
`plan.md`, trimmed on 2026-01-10 to keep `plan.md` focused on next actions.

Source of truth for "current status" remains:
- `build/clemacs/reports/progress.md` (regenerate via `mise run clemacs:report:progress`)

---

## Recent progress (archived)

- Completed and superseded items are archived in `plans/plan-archive-2026-01-06.md`.
- Upstream ERT bring-up is unblocked and green as of 2026-01-06 (see archive for details).
- `startup.check.files` advanced with next TTY-relevant pdump candidates and higher caps (see archive for details).
- 2026-01-07: added `clemacs:loop:elisp-core` (one-command high-signal loop) and extended the playbook for non-loader failures.
- 2026-01-07: split `clemacs/elisp-compat.lisp` into `clemacs/elisp-compat/*.lisp` modules (thin REPL loader retained); updated loader/compat shims and advanced `startup.check.files` (see `plans/plan-archive-2026-01-07.md`).
- 2026-01-07: raised `startup.check.files` caps for deeper TTY startup loads (`lisp/files.el` 250, `lisp/ls-lisp.el` 600, `lisp/disp-table.el` 800) and unblocked file/path helpers needed by early `lisp/files.el` + `lisp/loaddefs.el`.
- 2026-01-08: brought up more upstream ERT under clemacs (rx/seq) via `clemacs/contract/ert-upstream.load.files` + promoted a small must-pass slice in `clemacs/contract/ert-upstream.tests`.
- 2026-01-08: added `clemacs:test:ert-upstream-one` support for `ert-upstream.load.files` so newly-loaded upstream tests can be triaged individually.
- 2026-01-08: started "real editor core" command routing in `clemacs/tty.lisp` (minimal ELisp-style command loop: keymaps + `read-key-sequence` + `key-binding` + `command-execute`) with bring-up stubs in `clemacs/elisp-compat/55-command-loop.lisp`.
- 2026-01-08: aligned keymap semantics so `keymapp` treats symbols with function-cell keymaps as keymaps; added a focused microtest in `clemacs/contract/semantics.microtests.sexp`.
- 2026-01-08: enabled `\\C-` string escapes in the ELisp reader so shipped keymaps using strings like `"\\C-x"` bind correctly; the clemacs TTY loop now loads a minimal startup set (backquote + subr) by default to use the shipped `global-map`/prefixes.
- 2026-01-08: promoted a few more rx/seq upstream ERT tests (monotonic) after adding keyboard/command-loop bring-up stubs.
- 2026-01-09: implemented high-fanout bring-up shims driven by the elisp-core gate (minibuffer/completion basics, single-window primitives incl. `window-end`, backquote/pcase forward refs, basic file modes/permissions, simple process/call-process-region surface, and sexp/point/key helpers), plus microtests + compat notes to keep the contract green.
- 2026-01-09: implemented a baseline `parse-partial-sexp` + `syntax-ppss` scanner (Emacs-shaped enough for indentation/isearch callers) and uncapped `lisp/emacs-lisp/syntax.el` in the clemacs startup manifests.

## Plan hygiene (archived)

- DONE (2026-01-10): Trimmed `plan.md` to keep the active TODO list short; P0/P1 alpha checklist stays archived here.
- DONE (2026-01-10): Promoted the clemacs alpha try path by default (`clemacs:emacs:run` defaults + `emacs --help`), so testers don't need to discover flags manually.
- DONE (2026-01-10): Defined and gated the "alpha UX" contract via `mise run clemacs:test:tty` (visit/edit/save, M-x, search/replace slice, basic window ops, crash shield).
- DONE (2026-01-10): Autoload/function-designator robustness is "good enough for bring-up" (autoload markers, `funcall` resolution, `indirect-function` escape hatch for keymaps) with supporting microtests.

## Feedback-loop improvements (tooling) (archived)

- DONE (2026-01-10): `clemacs:test:micro` supports `--name` / `CLEMACS_MICROTEST_NAME` to run one semantics microtest (or a small subset by substring).
- DONE (2026-01-10): Batch reference-Emacs comparisons for `:emacs :match` microtests (single Emacs run per microtest run); set `CLEMACS_REFERENCE_EMACS_BATCH=0` to disable.

## Current snapshot (2026-01-10) (archived)

Status is tracked in `build/clemacs/reports/progress.md`. As of 2026-01-10:

- clemacs contract gates are green: `smoke`, `elisp-core`, and `check`.
- Startup manifests:
  - `clemacs/contract/startup.check.files`: entries=100, capped=71, nolimit=27, sum_maxforms=2767
  - `clemacs/contract/startup.editor-core.files`: entries=99, capped=71, nolimit=26, sum_maxforms=2767
- Upstream ERT bring-up: must-pass=201, known-fail=0.

## Next iteration (priority: usable interactive clemacs) (archived)

Goal: `mise run clemacs:tty:run` is a usable terminal editor (open/edit/save/quit, M-x),
and common workflows don't crash (errors are surfaced, not fatal).

Top 10 next tasks (ROI ordered; 1-11 DONE)

1) DONE (2026-01-10): TTY startup manifest (editor slice)
   - Added `clemacs/contract/startup.tty-editor.files` and set the TTY loop default startup
     level to `tty-editor`.
   - Gate: `mise run clemacs:test:tty` is green.

2) DONE (2026-01-10): Stop poisoning shipped keymaps in the TTY loop
   - `clemacs-tty-setup` only installs bring-up keymaps for `CLEMACS_TTY_STARTUP_LEVEL=subr|none`;
     `tty-editor` uses shipped `global-map`/`ctl-x-map` without clobbering.
   - Gate: `mise run clemacs:test:tty` exercises both `subr` and `tty-editor` scenarios and is green.

3) DONE (2026-01-10): "Visit file" vertical slice: `find-file` (C-x C-f)
   - `C-x C-f` works in the `tty-editor` PTY test (visit -> edit -> save).

4) DONE (2026-01-10): "Save file" vertical slice: `save-buffer` (C-x C-s)
   - `C-x C-s` works after visiting a file; PTY test asserts written contents.

5) DONE (2026-01-10): M-x: `execute-extended-command` + completion
   - `M-x save-buffers-kill-terminal` works end-to-end in the PTY test and exits cleanly.

6) DONE (2026-01-10): Minibuffer history (core UX)
   - Implemented `add-to-history` / `history-add-new-input`, plus the minimal minibuffer history
     variables to preserve interactive state.
   - Added M-p/M-n history navigation in the minibuffer local map.
   - Gate: `mise run clemacs:test:tty` demonstrates M-p recalling last minibuffer input.

7) DONE (2026-01-10): Keyboard macro surface (unblocks upstream key/command tests)
   - Implemented `read-key-sequence-vector`, `read-kbd-macro`, `execute-kbd-macro` (minimal).
   - Gate: `mise run clemacs:test:tty` replays a tiny macro without crashing.

8) DONE (2026-01-10): Timing + yielding
   - Implemented `sit-for`/`sleep-for` and tightened `input-pending-p` (TTY-aware; noninteractive stays nil).

9) DONE (2026-01-10): Crash shield / error surfacing in the TTY loop
   - Errors now surface via `message` (shown on the TTY header line) and the loop keeps running.
   - Optional logging: set `CLEMACS_TTY_ERROR_LOG` to append errors to a file.
   - Gate: `mise run clemacs:test:tty` injects an unknown command error and continues.

10) DONE (2026-01-10): Interactive subprocesses (next workflow unlock after M-x)
   - Implemented minimal `make-process`/`start-process` + `delete-process`, plus filter/sentinel plumbing.
   - Gate: `start-process` output lands in the target buffer and matches reference Emacs (microtest).

11) DONE (2026-01-10): Start loading comint/shell (first slice)
   - Added capped `lisp/comint.el` + `lisp/shell.el` to `startup.check`, `startup.editor-core`, and `startup.tty-editor`.
   - Fixed the first fallout in menu/keymap plumbing so early `shell.el` keymap setup can load.

## Next biggest unlocks (archived)

These are high-leverage targets because they remove high-fanout caps
in `clemacs/contract/startup.*.files` and unblock large portions of shipped
editor-core ELisp.

Done (2026-01-09)
- Uncapped `lisp/emacs-lisp/nadvice.el` in `startup.check` and `startup.editor-core` manifests.
- Uncapped `lisp/minibuffer.el` in `startup.check` and `startup.editor-core` manifests.
- Started a buffer-backed minibuffer model (`read-from-minibuffer` populates ` *Minibuf-0*`; `exit-minibuffer`/`delete-minibuffer-contents` are no longer hard errors).
- Baseline syntax scanning: `parse-partial-sexp` + `syntax-ppss` (and uncapped `lisp/emacs-lisp/syntax.el` in `startup.check`/`startup.editor-core`).
- Process/subprocess surface (batch-first): `call-process`, `set-process-plist`, `emacs-pid`, `process-attributes` (plus microtests).
- Raised `lisp/font-lock.el` and `lisp/jit-lock.el` caps to 200 in `startup.check`/`startup.editor-core`.

Done (2026-01-10)
- Command-loop prefix args: add `prefix-arg` plumbing, `unread-command-events` pushback in `read-event`, and minimal `universal-argument`/`digit-argument`/`negative-argument` for the clemacs TTY loop.
- Startup checkpoints: uncap `lisp/keymap.el` and raise `lisp/bindings.el` to max-forms=347 in `startup.check` and `startup.editor-core` manifests (bisected at 348; see `build/clemacs/reports/bisect-lisp_bindings_el.md`).
- Minibuffer input: switch `read-from-minibuffer` from `tty-prompt` to an editable `*Minibuf-0*` buffer (prompt-safe editing, local keymap), with noninteractive defaults and microtests.
- Upstream ERT: promote `test-keymap-parse-macros` (kbd/key-parse cluster).
- DONE (2026-01-10): implement `local-key-binding`/`global-key-binding`, ensure `emacs-lisp-mode` provides a `[menu-bar]` prefix keymap, and load enough of `lisp/help.el` for the `help-command` global binding; promoted `subr-test-{local,global}-key-binding`.
- DONE (2026-01-10): TTY frame/minibuffer shims: dedicated minibuffer window, `window-minibuffer-p`/`minibuffer-window`, and selecting the minibuffer window during `read-from-minibuffer`.
- DONE (2026-01-10): Interactive process plumbing: `make-process`/`start-process`/`delete-process`, filters/sentinels, `process-send-string`/`process-send-eof`, and `accept-process-output`.

1) DONE (2026-01-10): TTY frame/minibuffer window shims (`lisp/frame.el` is already uncapped)
   - Goal is "Emacs-shaped enough for editor-core", not GUI parity.

2) DONE (2026-01-10): Process/subprocess surface (batch-first, then interactive)
   - Batch-first is now in place: `call-process-region` + `call-process`, plus
     minimal process plists and basic `process-attributes`/`emacs-pid`.
   - Interactive process plumbing is now in place: `make-process`/`start-process`,
     `delete-process`, filters/sentinels, and `accept-process-output`.
