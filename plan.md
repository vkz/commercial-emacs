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
- UTF-8 only: internationalization beyond Unicode/UTF-8 is out of scope.
  - Legacy encodings and input-method catalogs (LEIM) must not block clemacs bring-up; keep them skipped/ignored.

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
  - `plans/plan-archive-2026-01-11.md`
- Latest milestone: DONE (2026-01-11): `cl-generic` + `nadvice` upstream ERT clusters promoted (must-pass), and clemacs advice/interactive plumbing is stable again (details in `plans/plan-archive-2026-01-11.md`).

## Current work (end goal: shipped ELisp runs under clemacs)

We drive the remaining work with three synced loops:

1) Inventory: use `inventory/*` as the authoritative checklist of primitives.
2) Load: attempt to load more of `lisp/` under clemacs, recording missing pieces.
3) Tests: run increasingly large upstream ERT suites under clemacs with explicit skip lists.

Priority note (2026-01-12)
- Deprioritize menu/UI chrome (`menu-bar`, `tab-bar`, GUI-ish surfaces) in favor of
  core TTY editor behavior (buffers/windows/minibuffer/M-x/find-file) and ELisp
  engine correctness (upstream ERT + shipped `lisp/` loads).

Decision checkpoint (must ask the user)
- If/when we hit a point where clemacs must diverge from upstream ELisp syntax or semantics beyond
  mechanical rewrites, stop and ask for an explicit decision with concrete examples and tradeoffs.

Iteration notes (2026-01-12)

Issue noticed + fix path
- DONE (2026-01-12): `clemacs:test:micro` now runs `:emacs :match` comparisons against reference Emacs (no mass "reference Emacs not available" skips); fix path was to make the reference-Emacs batch run succeed (repair two `:match` microtests) and implement the missing compat needed by those tests (notably cyclic `fset` detection and better completion primitives).
- DONE (2026-01-12): Upstream minibuffer/completion bring-up stabilized: `clemacs:test:ert-upstream` completion cluster is green again after implementing `try-completion`/`all-completions`/`test-completion` case+regexp semantics, adding `assoc-string`, and stubbing the remaining completion globals used by `minibuffer.el`.
- DONE (2026-01-12): Grow `startup.smoke` toward pdump order: add a first capped slice of `frame.el`, `startup.el`, `term/tty-colors.el`, and `font-core.el` to `clemacs/contract/startup.smoke.files`.
- DONE (2026-01-12): Expand `ert-upstream.tests` minibuffer completion must-pass set: promote `completion-pcm-test-{3,4,5,6}` (still green).
- DONE (2026-01-12): Expand `ert-upstream.tests` minibuffer completion must-pass set: promote `completion-substring-test-{1,2,3,4,5}` and raise `test/lisp/minibuffer-tests.el` max-forms (in `clemacs/contract/ert-upstream.load.files`) so those tests are actually registered.
- DONE (2026-01-12): Expand `ert-upstream.tests` minibuffer completion must-pass set: promote `completion-flex-test-{1,2,3}` (fix was to implement ELisp-ish `mapcan` over strings so `completion-flex--make-flex-pattern` works).
- DONE (2026-01-12): Grow `startup.tty-editor` toward pdump order: add a first capped slice of `button.el`, `abbrev.el`, `help.el`, `jka-cmpr-hook.el`, `epa-hook.el`, `mule-cmds.el`, `charprop.el`, `characters.el`, `composite.el`, `indent.el`, `startup.el`, `term/tty-colors.el`, `font-core.el`, `mouse.el`, `fringe.el`, `scroll-bar.el`, and `select.el` to `clemacs/contract/startup.tty-editor.files`.
- DONE (2026-01-12): Grow `startup.tty-editor` toward pdump order: add `easymenu.el`, `rfn-eshadow.el`, and the next editor-centric chunk (`lisp.el`, `lisp-mode.el`, `text-mode.el`, `prog-mode.el`, etc); start raising max-forms caps on earlier tty-editor entries to get real bring-up failures instead of “present but barely loaded”.
- DONE (2026-01-12): Grow `startup.tty-editor` toward pdump order: add `fill.el`, `newcomment.el`, `tabulated-list.el`, `buff-menu.el`, `elisp-mode.el`, `disp-table.el`, `ls-lisp.el`, `term/internal.el`, and `ucs-normalize.el` (pdump.tty-editor coverage now 90/105).
- DONE (2026-01-12): Fix `try-completion` duplicates behavior (return `t` when all candidates already equal the prefix) and fix `assoc-string` early return so completion code paths in `minibuffer.el` don’t accidentally take the “common suffix” path and trip `(nreverse t)`; add a semantics microtest.
- NOTE (2026-01-12): clemacs currently canonicalizes mixed-case symbol names via `intern`/`prin1-to-string` (effectively upcasing). Full Emacs-fidelity fix path is to stop upcasing in `intern` and teach the printer to preserve case (or implement Emacs-like `print-escape-uppercase`). Decision: defer until it blocks shipped `lisp/` loads or upstream ERT; prioritize core TTY/editor correctness first.

Next high-leverage steps
- DONE (2026-01-12): Start the minibuffer bring-up loop: add `lisp/minibuffer.el` to `startup.tty-editor` with a low checkpoint and confirm `startup-check` stays green; promote a tiny minibuffer completion cluster into `ert-upstream.tests` and implement the completion plumbing needed to keep it green.
- DONE (2026-01-12): Tighten window/buffer surface toward upstream: implement/stub next window primitives referenced by the `window.el` paths we’re exercising (e.g. `set-window-dedicated-p`) instead of leaving them as undefined warnings.

## Current snapshot

Source of truth: `build/clemacs/reports/progress.md` (regenerate via `mise run clemacs:report:progress`).

Quick try path (macOS)
- `mise run clemacs:emacs:run -- path/to/file`
- Gate: `mise run clemacs:verify`

## Roadmap (TODO, priority order)

P0/P1: clemacs alpha + usable TTY editor slice
- DONE (2026-01-10): See `plans/plan-archive-2026-01-10.md` for the full shipped alpha checklist and details.

P2: Load more shipped `lisp/` under clemacs (monotonic)
- DONE (2026-01-10): Add the checked-in autoloads snapshot `lisp/ldefs-boot.el` to `clemacs/contract/startup.smoke.files` and bisect/raise its stable checkpoint to 198 forms.
- DONE (2026-01-10): Fix `lisp/ldefs-boot.el` checkpoint past form 199 by raising `lisp/keymap.el` (smoke) and adding a bring-up `defvar-keymap` macro; advance `startup.smoke.files` to include `jka-cmpr-hook` and `epa-hook`.
- DONE (2026-01-10): Advance `startup.smoke.files` to include `mule-cmds`, `charprop`, and `characters` (pdump order; monotonic growth).
- DONE (2026-01-11): Raise `startup.smoke.files` and propagate the `macroexp`/`pcase`/`gv`/`cl-preloaded`/`oclosure` prelude needed for stable `cl-generic` bring-up; begin extending `startup.check/editor-core` with `image` and `fontset`, and `startup.tty-editor` with early pdump prereqs (`widget`/`custom`/`map-ynp`/`cus-face`/`faces`/`rx`).
- DONE (2026-01-11): Unblock `startup.check` bring-up iteration: add loader progress/timing output, stub `clemacs/ported/lisp/loaddefs.el` to avoid huge generated autoloads, raise early `widget`/`custom`/`startup` checkpoints, and implement missing compat primitives discovered by startup-check.
- TODO: Keep growing `clemacs/contract/startup.{smoke,tty-editor,check,editor-core}.files` following pdump order; bisect early when checkpoints get unstable.
- DONE (2026-01-12): Extend `clemacs/contract/startup.tty-editor.files` with `syntax.el` and an initial `font-lock.el` slice, keeping `mise run clemacs:verify` green.
- DONE (2026-01-12): Extend `clemacs/contract/startup.tty-editor.files` with `jit-lock.el` and `timer.el`, keeping `mise run clemacs:verify` green.

P3: Upstream ERT bring-up (coverage as a guardrail)
- DONE (2026-01-10): Expand `clemacs/contract/ert-upstream.tests` with a cl-lib cluster (gensym + numeric predicates + helpers), backed by compat fixes and microtests; keep the suite green.
- DONE (2026-01-11): Bring up `cl-generic` upstream tests under clemacs (incl setf-generic names, gv places, defun declaration plumbing); keep the suite green (see `plans/plan-archive-2026-01-11.md`).
- DONE (2026-01-11): Bring up `nadvice` upstream tests under clemacs (incl old advice interop, advice printing, and lexical interactive specs); keep the suite green (see `plans/plan-archive-2026-01-11.md`).
- DONE (2026-01-11): Promote `backquote` and a small `rx` cluster to `clemacs/contract/ert-upstream.tests` (startup-adjacent); keep must-pass monotonic and green.
- DONE (2026-01-11): Expand the upstream ERT must-pass set with a `subr-tests` cluster (cXXr, version parsing, `[:blank:]`, gensym); fix core list accessor semantics (shadow + define cXXr + setf cXXr), implement `\\N{...}` string escapes, and improve `error-message-string` to keep the suite green.
- TODO: Grow `clemacs/contract/ert-upstream.tests` monotonically, prioritizing suites that overlap P1/P2.
- TODO: When something must be skipped, record it in `clemacs/contract/ert-upstream.known-fail.tests` with a dated reason (XPASS is a gate failure).

### Top TODOs (keep short)

- DONE (2026-01-12): Make the PTY editor gate fail on any command-loop error (no
  silent beeps), extend it to exercise buffer switching + window layout ops
  reliably, and fix the underlying CL/ELisp function-cell mismatch (post-load
  shims now use `fset`, not just `fdefinition`) plus minimal buffer-prompt
  primitives (`read-buffer`, `internal-complete-buffer-except`, `other-buffer`,
  `kill-buffer` interactive) to keep `mise run clemacs:test:tty` and
  `mise run clemacs:verify` green.
- TODO (2026-01-12): Bring up upstream minibuffer behavior: start loading `lisp/minibuffer.el` under `startup.tty-editor` (bisect+fix) and promote a small `test/lisp/minibuffer-tests.el` cluster into `clemacs:test:ert-upstream` (must-pass monotonic).
- DONE (2026-01-12): Reduce CL-side noise: eliminate SBCL "redefining ELISP::..." warnings by keeping exactly one definition per ELisp surface symbol (prefer the newest bring-up version).

- DONE (2026-01-11): Raise startup manifests in pdump order, skipping legacy encodings/LEIM (UTF-8 only); keep iterating with `--limit` bisection and `clemacs:report:first-failure`.
- DONE (2026-01-11): Improve agent bring-up ergonomics: document `startup-check --limit` bisection clearly and make `clemacs:report:first-failure`/SBCL log paths discoverable.
- DONE (2026-01-11): Standardize reference Emacs defaults across clemacs `mise` tasks (micro/smoke/ref eval) and make the chosen binary explicit.
- DONE (2026-01-11): Implement missing primitives in tight clusters (help/doc + file-name/filesystem helpers), with new microtests for each behavior.
- DONE (2026-01-11): Promote startup-adjacent upstream ERT tests (backquote + rx), keeping must-pass monotonic and green.
- DONE (2026-01-11): Keep `clemacs/contract/lisp.allowed-skip.files` strictly “out-of-scope only” (no skipping to get green).
- DONE (2026-01-11): Keep the PTY editor gate (`mise run clemacs:test:tty`) representative of the promised alpha UX (visit/edit/save/quit + search/replace + basic window ops).
- DONE (2026-01-11): Close the `pdump.check` gap (105/105) by explicitly marking GUI/non-supported pdump conditionals as out-of-scope and teaching clemacs progress/startup-delta reports to count allowed skips as "covered".
- DONE (2026-01-12): Grow `clemacs/contract/startup.tty-editor.files` while keeping `clemacs:test:contract -- --level elisp-core` green (added more early core: `pp`, `ldefs-boot`, `loaddefs`; load `window.el`/`isearch.el`/`replace.el` directly, with minimal post-load shims to keep the single-window TTY model stable).
- DONE (2026-01-12): Fix TTY UX keybindings to 22/22 (M-v, C-s, C-r, M-%, C-x 2, C-x o, C-x 0) and make the batch check accurate by applying `clemacs-tty-setup` keybinding ensures after loading the tty-editor startup manifest.
- DONE (2026-01-12): Add microtests covering new startup bring-up blockers (ensure `special-event-map` and `window-persistent-parameters` are bound as expected).
- DONE (2026-01-12): Make command loop honor overriding keymaps and `pre-command-hook`/`post-command-hook` so modal libraries like `isearch.el` behave correctly.
- DONE (2026-01-12): Stabilize the PTY editor gate input stream (handle partial PTY writes; treat query-replace confirmation as a single keystroke).
- DONE (2026-01-12): Implement TTY window geometry primitives used by upstream `window.el` (pixelwise sizes + edges deps), remove window post-load size shims to avoid recursion, and add one semantics microtest per primitive.
- DONE (2026-01-12): Fix two bring-up correctness bugs uncovered while gating: `symbol-value` now signals `void-variable` for truly unbound vars, and `function-get` no longer loops forever on circular function indirections.
- DONE (2026-01-12): Improve `clemacs:test:contract -- --level elisp-core` iteration time/visibility: make `startup-check` emit periodic progress + async heartbeat output (and optional async backtrace) so long runs are obviously live.
- DONE (2026-01-12): Fix `startup-check` hang in `lisp/textmodes/text-mode.el` (form 6): ensure `text-mode-map` is an early empty keymap (not nil) so the `defcustom` setter's `keymap-unset` does not stall the loader.
- DONE (2026-01-12): Make `mise run progress` stable across builds: rebuild `build/clemacs/bin/emacs` before probing tty UX keybindings and invalidate cached progress when inputs are newer (fixes occasional `0/22` false-red display).
- DONE (2026-01-12): Make interactive clemacs default to a usable editor: `emacs-main` defaults `--startup-level` to `tty-editor` (batch default stays `smoke`).

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

## Archive

- `plans/plan-001.md` (Step 0/1 plan snapshot)
- `plans/dev-001.md` (Step 0/1 dev-notes snapshot)
- `plans/plan-002.md` (plan snapshot before trimming on 2026-01-05)
- `plans/dev-002.md` (dev-setup checklist before trimming on 2026-01-05)
- `plans/plan-archive-2026-01-06.md` (archived DONE items through 2026-01-06)
- `plans/plan-archive-2026-01-07.md` (archived DONE items through 2026-01-07)
- `plans/plan-archive-2026-01-10.md` (archived DONE items through 2026-01-10)
- `plans/plan-archive-2026-01-11.md` (archived DONE items through 2026-01-11)
