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

- `mise run clemacs:test:contract -- --level elisp-core && mise run clemacs:report:progress`

## Dev setup (DONE, 2026-01-05)

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

DONE (2026-01-05)
- Fix out-of-tree dump/startup load-path to prefer build-tree `.elc` files (vs source `.el`).
- Make `mise run build` generate shipped snapshot files (`lisp/cus-load.el`, `lisp/finder-inf.el`) when missing.
- Fix `clemacs:report:startup-delta` to resolve pdump load paths to real `lisp/**` files.
- Grow clemacs startup manifests (check/editor-core): add fill/comment/replace/tabulated-list/buff-menu and related TTY bits.
- Raise several startup.check checkpoints (fill, replace, tabulated-list, buff-menu, isearch) and uncap timer/newcomment/fringe/select.
- Add core editor ELisp shims (BOL/EOL motion, indentation, string/window width) and capture behavior in semantics microtests.

## Current work (end goal: shipped ELisp runs under clemacs)

We drive the remaining work with three synced loops:

1) Inventory: use `inventory/*` as the authoritative checklist of primitives.
2) Load: attempt to load more of `lisp/` under clemacs, recording missing pieces.
3) Tests: run increasingly large upstream ERT suites under clemacs with explicit skip lists.

Decision checkpoint (must ask the user)
- If/when we hit a point where clemacs must diverge from upstream ELisp syntax or semantics beyond
  mechanical rewrites, stop and ask for an explicit decision with concrete examples and tradeoffs.

## Milestones (TODO)

### Milestone B1-8: load the shipped `lisp/` tree under clemacs

Deliverables
- A deterministic clemacs loader that can load (most of) `lisp/` from this repo.
- A mechanical rewrite path for cases where we intentionally diverge from upstream ELisp.

Gate
- `mise run clemacs:load:lisp -- --level smoke` loads an explicit list of ELisp files and exits 0.
- The list is data in-repo and grows monotonically (no deleting to get green).

Next actions
- Grow `clemacs/contract/startup.{smoke,check,editor-core}.files` monotonically, following pdump order.
- Prefer conservative per-file checkpoints; use `mise run clemacs:report:first-failure` + `clemacs:bisect:file` when unstable.

### Milestone B1-9: run upstream ERT suites under clemacs

Deliverables
- Run a meaningful subset of upstream ERT tests shipped in this repo under clemacs.
- Explicit contract data for must-pass / allowed-skip / known-fail.

Gate
- `mise run clemacs:test:contract -- --level check` fails on regressions.

Next actions
- Expand `clemacs/contract/ert-upstream.tests` monotonically.
- Keep `clemacs/contract/ert-upstream.known-fail.tests` dated and explicit (XPASS is a gate failure).

### Milestone B1-12: inventory closure for `startup.check`

Deliverables
- All C-defined primitives referenced by `clemacs/contract/startup.check.files` are either:
  - implemented (prefer shims in `clemacs/elisp-compat.lisp`), or
  - explicitly recorded as an intentional semantic divergence.

Gate
- `mise run clemacs:test:contract -- --level elisp-core` stays green while raising checkpoints.

Next actions
- Treat each new failure as an inventory item: implement or stub the missing primitive and add breadcrumbs.

### Milestone B1-14: clemacs "real editor core" boot

Deliverables
- `mise run run:clemacs` starts an interactive editor loop that:
  - loads a curated startup manifest,
  - can open a file, edit, save, quit,
  - and can evaluate ELisp in-process (initially for tests/tooling).

Acceptance criteria (promotion gate)
- Promote clemacs to `mise run run` only when `run:clemacs` is a usable terminal editor and exits cleanly.

## Archive

- `plans/plan-001.md` (Step 0/1 plan snapshot)
- `plans/dev-001.md` (Step 0/1 dev-notes snapshot)
- `plans/plan-002.md` (plan snapshot before trimming on 2026-01-05)
- `plans/dev-002.md` (dev-setup checklist before trimming on 2026-01-05)
