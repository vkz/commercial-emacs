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
- Internationalization beyond UTF-8 is out of scope (no locale/translation work planned for alpha).

Baseline acceptance criteria (C-hosted TTY Emacs)

- `mise run build` produces working `emacs` and `emacsclient`.
- `mise run run` starts Emacs in a terminal as a normal editor.
- `mise run test:smoke` and `mise run test:check` pass.
- `mise run verify -- --level check` is the one-command gate.

## Recent progress

- Current status snapshot: `build/clemacs/reports/progress.md` (regenerate via `mise run clemacs:report:progress`).
- Completed/superseded items are archived in:
  - `plans/plan-archive-2026-01-06.md`
  - `plans/plan-archive-2026-01-07.md`
  - `plans/plan-archive-2026-01-10.md`
- Latest milestone: DONE (2026-01-10): clemacs TTY "alpha" (open/edit/save/quit + M-x) and a runnable clemacs `emacs` executable (details in `plans/plan-archive-2026-01-10.md`).

## Current work (end goal: shipped ELisp runs under clemacs)

We drive the remaining work with three synced loops:

1) Inventory: use `inventory/*` as the authoritative checklist of primitives.
2) Load: attempt to load more of `lisp/` under clemacs, recording missing pieces.
3) Tests: run increasingly large upstream ERT suites under clemacs with explicit skip lists.

Decision checkpoint (must ask the user)
- If/when we hit a point where clemacs must diverge from upstream ELisp syntax or semantics beyond
  mechanical rewrites, stop and ask for an explicit decision with concrete examples and tradeoffs.

## Current snapshot

Source of truth: `build/clemacs/reports/progress.md` (regenerate via `mise run clemacs:report:progress`).

Quick try path (macOS)
- `mise run clemacs:emacs:run -- path/to/file`
- Gate: `mise run clemacs:verify`

## Roadmap (TODO, priority order)

P0: Put clemacs in users' hands (alpha)
- DONE (2026-01-10): Add a short tester quickstart (clone + `mise` + run command + how to report bugs), plus supported/unsupported feature list (`clemacs/TESTER-QUICKSTART.md`).
- DONE (2026-01-10): Make `clemacs:emacs:run` default to `--startup-level tty-editor` and update `emacs --help` to list `tty-editor`.
- DONE (2026-01-10): Implement minimal `--batch` behavior (load startup manifest, run `--eval` forms, exit nonzero on error); document unsupported flags.
- DONE (2026-01-10): Implement minimal init loading and opt-outs (`-Q` and `-q` Emacs-shaped behavior, even if partial).
- DONE (2026-01-10): Add an "issue bundle" helper task (not Emacs' built-in bug reporter) that captures: `progress.md`, `first-failure.*`, `stamps/*`, plus a repro command line (`mise run clemacs:report:issue-bundle`).

P1: Usable terminal editor UX (stability + core workflows)
- DONE (2026-01-10): Inventory the top interactive workflows that still crash (use `clemacs:test:tty` as the gate) and implement the missing primitives in clusters.
- DONE (2026-01-10): Decide and implement the minimal multi-window surface (split, other-window, delete-window) needed for common help/minibuffer workflows.
- DONE (2026-01-10): Implement an isearch/query-replace vertical slice (enough for real editing), or explicitly document it as missing for alpha.
- DONE (2026-01-10): Reduce TTY bring-up noise by predeclaring a small set of early global vars (`inhibit-point-motion-hooks`, `inhibit-file-name-handlers`, `inhibit-file-name-operation`, `isearch-*`, etc.) and making `clemacs:tty:run` prefer a saved SBCL core + muffle style warnings.

P2: Load more shipped `lisp/` under clemacs (monotonic)
- DONE (2026-01-10): Add the checked-in autoloads snapshot `lisp/ldefs-boot.el` to `clemacs/contract/startup.smoke.files` and bisect/raise its stable checkpoint to 198 forms.
- DONE (2026-01-10): Fix `lisp/ldefs-boot.el` checkpoint past form 199 by raising `lisp/keymap.el` (smoke) and adding a bring-up `defvar-keymap` macro; advance `startup.smoke.files` to include `jka-cmpr-hook` and `epa-hook`.
- TODO: Keep growing `clemacs/contract/startup.{smoke,tty-editor,check,editor-core}.files` following pdump order; bisect early when checkpoints get unstable.
- TODO: Improve autoload/function designator robustness (high-fanout for help/arglist, `cl-generic`, and bytecomp callers).

P3: Upstream ERT bring-up (coverage as a guardrail)
- TODO: Grow `clemacs/contract/ert-upstream.tests` monotonically, prioritizing suites that overlap P1/P2.
- TODO: When something must be skipped, record it in `clemacs/contract/ert-upstream.known-fail.tests` with a dated reason (XPASS is a gate failure).

### Milestone B1-8: load the shipped `lisp/` tree under clemacs

Deliverables
- A deterministic clemacs loader that can load (most of) `lisp/` from this repo.
- A mechanical rewrite path for cases where we intentionally diverge from upstream ELisp.

Gate
- `mise run clemacs:load:lisp -- --level smoke` loads an explicit list of ELisp files and exits 0.
- The list is data in-repo and grows monotonically (no deleting to get green).

Status
- See `build/clemacs/reports/progress.md` for current manifest sizes and contract stamps.

Next actions (TODO)
- TODO: Grow `clemacs/contract/startup.{smoke,tty-editor,check,editor-core}.files` monotonically, following pdump order.
- TODO: On failure, follow the port loop: `mise run clemacs:loop:elisp-core` -> `mise run clemacs:report:first-failure-startup-check-debug` -> implement the single top offender -> leave breadcrumbs -> repeat.
- TODO: Keep `clemacs/contract/lisp.allowed-skip.files` small and dated; prefer implementing missing primitives over skipping.

### Milestone B1-9: run upstream ERT suites under clemacs

Deliverables
- Run a meaningful subset of upstream ERT tests shipped in this repo under clemacs.
- Explicit contract data for must-pass / allowed-skip / known-fail.

Gate
- `mise run clemacs:test:contract -- --level check` fails on regressions.

Next actions (TODO)
- TODO: Expand `clemacs/contract/ert-upstream.tests` monotonically (keep the suite green; use ERT promotions opportunistically when they unblock startup work).
- TODO: Keep `clemacs/contract/ert-upstream.known-fail.tests` dated and explicit (XPASS is a gate failure).

### Milestone B1-12: inventory closure for `startup.check`

Deliverables
- All C-defined primitives referenced by `clemacs/contract/startup.check.files` are either:
  - implemented (prefer shims in `clemacs/elisp-compat.lisp`), or
  - explicitly recorded as an intentional semantic divergence.

Gate
- `mise run clemacs:test:contract -- --level elisp-core` stays green while raising checkpoints.

Next actions (TODO)
- TODO: Use inventory deltas to implement primitives in clusters (next likely: help buffers, file-name helpers, process stubs).
- TODO: Treat each new startup failure as an inventory item: implement/stub and add breadcrumbs (microtests, compat notes, contract updates) in the same patch.

### Milestone B1-14: clemacs "real editor core" boot

Status
- DONE (2026-01-10): interactive TTY editor loop (open/edit/save/quit + M-x), plus a buildable clemacs `emacs` executable; details in `plans/plan-archive-2026-01-10.md`.

Deliverables
- `mise run run:clemacs` starts an interactive editor loop that:
  - loads a curated startup manifest,
  - can open a file, edit, save, quit,
  - and can evaluate ELisp in-process (initially for tests/tooling).

Acceptance criteria (promotion gate)
- Promote clemacs to `mise run run` only when `run:clemacs` is a usable terminal editor and exits cleanly.

Next actions (TODO)
- TODO: Promote the alpha try path by default (`clemacs:emacs:run` defaults and `--help` text), so testers do not need to discover flags manually.
- TODO: Define and gate the "alpha UX" contract (what must work in TTY: file visit/save, kill/yank, isearch, basic window ops) and keep it covered by `clemacs:test:tty`.

## Archive

- `plans/plan-001.md` (Step 0/1 plan snapshot)
- `plans/dev-001.md` (Step 0/1 dev-notes snapshot)
- `plans/plan-002.md` (plan snapshot before trimming on 2026-01-05)
- `plans/dev-002.md` (dev-setup checklist before trimming on 2026-01-05)
- `plans/plan-archive-2026-01-06.md` (archived DONE items through 2026-01-06)
- `plans/plan-archive-2026-01-07.md` (archived DONE items through 2026-01-07)
- `plans/plan-archive-2026-01-10.md` (archived DONE items through 2026-01-10)
