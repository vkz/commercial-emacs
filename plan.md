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

### 3) Decide and document the embedding boundary (what stays C vs what becomes SBCL first)

- You need a crisp “first integration milestone”, e.g.:
  - SBCL loads + can evaluate a small embedded ELisp subset, called from `Feval`/`Fapply` (or a parallel entrypoint).
  - Or SBCL implements reader/printer first (often easier to validate early), while evaluation remains in C temporarily.
- Write down the exact boot path: how Emacs reaches a usable state (loadup/pdump/startup) when parts of ELisp move.

### 4) Create “compatibility seams” in the C runtime (so you can swap subsystems gradually)

- Identify the choke points you’ll eventually replace:
  - reader: `lread.c` paths
  - evaluator: `eval.c` / `bytecode.c`
  - printer: `print.c`
  - symbol/value/function cells, environments, backtrace/debugger hooks
- Put thin indirection layers around them (even if initially they just call the existing implementation), so later you can route calls to SBCL without rewriting half of Emacs at once.

### 5) Hard rules for removed features and future removals (to avoid false negatives)

- Keep a single source of truth listing what is permanently gone: GUI backends, modules, nativecomp, x-dnd, etc.
- Ensure the test runner automatically skips tests that depend on removed features (rather than deleting random tests ad hoc).
- Add guardrails like your existing `trim:check`, but focused for the rewrite too (e.g., “no new nativecomp references”, “no GUI lisp files reintroduced”).

### 6) Build/debug ergonomics tuned for the rewrite

- Add a standard “debug build profile” (CFLAGS, assertions, maybe sanitizers where feasible) that agents always use when touching eval/alloc/GC-adjacent code.
- Add a fast “core crash repro” loop: run batch eval scripts under the built `emacs` and capture backtraces reliably.

### 7) Decide the SBCL ecosystem dependency policy now (explicit opt-in)

- Write down:
  - whether you allow Quicklisp/Ultralisp at all
  - how dependencies are vendored/pinned (git submodules? vendored tarballs? ASDF local-projects?)
  - what categories are allowed (testing, parsing, unicode, ffi, logging)
- This prevents “just add library X” sprawl once implementation pressure hits.

### 8) Autoloads / generated artifacts policy

- Right now you’re editing/depending on generated-ish files (`ldefs-boot.el`, `loaddefs.el` is ignored).
- Before the rewrite, decide:
  - what is regenerated, when, and by which `mise` task
  - what is checked in vs always-generated
- Otherwise you’ll hit confusing rebuild diffs and “file came back” regressions mid-refactor.

## SBCL-hosted engine rewrite (high-level, after prep)

This is the main project. The plan here must be explicit about milestones and test gates.

### Architecture spike

Questions to answer early
- How does `src/emacs` start/own the SBCL runtime?
- How do we represent Lisp values across the boundary (C <-> CL) without GC hazards?
- How do we call “primitive” operations that remain implemented in C while the engine is in CL?

Deliverable
- A written “engine boundary contract” (what is implemented in CL vs C, and the calling convention).

Acceptance criteria
- We can start Emacs and evaluate a minimal Emacs Lisp form via the SBCL-hosted engine, in the real
  command loop (not just a toy harness).

### Port plan for the “C-defined Lisp core”

Scope we must eventually reimplement (high-level)
- The evaluator and apply/funcall machinery currently in C.
- The reader (or an equivalent that produces identical Lisp objects/semantics).
- Core object model (symbols, conses, vectors, strings, numbers, hash tables, markers, etc.) with
  correct printing and equality semantics.
- The “defuns/defmacros in C” surface area (every primitive exposed to Lisp must exist and behave
  correctly).

Suggested milestones (test-gated)
- M1: Reader + printer parity for basic types; passes `test/src/lread-tests.el`
- M2: Core eval/apply parity for special forms and function call; passes smoke subset (`eval-tests`, `macroexp-tests`)
- M3: Bytecode execution parity (if we keep bytecode); passes `bytecomp-tests` / `byte-run-tests` as relevant
- M4: Pass `mise run test:check` with a documented exception list (ideally empty)
