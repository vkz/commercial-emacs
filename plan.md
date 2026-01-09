# clmacs Plan — TTY-only Emacs + SBCL-hosted Emacs Lisp

This project is a fork of a fork. The current direction is:

- Keep **TTY-only** Emacs as the runtime target.
- Rewrite the **Emacs Lisp engine** so Emacs Lisp is implemented **inside Common Lisp (SBCL)**,
  with an internal "unquote" escape to the SBCL host.
- Keep GUI code only insofar as it is shared/common infrastructure or valuable reference we can
  always recover from Git history.
- Tree-sitter and moving-GC work from upstream forks are out of scope for now.

## Where to start

Read these in order:

- `AGENTS.md` (repo invariants, workflows, gotchas)
- `plan.md` (this file: current TODOs)
- `plans/clemacs.md` (Option B architecture and branch decisions)
- `plans/agent-playbook.md` (operational bring-up runbook)

Onboarding command:

- `mise run clemacs:loop:elisp-core && mise run clemacs:report:progress`

## Dev setup

Dev bring-up is standardized around:

- `plans/agent-playbook.md`
- Repo-local agent skills under `.codex/skills/`

Archive: the original checklist is preserved in `plans/dev-002.md`.

## Invariants (hard constraints)

These are intentional and should be treated as invariants until the project direction changes:

- GUI backends are removed (`nextstep/`, `lwlib/`, `oldXMenu/`, and `src/` NS/X11/PGTK backends).
- GUI-only Elisp integration is removed:
  - `lisp/term/common-win.el`, `lisp/term/x-win.el`, `lisp/term/ns-win.el`, `lisp/term/pgtk-win.el`
  - `lisp/x-dnd.el`, `lisp/pgtk-dnd.el`, and `test/lisp/x-dnd-tests.el`
- Dynamic modules are removed.
- Native compilation (libgccjit / `.eln`) is removed/disabled.

Baseline acceptance criteria (C-hosted TTY Emacs)

- `mise run build` produces working `emacs` and `emacsclient`.
- `mise run run` starts Emacs in a terminal as a normal editor.
- `mise run test:smoke` and `mise run test:check` pass.
- `mise run verify -- --level check` is the one-command gate.

## Recent progress

- Completed and superseded items are archived in `plans/plan-archive-2026-01-06.md`.
- Upstream ERT bring-up is unblocked and green as of 2026-01-06 (see archive for details).
- `startup.check.files` advanced with next TTY-relevant pdump candidates and higher caps (see archive for details).
- 2026-01-07: added `clemacs:loop:elisp-core` (one-command high-signal loop) and extended the playbook for non-loader failures.
- 2026-01-07: split `clemacs/elisp-compat.lisp` into `clemacs/elisp-compat/*.lisp` modules (thin REPL loader retained); updated loader/compat shims and advanced `startup.check.files` (see `plans/plan-archive-2026-01-07.md`).
- 2026-01-07: raised `startup.check.files` caps for deeper TTY startup loads (`lisp/files.el` 250, `lisp/ls-lisp.el` 600, `lisp/disp-table.el` 800) and unblocked file/path helpers needed by early `lisp/files.el` + `lisp/loaddefs.el`.
- 2026-01-08: brought up more upstream ERT under clemacs (rx/seq) via `clemacs/contract/ert-upstream.load.files` + promoted a small must-pass slice in `clemacs/contract/ert-upstream.tests`.
- 2026-01-08: added `clemacs:test:ert-upstream-one` support for `ert-upstream.load.files` so newly-loaded upstream tests can be triaged individually.
- 2026-01-08: started “real editor core” command routing in `clemacs/tty.lisp` (minimal ELisp-style command loop: keymaps + `read-key-sequence` + `key-binding` + `command-execute`) with bring-up stubs in `clemacs/elisp-compat/55-command-loop.lisp`.
- 2026-01-08: aligned keymap semantics so `keymapp` treats symbols with function-cell keymaps as keymaps; added a focused microtest in `clemacs/contract/semantics.microtests.sexp`.
- 2026-01-08: enabled `\\C-` string escapes in the ELisp reader so shipped keymaps using strings like `\"\\C-x\"` bind correctly; the clemacs TTY loop now loads a minimal startup set (backquote + subr) by default to use the shipped `global-map`/prefixes.
- 2026-01-08: promoted a few more rx/seq upstream ERT tests (monotonic) after adding keyboard/command-loop bring-up stubs.
- 2026-01-09: implemented high-fanout bring-up shims driven by the elisp-core gate (minibuffer/completion basics, single-window primitives incl. `window-end`, backquote/pcase forward refs, basic file modes/permissions, simple process/call-process-region surface, and sexp/point/key helpers), plus microtests + compat notes to keep the contract green.
- 2026-01-09: implemented a baseline `parse-partial-sexp` + `syntax-ppss` scanner (Emacs-shaped enough for indentation/isearch callers) and uncapped `lisp/emacs-lisp/syntax.el` in the clemacs startup manifests.

## Current work (end goal: shipped ELisp runs under clemacs)

We drive the remaining work with three synced loops:

1) Inventory: use `inventory/*` as the authoritative checklist of primitives.
2) Load: attempt to load more of `lisp/` under clemacs, recording missing pieces.
3) Tests: run increasingly large upstream ERT suites under clemacs with explicit skip lists.

Decision checkpoint (must ask the user)
- If/when we hit a point where clemacs must diverge from upstream ELisp syntax or semantics beyond
  mechanical rewrites, stop and ask for an explicit decision with concrete examples and tradeoffs.

## Milestones (TODO)

## Current snapshot (2026-01-09)

Status is tracked in `build/clemacs/reports/progress.md`. As of 2026-01-09:

- clemacs contract gates are green: `smoke`, `elisp-core`, and `check`.
- Startup manifests:
  - `clemacs/contract/startup.check.files`: entries=100, capped=76, nolimit=22, sum_maxforms=2705
  - `clemacs/contract/startup.editor-core.files`: entries=99, capped=76, nolimit=21, sum_maxforms=2895
- Upstream ERT bring-up: must-pass=198, known-fail=0.

## Next biggest unlocks (priority order)

These are the next high-leverage targets because they remove high-fanout caps
in `clemacs/contract/startup.*.files` and unblock large portions of shipped
editor-core ELisp.

Done (2026-01-09)
- Uncapped `lisp/emacs-lisp/nadvice.el` in `startup.check` and `startup.editor-core` manifests.
- Uncapped `lisp/minibuffer.el` in `startup.check` and `startup.editor-core` manifests.
- Started a buffer-backed minibuffer model (`read-from-minibuffer` populates ` *Minibuf-0*`; `exit-minibuffer`/`delete-minibuffer-contents` are no longer hard errors).
- Baseline syntax scanning: `parse-partial-sexp` + `syntax-ppss` (and uncapped `lisp/emacs-lisp/syntax.el` in `startup.check`/`startup.editor-core`).
- Process/subprocess surface (batch-first): `call-process`, `set-process-plist`, `emacs-pid`, `process-attributes` (plus microtests).
- Raised `lisp/font-lock.el` and `lisp/jit-lock.el` caps to 200 in `startup.check`/`startup.editor-core`.

1) Uncap `lisp/frame.el` (currently max-forms=200)
   - Provide a minimal TTY frame model and core accessors like
     `frame-parameter`, `minibuffer-window`, and `minibuffer-prompt-end`.
   - Goal is "Emacs-shaped enough for editor-core", not GUI parity.

2) Process/subprocess surface (batch-first, then interactive)
   - Batch-first is now in place: `call-process-region` + `call-process`, plus
     minimal process plists and basic `process-attributes`/`emacs-pid`.
   - Next: interactive process plumbing (`make-process`/`start-process`),
     `delete-process`, filters/sentinels, and richer `process-attributes` keys
     as needed by real editor workflows.

### Milestone B1-8: load the shipped `lisp/` tree under clemacs

Deliverables
- A deterministic clemacs loader that can load (most of) `lisp/` from this repo.
- A mechanical rewrite path for cases where we intentionally diverge from upstream ELisp.

Gate
- `mise run clemacs:load:lisp -- --level smoke` loads an explicit list of ELisp files and exits 0.
- The list is data in-repo and grows monotonically (no deleting to get green).

High priority (next ROI)
- Autoload/function-designator robustness: make core helpers accept autoload markers and treat them as callable/inspectable where Emacs does (still high-fanout via `cl-generic`, `bytecomp`, and help/arglist paths).
- Interactive command pipeline: implement `commandp`, `interactive-form`, `call-interactively`, prefix-arg + command history plumbing (unblocks real editor usage and a lot of `simple.el`/minibuffer code paths).
- Minimal TTY frame/window/minibuffer shims: enough of `frame-parameter`, `minibuffer-window`, `minibuffer-prompt-end`, plus staples like `switch-to-buffer`, `buffer-file-name`, `move-to-column` (high fanout in editor-core startup).
- Minibuffer/completion basics: now have `minibuffer-depth`, a minimal `completing-read`, and a buffer-backed minibuffer state; next is an editable minibuffer buffer (keymaps + cursor motion + in-buffer edits) rather than the current line-prompt input.
- Window/buffer motion basics: now have `window-point`/`window-height`/`window-start`/`window-end` + a single-window model; next is enough window-state APIs for `frame.el`/display paths and more accurate window-end/window-start semantics under scrolling.
- Process/subprocess surface: now have a minimal `process-buffer`/`get-buffer-process`, `call-process-region` + `call-process`, and basic process plists/attrs (`set-process-plist`, `process-attributes`, `emacs-pid`); next is interactive processes (`make-process`/`start-process`), `delete-process`, and filter/sentinel plumbing.
- Syntax/parse-state core: baseline `parse-partial-sexp` + `syntax-ppss` is in place, and `font-lock.el`/`jit-lock.el` caps are raised; next is addressing the missing primitives those loads expose.

Next actions
- Grow `clemacs/contract/startup.{smoke,check,editor-core}.files` monotonically, following pdump order.
- For `startup.check.files`, only add TTY-relevant candidates (ignore GUI/W32 files) and raise caps gradually.
- Default cap strategy: take bigger jumps and bisect early (rule of thumb: `lisp/loaddefs.el` +1000; most other files +300–800; if the failure location is unclear, bisect immediately: `mise run clemacs:bisect:file -- --file <lisp/.../foo.el> --manifest clemacs/contract/startup.check.files`).
- After each bump: run `mise run clemacs:test:contract -- --level elisp-core`.
- On failure: run `mise run clemacs:report:first-failure-startup-check-debug` and implement the single top offender before moving on.

### Milestone B1-9: run upstream ERT suites under clemacs

Deliverables
- Run a meaningful subset of upstream ERT tests shipped in this repo under clemacs.
- Explicit contract data for must-pass / allowed-skip / known-fail.

Gate
- `mise run clemacs:test:contract -- --level check` fails on regressions.

Next actions
- Expand `clemacs/contract/ert-upstream.tests` monotonically (keep the suite green; use ERT promotions opportunistically when they unblock startup work).
- Keep `clemacs/contract/ert-upstream.known-fail.tests` dated and explicit (XPASS is a gate failure).
- Promote a few more rx/seq tests (monotonic), then begin loading/promoting the first keyboard/keymap-related upstream tests once the command-loop/keyboard stubs exist.

### Milestone B1-12: inventory closure for `startup.check`

Deliverables
- All C-defined primitives referenced by `clemacs/contract/startup.check.files` are either:
  - implemented (prefer shims in `clemacs/elisp-compat.lisp`), or
  - explicitly recorded as an intentional semantic divergence.

Gate
- `mise run clemacs:test:contract -- --level elisp-core` stays green while raising checkpoints.

Next actions
- Use inventory deltas to implement primitives in clusters (next likely: help buffers, file-name helpers, process stubs).
- Treat each new startup failure as an inventory item: implement/stub and add breadcrumbs (microtests, compat notes, contract updates) in the same patch.

### Milestone B1-14: clemacs "real editor core" boot

Deliverables
- `mise run run:clemacs` starts an interactive editor loop that:
  - loads a curated startup manifest,
  - can open a file, edit, save, quit,
  - and can evaluate ELisp in-process (initially for tests/tooling).

Acceptance criteria (promotion gate)
- Promote clemacs to `mise run run` only when `run:clemacs` is a usable terminal editor and exits cleanly.

Next actions (high-leverage)
- Switch the clemacs TTY loop from the bring-up keymap to shipped `current-global-map` by loading a curated startup manifest during TTY startup (default `CLEMACS_TTY_STARTUP_LEVEL=smoke`), with an option to keep the minimal bring-up startup (`CLEMACS_TTY_STARTUP_LEVEL=subr`) while debugging.
- Add minimal keyboard/command-loop stubs needed by shipped ELisp and upstream ERT loads (e.g. `key-parse`, `this-single-command-keys`, event symbol parsing/modifiers), keeping behavior intentionally small but Emacs-shaped.

## Archive

- `plans/plan-001.md` (Step 0/1 plan snapshot)
- `plans/dev-001.md` (Step 0/1 dev-notes snapshot)
- `plans/plan-002.md` (plan snapshot before trimming on 2026-01-05)
- `plans/dev-002.md` (dev-setup checklist before trimming on 2026-01-05)
- `plans/plan-archive-2026-01-06.md` (archived DONE items through 2026-01-06)
- `plans/plan-archive-2026-01-07.md` (archived DONE items through 2026-01-07)
