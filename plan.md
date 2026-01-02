# clmacs Plan — TTY-only Emacs + SBCL-hosted Emacs Lisp

This document replaces the old “GUI-only trim” plan. The new direction is:

- Keep **TTY-only** Emacs (no NS/Cocoa, no X11, no PGTK) as the runtime target.
- Rewrite the **Emacs Lisp engine** so Emacs Lisp is implemented **inside Common Lisp (SBCL)**, with an internal “unquote” escape to the SBCL host.
- Keep GUI code only insofar as it is (a) shared/common infrastructure or (b) useful reference that we can always recover from Git history.
- Treat tree-sitter and moving-GC work in this fork as **out of scope for now** (tree-sitter later; moving GC never, because SBCL GC is the route).


## Reality Checks (verified in *this* repo)

These are the only “claims” this plan relies on:

- `README.md` (from the upstream fork) states this tree is based on **GNU Emacs 31.0.50** and lists divergences (long lines work, tree-sitter highlighting, gnus/process rewrites, PPSS work, moving GC).
  - We do **not** assume the non-tree-sitter claims are correct; we’ll avoid depending on them until we’ve validated behavior in code/tests.
- Tree-sitter support is wired into `configure.ac` behind `--with-tree-sitter` and checks for `tree-sitter = v0.20.10beta3`.
  - There is a test subtree `test/src/tree-sitter-*` and `test/src/tree-sitter-tests.el`.
  - We will keep the code around but default to `--with-tree-sitter=no` until we explicitly work on it.
- The test harness is standard Emacs: `test/README` + `test/Makefile.in` using
  ERT selectors and `make -C <build>/test check` / `check-all` / file-specific
  targets (or, in this repo, `mise run test:*`).


## Constraints / Non-goals

Hard constraints
- **TTY-only runtime**: we build/run in terminal only.
- **SBCL only** for the Common Lisp host.
- **Primary dev platform is macOS on this machine** (Linux/FreeBSD testing comes later).

Out of scope (for this plan revision)
- Tree-sitter work (we will not improve it now; we’ll only avoid breaking it).
- Moving GC work (we will not use it; SBCL GC is the path).
- Emacs Lisp native compilation / JIT via libgccjit (out of scope; removed in this fork).
- Browser-only frontend (future ambition; plan should not preclude it, but does not implement it).


## Roadmap Overview

We keep the ordering you requested, with explicit acceptance criteria:

- Step 0a: delete large chunks we will not need
- Step 0b: move build + routine dev tasks under `mise`
- Step 1: surface Emacs Lisp tests (smoke + full suite) for conformance
- Step 2: design + execute the SBCL-hosted Emacs Lisp engine rewrite

Principles
- Prefer **configure/build gating** before deletion when uncertainty exists.
- Make changes **reversible** by tagging before large deletes.
- Prefer “delete whole directories and whole ports” over nibbling individual `#ifdef`s.


## Step 0 — Baseline Snapshot (before deletes)

0.1 Tag a safety point
- Create a local branch and tag so we can confidently delete.

0.2 Establish a reproducible baseline *TTY build* on macOS
- Goal is to prove we can build and run Emacs in terminal on macOS **without** NS/X11/PGTK.
- Also freeze “we are not tackling tree-sitter now” by configuring with `--with-tree-sitter=no`.

Suggested baseline configure shape (exact flags may be adjusted after the first successful run)
- Disable GUI backends:
  - `--with-ns=no`
  - `--with-pgtk=no`
  - `--with-x-toolkit=no` (and, if supported by the generated `configure`, `--with-x=no`)
- Reduce moving parts while we focus on the Lisp engine rewrite:
  - `--with-tree-sitter=no`

Note on native compilation
- Because the long-term direction is “Emacs Lisp implemented inside SBCL”, Emacs’s current ELisp
  native compilation (libgccjit producing `.eln`) is not a goal and does not make architectural
  sense long-term. We will:
  - Treat all `:nativecomp`-tagged tests as irrelevant for conformance (our conformance target is
    the SBCL-hosted engine, not libgccjit output).
  - Keep it deleted; ELisp runs as SBCL code in the long-term design.

Note on dynamic modules
- This fork removes Emacs dynamic module support entirely (and removes the
  module tests/resources).
- Rationale: the module test binary was unstable on macOS, and dynamic modules
  are not in scope for the SBCL-hosted ELisp engine direction.

0.3 Run baseline tests
- Use the stock harness via mise: `mise run test:check`.

Acceptance criteria
- From a clean checkout, we can build a TTY-only Emacs on macOS and run
  `mise run test:check` with failures understood and recorded (if any are
  fork-related).


## Step 0a — Large Deletions (repo trim)

Goal: delete entire ports and clearly irrelevant historical/metadata so the forthcoming SBCL work isn’t buried under unrelated platform glue.

Important: This step should be done *after* Step 0 baseline, and in chunks that preserve build+test green at each chunk boundary.

### 0a.1 Delete unsupported OS ports (definite)

Reality check
- This repo already appears to have most legacy OS port code removed (e.g.
  we do not currently have the usual `src/w32*.c` or `src/msdos.c` files).
- Treat “delete old ports” as an *invariant to maintain*, not a large new
  deletion step.  Enforce via:
  - grep-based guardrails (`mise run trim:check`)
  - configure defaults that keep us on the TTY-only path

Notes
- `doc/emacs/windows.texi` is the Emacs “windows” chapter (not MS Windows).
- If we later want to delete remaining documentation nodes about removed ports,
  do it as a dedicated doc cleanup step (and be prepared to fix texinfo menus).

Acceptance criteria
- After any trim chunk, a TTY-only build still succeeds on macOS and the Step 1
  smoke tests (defined below) still run.

Notes from the first trim iterations
- `admin/unidata/` was removed to reduce repo size and reduce regeneration
  surface area.  We treat `lisp/international/{charprop,charscript,emoji-zwj}.el`
  as vendored/generated inputs for now.
- One upstream test used `admin/unidata/NormalizationTest.txt`; that file now
  lives at `test/data/unicode/NormalizationTest.txt`.

### 0a.2 Delete ELisp native compilation / JIT infrastructure (definite)

Rationale
- With SBCL as the host runtime, “compiling and running Emacs Lisp” becomes compiling/running SBCL,
  so maintaining a parallel ELisp JIT (libgccjit -> `.eln`) is wasted effort and complexity.

Current state (this repo)
- Native compilation is hard-disabled in `configure.ac` and stubbed in both C
  (`src/comp.c`) and Lisp (`lisp/emacs-lisp/comp*.el`) so callers get a clear
  failure or `nil` rather than partial behavior.
- Tests that require native compilation are skipped (`:nativecomp` and explicit
  guards).

Optional future cleanup
- If we want to reduce surface area further, we can delete additional native
  compilation codepaths while keeping only the minimal compatibility stubs
  required for upstream Lisp code to load cleanly.

Acceptance criteria
- `configure` has no native-compilation option, build does not mention libgccjit, and test selection
  no longer includes native-comp-specific suites.

### 0a.3 Make the build TTY-only (then delete GUI backends)

We want “TTY-only” to mean: no GUI backends built, and no GUI-only runtime assets required.

Recommended approach (two-phase, to reduce risk)

1) Gate at configure/build time first
   - Ensure a configure invocation exists that **disables** NS/X11/PGTK and still builds.
   - Keep the GUI directories in-tree temporarily but not compiled/linked.

2) Physically delete GUI-only directories once stable
   - Done in this fork:
     - `nextstep/` (NS/Cocoa port glue)
     - `lwlib/` and `oldXMenu/` (X11 GUI support)
     - `src/`: GUI backend sources removed (and makefile entries updated):
       - NS/Cocoa: `src/ns*.m`, `src/nsterm.*`, `src/nsfns.*`, `src/nsselect.*`, etc.
       - X11: `src/xterm.c`, `src/xfns.c`, `src/xmenu.c`, `src/xselect.c`, `src/xsettings.c`, `src/xwidget.c`, etc.
       - PGTK/GTK: `src/pgtk*`, `src/gtkutil.*`, `src/emacsgtkfixed.*`, etc.
       - Note: `src/xwidget.h` is intentionally kept for non-xwidget stub inlines when `HAVE_XWIDGETS` is off.
   - Lisp: GUI-only integration removed once no longer reachable:
     - `lisp/term/common-win.el`
     - `lisp/term/x-win.el`, `lisp/term/ns-win.el`, `lisp/term/pgtk-win.el`
     - `lisp/x-dnd.el`, `lisp/pgtk-dnd.el`
     - `test/lisp/x-dnd-tests.el` (now-irrelevant test for removed feature)

Guardrail
- Do **not** delete core display infrastructure that TTY still uses (e.g., `src/xdisp.c` is not “X11”; it is core redisplay).

Acceptance criteria
- `./configure` (or its `mise` wrapper) can produce a build with no GUI backends.
- The resulting `src/emacs` runs in a terminal and can run batch tests (`mise run test:check`).

### 0a.4 Delete high-churn historical metadata (definite + optional)

Definite (safe, not needed for building/running)
- Component NEWS files in `etc/`: `etc/*-NEWS` (e.g. `EGLOT-NEWS`, `ERC-NEWS`, `CALC-NEWS`, `NXML-NEWS`, `ORG-NEWS`, `MH-E-NEWS`)
- `etc/HISTORY`

Optional (policy choice; safe for build, but may be useful for archaeology)
- `etc/AUTHORS`
- Any remaining release-note collections under `etc/` if present in future

Acceptance criteria
- Build/test behavior unchanged; we explicitly accept that `C-h n` and historical release-note browsing may no longer work.


## Step 0b — mise: toolchains + tasks (no more tribal build incantations)

Goal: routine work happens via `mise run ...` so we can evolve away from make/autotools over time, but without breaking short-term productivity.

Deliverables (first pass)
- `mise.toml` (or `.mise.toml`) pinning toolchains we control:
  - `sbcl` (required)
  - any other pinned developer tools we can realistically manage (formatters, scripting runtimes, etc.)
- `.mise/tasks/*` file tasks for anything non-trivial (argument parsing, multi-step orchestration).

Task UX requirements (non-negotiable)
- `mise run <task> --help` prints help, exits 0, and does no work.
- Prefer file tasks for top-level tasks so `--help` is side-effect free (avoid `depends` at top-level help surfaces).

Proposed task namespace (sketch)
- `bootstrap` (runs `./autogen.sh` when needed)
- `configure:tty` (out-of-tree build dir; pins `--with-tree-sitter=no`, disables GUI backends, and records configure args)
- `build` (incremental; default `-j` based on CPU; produces `build/.../src/emacs`)
- `bootstrap:make` (runs `make bootstrap` in the build dir when incremental build gets confused)
- `lisp:autoloads` (runs the documented `make -C lisp autoloads` when needed)
- `run` (runs the built TTY Emacs with a minimal environment)
- `test:smoke` (fast, deterministic subset; see Step 1)
- `test:check` (full default suite: `make -C <build>/test check`)
- `test:check-all` (optional: `make -C <build>/test check-all`)
- `test:file` (runs a specific `test/<path>.el` target via `make -C <build>/test <path>.log`)
- `clean` / `distclean` / `clobber` (with confirmation for destructive actions)

Build directory convention (so incremental builds stay predictable)
- `build/macos-tty/` as the default local build output directory.
- Later: `build/linux-tty/`, `build/freebsd-tty/` for CI/other machines.

Task parameters we will likely need (design for these early)
- `--jobs <n>`: passed through to `make -j`.
- `--clean` / `--distclean`: predictable cleanup modes.
- `--configure-arg <arg>` (repeatable): for experimentation without editing task code.
- `--cc <cc>` and `--cflags <cflags>`: so we can switch between `clang` and variants deterministically.

Acceptance criteria
- From a clean checkout on macOS: `mise run build` produces a working TTY Emacs.
- Re-running `mise run build` after a small edit is incremental (does not re-run everything).
- `mise run test:smoke` and `mise run test:check` work and have stable output conventions.


## Step 1 — Surface Emacs Lisp tests (smoke + full suite)

Goal: make it obvious which test suites define “Emacs Lisp engine conformance”, and provide a fast loop while rewriting the engine.

Facts we will leverage (already in tree)
- `test/README` documents selectors and targets.
- `test/Makefile.in` supports:
  - `make -C <build>/test check` (default selector)
  - `make -C <build>/test check-all`, `check-expensive`
  - `make -C <build>/test <filename>.log` or `make -C <build>/test <dirname>`-scoped checks

### 1.1 Define a *TTY + engine-focused* smoke suite

Design criteria
- Runs in terminal/batch; no GUI assumptions.
- No network dependency; no “remote tramp” requirements; minimal filesystem brittleness.
- Targets core semantics: reader, evaluator, environments, function call, macros, bytecode, basic types.

Initial candidate smoke files (all exist in this repo today)
- `test/src/alloc-tests.el`
- `test/src/eval-tests.el`
- `test/src/lread-tests.el`
- `test/src/syntax-tests.el`
- `test/lisp/emacs-lisp/lisp-tests.el` (broad core semantics coverage)
- `test/lisp/emacs-lisp/macroexp-tests.el`
- `test/lisp/emacs-lisp/bytecomp-tests.el`
- `test/lisp/emacs-lisp/cl-lib-tests.el`
- `test/lisp/emacs-lisp/subr-x-tests.el`
- `test/lisp/emacs-lisp/ert-tests.el`

Deliverable
- A documented command (via `mise run test:smoke`) that runs exactly this set (and any additional files we add later), with clear pass/fail reporting.

### 1.2 Define the “full suite” we claim conformance against

Default full suite
- `make -C <build>/test check` (or `mise run test:check`)

Optional fuller suites (for later)
- `make -C <build>/test check-all`
- `make -C <build>/test check-expensive`

Acceptance criteria
- We can run smoke tests quickly and deterministically during development.
- We can run the full suite before/after major milestones and interpret failures (skip vs regression vs known upstream flake).

## Step 1.5 — SBCL Ecosystem Dependencies + Dev Loop Design

Timing
- Do this after we have trimmed the repo (Step 0a) and have stable `mise` build/test tasks (Step 0b/1),
  but before the SBCL-hosted engine rewrite becomes “real work” (Step 2).

Goal
- Decide what (if anything) from the Common Lisp/SBCL ecosystem is in scope as *opt-in* dependencies,
  and lock down a development workflow that maximizes feedback speed (REPL, debugging, tests).

### 1.5.1 Dependency policy (opt-in, justified)

Default stance
- Start with **ANSI Common Lisp + SBCL** only. No third-party dependencies by default.

Rules for adding a dependency
- Must have a clear, written justification tied to one of:
  - significant code clarity reduction in the engine implementation
  - a facility we would otherwise have to reimplement poorly (testing, tracing, FFI ergonomics, etc.)
  - measurable development speedup with low ongoing maintenance cost
- Must be widely used and actively maintained (or extremely stable).
- Must not pull in an uncontrolled dependency tree (keep transitive deps small and understandable).
- Must run on our target SBCL platforms (macOS now; Linux/FreeBSD later).
- Must be version-pinnable and reproducible.

Versioning and reproducibility (choose one approach early)
- A: vendor dependencies into the repo (explicit version control, no network fetch at build time).
- B: use ASDF + a pinned Quicklisp/Ultralisp snapshot (reproducible but bootstrap complexity).
- C: use git submodules (explicit pinning, but submodule ergonomics).

Deliverable
- A short “dependency decision record” in this plan (or a `plans/` note later) listing:
  - which dependency mechanism we chose (A/B/C) and why
  - the approved dependency list (possibly empty)
  - the “no-go” list (things we explicitly avoid)

### 1.5.2 Candidate libraries to evaluate (examples, not commitments)

We only adopt these if they pass the above rules and we can defend the choice:
- Small utility layer: `alexandria` (widely used helpers)
- FFI bridge (if/when we need it): `cffi`
- Testing framework (for SBCL-side unit tests): `fiveam` or `parachute`
- Structured logging/tracing (if SBCL built-ins are insufficient): to be selected deliberately

### 1.5.3 Tight feedback loop (design before implementation)

Requirements
- A fast way to iterate on the SBCL-hosted engine without “rebuild the world” cycles.
- First-class debugging: reproducible crashes, stack traces, and easy stepping through engine code.
- Unified test story: SBCL-side unit tests + Emacs ERT conformance tests, both runnable from `mise`.

Planned workflow (high-level)
- Provide `mise` tasks for:
  - starting an SBCL REPL in the right project context
  - running SBCL-side unit tests quickly
  - running Emacs ERT smoke/full suites (already Step 1)
- Decide how we capture debug artifacts:
  - SBCL debugger output
  - core dumps/backtraces for C/SBCL boundary issues
  - a minimal “engine trace” facility for tricky semantic mismatches

Acceptance criteria
- We can change engine code and re-run the SBCL-side unit tests in seconds.
- We can run `test:smoke` frequently and `test:check` as a gate, with failures easy to triage.


## Step 2 — Rewrite Emacs Lisp engine to SBCL-hosted implementation

This is the main project. The plan here must be explicit about *milestones* and *acceptance criteria*, and conservative about unverified assumptions.

### 2.0 Architecture spike: decide how SBCL is embedded

Questions to answer (must be resolved early)
- How does `src/emacs` start/own the SBCL runtime?
- How do we represent Lisp values across the boundary (C <-> CL) without GC hazards?
- How do we call “primitive” operations that remain implemented in C while the engine is in CL?

Deliverable
- A written “engine boundary contract” (what is implemented in CL vs C, and the calling convention).

Acceptance criteria
- We can start Emacs and evaluate a minimal Emacs Lisp form via the SBCL-hosted engine, in the real command loop (not just a toy harness).

### 2.1 Port plan for the “C-defined Lisp core”

Scope we must eventually reimplement (high-level)
- The evaluator and apply/funcall machinery currently in C.
- The reader (or an equivalent that produces identical Lisp objects/semantics).
- Core object model (symbols, conses, vectors, strings, numbers, hash tables, markers, etc.) with correct printing and equality semantics.
- The “defuns/defmacros in C” surface area (every primitive exposed to Lisp must exist and behave correctly).

Approach: stage the port so tests can drive correctness

Milestones (suggested)
- M1: Reader + printer parity for basic types; passes `test/src/lread-tests.el`
- M2: Core eval/apply parity for special forms and function call; passes smoke suite subset (`eval-tests`, `macroexp-tests`)
- M3: Bytecode execution parity (if we keep bytecode); passes `bytecomp-tests` / `byte-run-tests` as relevant
- M4: Expand smoke suite; pass full `make -C <build>/test check` with a documented exception list (ideally empty)

Acceptance criteria
- Each milestone gates on the corresponding test targets in Step 1.

### 2.2 Internal “unquote” escape hatch (SBCL host interop)

Goal
- Provide a controlled, internal mechanism for embedded Emacs Lisp to call into SBCL (host) for implementation and experimentation.

Constraints
- Must not leak as an unstable user-facing feature by default.
- Must be testable and auditable (used for primitives and bridge code, not arbitrary eval injection in production).

Acceptance criteria
- We can implement at least one non-trivial primitive via the escape hatch and cover it with an existing ERT test.


## Prep Done Definition (end of Steps 0a/0b/1/2 “prep” portion)

We are “done with prep” when:

- We can build a TTY-only Emacs on macOS using a single command (`mise run build`).
- Incremental builds work (small C/Lisp edits do not trigger full rebuilds).
- We can run `mise run test:smoke` and `mise run test:check` reliably.
- Unsupported OS ports and obviously irrelevant historical files are deleted (as per Step 0a), with a tag preserved for easy archaeology.
- We have a written engine boundary contract and an agreed milestone/test gating strategy for the SBCL-hosted engine rewrite.


## Later (explicitly deferred)

- Tree-sitter “through and through” (including PPSS replacement): revisit only after SBCL-hosted engine conformance is in a good place.
- Browser-only frontend: keep in mind when making architectural choices, but do not pre-optimize now.
