# Dev Notes (current)

This file is for *ongoing* notes. The Step 0/1 historical notes are archived in
`plans/dev-001.md`.

## Important consequences of Step 0/1 trimming

- GUI backends are removed (dirs + `src/` backends), so any GUI-only features
  (frames on NS/X11/PGTK, xwidgets, drag-and-drop) are out of scope.
- GUI-only Elisp integration is removed:
  - `lisp/term/*-win.el` (X/NS/PGTK window-system integration)
  - `lisp/x-dnd.el` + `lisp/pgtk-dnd.el`
  - `test/lisp/x-dnd-tests.el` (removed to avoid false negatives)
- Dynamic modules are removed; any future work must not assume `emacs-module.h`
  exists or can be installed.
- `admin/unidata/` is removed; Unicode regeneration is not possible without
  temporarily restoring an equivalent data source.

## Current invariant workflow (agents should use this)

- Guardrails: `mise run trim:check`
- Verification: `mise run verify -- --level check` (use `--force` when needed)
- TTY run: `mise run run`

## Known gotchas

- `src/xwidget.h` must remain (stub inlines when `HAVE_XWIDGETS` is off).
- `lisp/loaddefs.el` is generated/ignored; avoid editing it. Regenerate via the
  normal build/autoload machinery if needed.

## Next dev focus (prep for the SBCL-hosted engine rewrite)

- Add explicit inventory tooling for the C-defined ELisp surface area (see
  `plan.md`).
