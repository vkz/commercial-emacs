# clmacs Plan — TTY-only Emacs + SBCL-hosted Emacs Lisp

This project is a fork of a fork. The current direction is:

- Keep **TTY-only** Emacs as the runtime target.
- Rewrite the **Emacs Lisp engine** so Emacs Lisp is implemented **inside Common Lisp (SBCL)**,
  with an internal “unquote” escape to the SBCL host.
- Keep GUI code only insofar as it is shared/common infrastructure or valuable reference we can
  always recover from Git history.
- Tree-sitter and moving-GC work from upstream forks are **out of scope for now**
  (tree-sitter later; moving GC never, because SBCL GC is the route).

## Archive (what we already did)

The initial Step 0/1 trimming + build/test harness work is complete and archived:

- `plans/plan-001.md` (plan snapshot + DONE checklist)
- `plans/dev-001.md` (dev-notes snapshot + DONE checklist)

## Important consequences of Step 0/1 trimming

These are intentional and should be treated as invariants until the project direction changes:

- GUI backends are removed (`nextstep/`, `lwlib/`, `oldXMenu/`, and `src/` NS/X11/PGTK backends).
- GUI-only Elisp integration is removed:
  - `lisp/term/common-win.el`, `lisp/term/x-win.el`, `lisp/term/ns-win.el`, `lisp/term/pgtk-win.el`
  - `lisp/x-dnd.el`, `lisp/pgtk-dnd.el`, and `test/lisp/x-dnd-tests.el`
- Dynamic modules are removed.
- Native compilation (libgccjit / `.eln`) is removed/disabled.
- `admin/unidata/` is removed; Unicode regeneration requires temporarily restoring an equivalent source.

Acceptance criteria (still the gate for future changes)
- `mise run build` produces working `emacs` and `emacsclient`.
- `mise run run` starts Emacs in a terminal as a normal editor.
- `mise run test:smoke` and `mise run test:check` pass.
- `mise run verify -- --level check` is the one-command “did we break it?” loop.

## Pre-rewrite preparation (before touching the ELisp engine)

### 1) Freeze a conformance target + carve out “must pass” suites

- Pick the exact upstream baseline you are targeting for ELisp semantics (e.g. “Emacs 31.0.50 behavior as shipped in this repo on 2026-01-02”).
- Create an explicit test contract:
  - `must-pass` (core ELisp semantics + core editor behaviors)
  - `allowed-skip` (anything that depends on removed GUI backends/modules/nativecomp)
  - `known-fail` (if any; should be temporary and tracked)
- Make the test entrypoints deterministic and fast to iterate (you already have `mise run verify`, but for the rewrite you’ll want a narrower “elisp-core” set you can run constantly).

Status (DONE, 2026-01-02)
- Contract data lives in `test/contract/`:
  - `test/contract/smoke.logtargets` (must-pass fast suite)
  - `test/contract/allowed-skip.logtargets` (intentionally not run)
  - `test/contract/known-fail.logtargets` (temporary tolerations)
- `mise` entrypoints (must remain stable):
  - `mise run test:smoke` consumes `test/contract/smoke.logtargets`
  - `mise run test:contract -- --level smoke|check|check-all` is the “contract gate”

Expansion (project-specific)
- Conformance statement (initial):
  - Target “Emacs 31.0.50 behavior” as observed in this repo’s TTY build, but with the stronger
    practical goal: **all or most of the Elisp shipped with Emacs continues to work** as a user
    would expect, modulo any explicitly documented changes required by embedding into an SBCL host.
- Concrete test entrypoints (must remain available via `mise`, even if we later need to adjust the
  test suite for CL-host interop semantics):
  - Smoke: `mise run test:smoke`
  - Default suite: `mise run test:check`
  - Full suite: `mise run test:check-all`
  - Single file: `mise run test:file -- <path-without-.el>` (e.g. `lisp/emacs-lisp/ert-tests`)
  - End-to-end gate: `mise run verify -- --level check`
- Test contract implementation approach (no guesswork):
  - Define a single source-of-truth manifest for “must-pass” tests (a checked-in list of `.log`
    targets, or an ERT selector file), and have the `mise` tasks consume that manifest.
  - Track `allowed-skip`/`known-fail` explicitly in the repo (as data), so agents don’t delete tests
    to “get green” and accidentally narrow the conformance target.

### 2) Inventory the C-defined ELisp surface area (this is the real spec)

- Extract/track (as data) the full set of:
  - `DEFSUBR` / `defsubr` primitives
  - C-defined variables (`DEFVAR_LISP`, `DEFSYM`, etc.)
  - special forms and bytecode ops
- The goal is a machine-checkable list: “these symbols exist; these arglists/docstrings; these side effects”.
- This inventory becomes your implementation checklist and prevents drifting into “hallucinated” semantics.

Expansion (step-by-step plan + output format)

Goal
- Produce a **machine-readable, regeneratable inventory** of every C-defined Elisp entrypoint and
  C-defined variable/symbol that matters for an SBCL-hosted engine port.

Proposed on-disk format (authoritative data)
- Create an `inventory/` directory (or `plans/inventory/` if we prefer to keep it purely as planning
  artifacts; decide once and stick to it).
- Primary artifact: `inventory/c-elisp.jsonl` (JSON Lines; one record per item).
  - Reasoning: JSONL is easy to diff, stream, and extend without schema migrations.
- Each record should include (minimum):
  - `kind`: `"subr" | "special_form" | "variable" | "symbol" | "bytecode_op"`
  - `lisp_name`: e.g. `"car"`, `"setq"`, `"buffer-list"`
  - `c_name`: e.g. `"Fcar"` for subrs, or the C variable name for `DEFVAR_*`
  - `source`: `{ "path": "src/...", "line": 123 }`
  - `arity`: `{ "min": 1, "max": 1 }` when applicable
  - `doc`: `{ "present": true, "hash": "..." }` (store full doc elsewhere if large)
  - `notes`: freeform string for oddities (unevalled args, special forms, etc.)
- Secondary artifacts (generated from JSONL):
  - `inventory/README.md` (human-readable summary + “how to regenerate”)
  - `inventory/c-elisp.tsv` (optional, for quick grep/spreadsheet use)

Collection plan (static + dynamic cross-check)
1. Static extraction (from sources)
   - Scan `src/` for:
     - `DEFUN` macro uses (primary list of primitives/special forms)
     - `DEFSUBR` / `defsubr` uses (registration list)
     - `DEFVAR_*` uses (C-defined variables)
     - `DEFSYM` and related symbol registration macros
   - Parse enough of each macro invocation to capture:
     - Lisp-visible name
     - C function/variable name
     - arity (where encoded)
     - file/line (for traceability)
2. Dynamic extraction (from a built TTY Emacs)
   - Run `emacs -Q --batch` and dump:
     - all `subr` functions (names + arity + doc presence)
     - optionally, “core” variables with documentation (at least those found in static extraction)
   - Use this to cross-check the static list:
     - static items missing at runtime: bug in extractor or build not loading the expected core
     - runtime subrs missing in static list: bug in extractor or macro variant not handled
3. Validation and guardrails
   - Add a `mise` task pair (later):
     - `inventory:regen`: regenerate JSONL + derived views
     - `inventory:check`: fail if regeneration would change committed inventory
4. Acceptance criteria for the inventory work
   - The inventory regenerates deterministically on macOS.
   - The static and dynamic inventories match within an explicitly documented, small exception set.
   - The inventory is sufficient to drive a “port checklist” (we can sort/group by `kind` and by
     `source.path` to plan port order).

Status (DONE, 2026-01-02)
- Inventory artifacts live in `inventory/`:
  - `inventory/c-elisp.jsonl` and `inventory/c-elisp.tsv` (authoritative for the current TTY build)
  - `inventory/runtime-subrs.json` (canonical subr list; de-duped via `subr-name` to avoid aliases)
  - `inventory/runtime-check.json` (runtime validation for variables/symbols)
  - `inventory/exceptions.json` (explicit, small exception lists; keep empty if possible)
- Regenerate / validate:
  - `mise run inventory:regen`
  - `mise run inventory:check` (fails if mismatch or if inventory is out of date)

### 3) Decide and document the embedding boundary (Option A vs Option B)

This repo now has two explicit design documents:

- Option A ("C-hosted, embed SBCL"): `plans/emacl.md`
- Option B ("SBCL-hosted, C as substrate library"): `plans/clemacs.md`

For this worktree/branch ("clemacs"), commit to Option B, specifically **B1
handle-based substrate API**, with a CL-first "Elisp as CL dialect" stance.

Decisions (record as the conformance contract for this branch)

- Process ownership (initial): keep the existing `src/emacs` build intact for
  baseline tests, and build a separate experimental `clemacs` binary/image for
  Option B bring-up.
- Value model (target): CL owns Lisp values and their lifetimes; C is forbidden
  from depending on `Lisp_Object` except behind explicitly timeboxed shims.
- Bytecode: do not prioritize `.elc` / Emacs bytecode compatibility initially.
- Semantics stance: "Elisp" is a compat layer; prefer CL constructs where the
  migration cost is mechanical and bounded.
- Syntax/namespace stance (initial):
  - read and compile elisp into a dedicated `ELISP` package,
  - accept CL `:keywords` as CL keywords in the `KEYWORD` package (migration
    may be required),
  - provide reader support for the highest-impact tokens (e.g. `[]`, `?x`),
  - treat lexical binding as the default; dynamic binding is explicit via
    `defvar`-style declarations (or an equivalent `special` policy).

First integration milestone (must be crisp)

- Start SBCL, load a CL system, call into the C substrate, and return a value.
- Add a tiny "hello command loop" in CL (TTY): read a key, run a command, update
  the screen, quit cleanly.

Boot story (write down and keep correct)

- Existing baseline stays: `mise run build`, `mise run run`, `mise run test:*`
  remain meaningful for the C-hosted Emacs while clemacs is experimental.
- clemacs boot uses an SBCL core/image (pdumper deferred); it loads:
  1) substrate FFI bindings,
  2) the CL-hosted Elisp dialect layer,
  3) a minimal editor core and test harness.

### 4) Create compatibility seams in the C runtime (for Option B1)

In Option B1, the key seam is not "swap eval.c later"; it is "stop letting
`Lisp_Object` be the substrate ABI."

Action items (C side)

- Introduce an explicit substrate API layer (new header + C files) that:
  - exports a small, stable C ABI (TTY IO, filesystem, timers, etc.),
  - uses `emx_value` (opaque handles) for any Lisp values crossing the boundary,
  - never exposes `Lisp_Object` in the substrate header.
- Create timeboxed shims (if needed) that adapt legacy `Lisp_Object` code to the
  new substrate API, and schedule their deletion.

Action items (CL side)

- Choose a stable-handle strategy and implement it early:
  - default: integer handles backed by a CL-managed table,
  - optional later: pinned/immobile objects if performance demands it.
- Define a single error propagation model for CL<->C:
  - substrate returns error codes/errno-ish data,
  - CL converts to conditions (including a dedicated "quit" condition).

Guardrails

- Any new C code in the substrate layer must not include or traffic in
  `Lisp_Object`.
- Any B2-like bridging must be explicitly marked as temporary and have a
  milestone after which it is removed.

### 5) Hard rules for removed features and future removals (avoid false negatives)

Keep the Step 0/1 invariants as hard constraints:

- GUI backends stay removed.
- Dynamic modules stay removed.
- Native compilation stays disabled.

Add clemacs-specific constraints (until proven necessary)

- Source-only load path initially (no `.elc` requirements).
- No "reintroduce GUI-only lisp" for clemacs to get tests green; instead, update
  the test contract skip lists.

### 6) Build/debug ergonomics tuned for the rewrite

Make clemacs iteration loops as short as the existing `mise run verify` loop.

- SBCL: run SBCL via `mise` (tools and/or tasks), and keep invocation flags
  deterministic across developers and CI.
- Add `mise` tasks (new, clemacs-specific):
  - `clemacs:build` / `clemacs:run` for the SBCL-hosted binary/image
  - `clemacs:test:smoke` for CL-level tests (fast, always runnable)
  - `clemacs:verify` as the one-command loop for clemacs bring-up
- Debugging:
  - standardize on SLY/SLYNK attachment to the running SBCL process,
  - ensure crashes yield actionable backtraces on both sides (C and SBCL).

Execution model (two loops, both supported)

1. Non-interactive "agent gate" loop
   - Use one-shot invocations for determinism:
     - `sbcl --non-interactive` for eval/test commands
     - add `--disable-debugger` for CI-like runs so we never wedge waiting on an
       interactive debugger prompt
   - Expectation: this is the default for `clemacs:test:*` and `clemacs:verify`.
   - Performance note: if one-shot startup becomes a bottleneck, mitigate with:
     - precompiled FASLs and incremental caching under the clemacs build dir,
     - an SBCL saved core/image for clemacs dev loops.

2. Interactive "human REPL" loop
   - Provide `mise run clemacs:slynk` to start a long-lived SBCL with SLYNK.
   - Developer attaches with `M-x sly-connect` and uses SLY to compile/eval,
     inspect values, and drive the debugger UI.

TTY safety (avoid wedging the shell)

- Until the "hello TTY loop" milestone, prefer headless/non-interactive tests.
- For any interactive TTY loop work:
  - use CL `unwind-protect` around terminal raw-mode changes, and
  - wrap `clemacs:run` in a shell guard that snapshots/restores `stty` state.
- Optional safety harness: run interactive clemacs inside `tmux` so killing the
  session restores a usable outer terminal even if clemacs wedges.

### 7) SBCL ecosystem dependency policy (explicit opt-in, SBCL-only)

Policy (branch default)

- SBCL-only is acceptable; do not spend effort on portability until later.
- Allow dependencies only when they:
  1) cut implementation time significantly,
  2) are stable/widely used,
  3) do not define Elisp semantics,
  4) can be swapped later.

Initial allowed set (expected to be enough for bring-up)

- ASDF/UIOP (project structure)
- Alexandria (utilities)
- CFFI (FFI to the substrate library)
- named-readtables (isolated reader mode for Elisp tokens)
- Test framework: pick one (FiveAM or Parachute)

Optional (only if we have a concrete need)

- Eclector (CST/reader + source locations)
- Serapeum (higher-level utilities)
- Trivia (pattern matching for AST transforms)
- SLY/SLYNK (interactive debugging; dev-only)

Vendoring/pinning (decide once, then stick to it)

- Prefer vendored/pinned sources in-repo (submodules or `vendor/`) over global
  Quicklisp state. If Quicklisp is used, it must be pinned and automated via
  `mise` tasks so it is reproducible.

### 8) Autoloads / generated artifacts policy (for clemacs)

The C-hosted Emacs build has existing "generated-ish" artifacts and policies.
clemacs will introduce more.

Rules to decide up front

- Any generated/transformed artifacts for clemacs should live out-of-tree under
  `build/` (or a clemacs-specific build dir) unless there is a strong reason to
  commit them.
- If we add a source-to-source rewrite step (Elisp -> CL-ish), it must be:
  - deterministic,
  - driven by a `mise` task,
  - cached/incremental where possible,
  - diffable for review.

## clemacs rewrite plan (Option B1, test-gated milestones)

This section is the actionable plan for this branch. The goal is to keep
progress measurable and always "execution guided": make a change, run a gate,
only proceed if the gate behaves as expected.

### Milestone B1-0: repo + toolchain readiness

Deliverables
- SBCL installed and invoked deterministically.
- A minimal CL system layout for clemacs (ASDF system + entrypoint).
- `mise run clemacs:build` and `mise run clemacs:run` exist (even if they only
  start SBCL and print a banner).
- Measure one-shot latency (wall time) for `clemacs:eval`/`clemacs:test:smoke`
  and decide whether we also need a saved core for fast iteration.

Gate
- `mise run clemacs:run` starts and exits cleanly from a terminal.

Status (DONE, 2026-01-02)
- DONE: Pin SBCL via `mise` (`sbcl@2.6.0` in `mise.toml`).
- DONE: Add minimal ASDF system scaffold under `clemacs/`.
- DONE: Add `mise` tasks:
  - `clemacs:bootstrap` (installs ECL host CL + SBCL via mise)
  - `clemacs:build`
  - `clemacs:run`
  - `clemacs:test:smoke`
- DONE: Gate passes: `mise run clemacs:run` prints banner and exits cleanly.
- DONE: One-shot timing (warm): `mise run clemacs:run` ~0.12s real on this machine.
- DONE (2026-01-03): One-shot timing (cold; cleared `build/clemacs/xdg-cache`): `mise run clemacs:bench:cold` ~31.24s real on this machine.
- DONE (2026-01-03): Add an optional saved-core path:
  - Build: `mise run clemacs:core:build`
  - Runs/tests use the core automatically when `build/clemacs/clemacs.core` exists.

### Milestone B1-1: substrate library callable from SBCL

Deliverables
- C substrate library builds as a dylib (or linked objects) with a tiny API:
  - version/probe call,
  - one trivial function (e.g., return platform string).
- CL code calls the substrate via CFFI and gets the correct result.

Gate
- A CL-level smoke test calls the substrate and validates results.

Status (DONE, 2026-01-03)
- DONE: Choose dependency workflow: qlot + `clemacs/qlfile.lock` (pinned; via mise).
- DONE: Add `clemacs/qlfile` + `clemacs/qlfile.lock` (commit both).
- DONE: Add mise tasks:
  - `clemacs:deps:install` (out-of-tree deps under `build/clemacs/deps/.qlot`)
  - `clemacs:deps:lock` (regenerates `clemacs/qlfile.lock`)
  - `clemacs:substrate:build` (builds `build/clemacs/substrate/libemxsubstrate.dylib`)
  - `clemacs:verify` (one-command gate for bring-up)
- DONE: Implement substrate dylib API: `emx_substrate_version`, `emx_substrate_platform`.
- DONE: Implement CL-side CFFI bindings + smoke test gate (`mise run clemacs:test:smoke`).
- DONE: Make dependency install faster: `clemacs:deps:install` skips `qlot install` when qlfile/lock stamp matches.

### Milestone B1-2: stable handle table + error model

Deliverables
- `emx_value` handle type and CL-side handle table.
- Defined C<->CL error propagation contract (return codes -> conditions).
- Defined "quit" propagation model.

Gate
- CL tests cover handle allocation/freeing and error propagation.

Status (DONE, 2026-01-03)
- DONE: Define substrate status/errno-ish contract (`emx_status` + small code set).
- DONE: Add substrate function to exercise errors (`emx_substrate_parse_int`).
- DONE: Implement CL-side handle table (`make-handle-table`, `handle-alloc/get/free`).
- DONE: Implement CL-side error model (conditions + status->condition mapping).
- DONE: Smoke test covers handle semantics + error propagation (`mise run clemacs:test:smoke`).
- DONE (2026-01-03): Replace ad-hoc smoke assertions with FiveAM (still invoked via `mise run clemacs:test:smoke`).

### Milestone B1-3: Elisp-as-CL dialect loader (source first)

Deliverables
- A loader that can read a restricted Elisp subset and run it as CL (either via
  reader macros or a prepass + standard CL reader).
- A compatibility layer module (`ELISP` package) with initial shims:
  `defun`, `defvar`, `setq`, basic predicates, and plists.

Gate
- A small compatibility test suite runs under SBCL and cross-checks a handful of
  expressions against the baseline C-hosted `emacs -Q --batch`.

Status (DONE, 2026-01-03)
- DONE: Add an `ELISP` package and a restricted reader (supports `[]` vectors and `?x` chars).
- DONE: Add initial compat shims: `plist-get`, `plist-put`.
- DONE: Extend `clemacs:test:smoke` to evaluate a handful of ELisp forms and cross-check against `emacs -Q --batch` when `emacs` is on PATH.
- DONE (2026-01-03): Implement `ELISP:SETQ` as a macro that:
  - preserves lexical bindings when inside `let`,
  - treats unknown/global variables as `symbol-value` assignments to avoid noisy CL undefined-variable warnings.

### Milestone B1-4: hello TTY command loop

Deliverables
- Minimal TTY input/output through the substrate API.
- Minimal command dispatch in CL with a few built-in commands:
  - insert text,
  - move point,
  - save/quit.

Gate
- Manual interactive check: edit a file in a terminal and exit without breaking
  terminal state.
- Prefer running this milestone inside `tmux` so a wedged TTY can be killed
  without losing the outer shell.

Status (DONE, 2026-01-03)
- DONE: Add substrate TTY API (raw mode + byte read/write).
- DONE: Add CL TTY loop (`clemacs:tty-main`) with insert/backspace and basic cursor moves.
- DONE: Add `mise` entrypoint for interactive bring-up: `mise run clemacs:tty:run` (restores `stty` on exit).
- DONE (2026-01-03): Add multi-line display with a viewport (uses terminal size) and vertical motion (arrows/C-p/C-n).
- DONE (2026-01-03): Add real save/quit chords: `C-x C-s` and `C-x C-c` (legacy `C-s` / `C-q` still work for now).
- DONE (2026-01-03): Automated TTY gate: `mise run clemacs:test:tty` drives `clemacs:tty-main` under a PTY and verifies save/quit.

### Milestone B1-5: expand editor substrate coverage

Deliverables
- Incrementally grow substrate services needed for a real editor core:
  buffers, gap/text representation, markers, keymaps, minibuffer (as needed).
- Keep moving "editor logic" into CL to avoid chatty cross-boundary loops.

Gate
- Start running a curated subset of Emacs lisp shipped in this repo (ported or
  mechanically rewritten) and pass an expanding clemacs smoke suite.

Status (DONE, 2026-01-03)
- DONE (2026-01-03): Introduce a CL buffer object with stable operations:
  insert/delete, point motion, and extraction to/from UTF-8 files.
- DONE (2026-01-03): Switch the TTY loop to use the buffer object (instead of raw strings).
- DONE (2026-01-03): Add buffer-focused tests to `clemacs:test:smoke`.
- DONE (2026-01-03): Introduce a minimal keymap/command dispatch layer:
  - represent key sequences (including prefix keys),
  - map to command functions,
  - keep editor logic in CL.
- DONE (2026-01-03): Add a minimal minibuffer-ish prompt surface (save-as prompt when buffer has no path).

### Milestone B1-6: converge on the existing test contract

Deliverables
- A plan to run ERT and selected upstream tests under clemacs.
- A compatibility report: what is identical, what is intentionally different,
  and how to mechanically migrate third-party elisp.

Gate
- `mise run test:smoke` (or an agreed successor contract) passes under clemacs
  with an explicit, justified skip list.

Status (DONE, 2026-01-03)
- DONE (2026-01-03): Write and maintain a clemacs compatibility report:
  - what Elisp forms are supported,
  - what semantics are intentionally different,
  - mechanical migration guidance.
- DONE (2026-01-03): Define a clemacs-specific contract gate (successor to `mise run test:smoke`)
  with explicit data for must-pass / allowed-skip / known-fail.
- DONE (2026-01-03): Add `mise` entrypoints to run that gate at levels `smoke` and `check`.
- DONE (2026-01-03): Prototype an ERT runner strategy (incremental):
  - implement a tiny ERT-like harness in the `ELISP` package,
  - run a handful of ERT-style tests from `clemacs/contract/ert-smoke.el` via `mise run clemacs:test:ert`,
  - include it in the `check` contract level (`mise run clemacs:test:contract -- --level check`).
