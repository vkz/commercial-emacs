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
- The test harness is standard Emacs: `test/README` + `test/Makefile.in` using ERT selectors and `make -C test check` / `check-all` / file-specific targets.


## Constraints / Non-goals

Hard constraints
- **TTY-only runtime**: we build/run in terminal only.
- **SBCL only** for the Common Lisp host.
- **Primary dev platform is macOS on this machine** (Linux/FreeBSD testing comes later).

Out of scope (for this plan revision)
- Tree-sitter work (we will not improve it now; we’ll only avoid breaking it).
- Moving GC work (we will not use it; SBCL GC is the path).
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
  - `--without-native-compilation`
  - `--with-tree-sitter=no`

0.3 Run baseline tests
- Use the stock harness: `make -C test check` (default selector excludes `:expensive-test`, `:unstable`, `:nativecomp`).

Acceptance criteria
- From a clean checkout, we can build a TTY-only Emacs on macOS and run `make -C test check` with failures understood and recorded (if any are fork-related).


## Step 0a — Large Deletions (repo trim)

Goal: delete entire ports and clearly irrelevant historical/metadata so the forthcoming SBCL work isn’t buried under unrelated platform glue.

Important: This step should be done *after* Step 0 baseline, and in chunks that preserve build+test green at each chunk boundary.

### 0a.1 Delete unsupported OS ports (definite)

These are large, unambiguously out of scope for modern macOS/Linux/FreeBSD:

- Windows / NT / Cygwin
  - Directories: `nt/`, `admin/nt/`
  - Build glue: `config.bat`
  - `src/` objects and headers: `src/w32*`, `src/cygw32.*`, `src/w32*.h`
  - Lisp: `lisp/w32-fns.el`, `lisp/w32-vars.el`, `lisp/dos-w32.el`, `lisp/term/w32-*.el`, `lisp/term/w32console.el`
  - Docs: `doc/emacs/windows.texi`, `doc/lispref/windows.texi`, `doc/misc/efaq-w32.texi`

- MS-DOS
  - `src/` objects and headers: `src/msdos.*`, `src/dosfns.*`
  - Lisp: `lisp/dos-fns.el`, `lisp/dos-vars.el`, and any remaining msdos-only helpers
  - Docs: `doc/emacs/msdos.texi`, `doc/emacs/msdos-xtra.texi`

- Haiku
  - `src/`: `src/haiku*` (C and C++ sources/headers)
  - Lisp: `lisp/term/haiku-win.el` (and any haiku-specific `declare-function` callers)
  - Docs: `doc/emacs/haiku.texi`

Notes
- Android port code does not appear to be present under `src/` in this repo; references in Lisp/docs are fine to prune later if desired, but don’t block the TTY/SBCL work.

Acceptance criteria
- After each port deletion chunk, a TTY-only build still succeeds on macOS and the Step 1 “smoke tests” (defined below) still run.

### 0a.2 Make the build TTY-only (then delete GUI backends)

We want “TTY-only” to mean: no GUI backends built, and no GUI-only runtime assets required.

Recommended approach (two-phase, to reduce risk)

1) Gate at configure/build time first
   - Ensure a configure invocation exists that **disables** NS/X11/PGTK and still builds.
   - Keep the GUI directories in-tree temporarily but not compiled/linked.

2) Physically delete GUI-only directories once stable
   - Directories that become deletable once we truly stop building any GUI:
     - `nextstep/` (NS/Cocoa port glue)
     - `lwlib/` and `oldXMenu/` (X11 GUI support)
   - `src/`: delete GUI-backend objects (and their makefile entries) such as:
     - NS/Cocoa: `src/ns*.m`, `src/nsterm.*`, `src/nsfns.*`, `src/nsselect.*`, etc.
     - X11: `src/xterm.c`, `src/xfns.c`, `src/xmenu.c`, `src/xselect.c`, `src/xsettings.c`, `src/xwidget.*`, etc.
     - PGTK/GTK: `src/pgtk*`, `src/gtkutil.*`, `src/emacsgtkfixed.*`, etc.
   - Lisp: delete GUI-only integration files when they are no longer reachable:
     - `lisp/term/ns-win.el`, `lisp/term/pgtk-win.el` (and any other GUI-only `*-win.el`)
     - `lisp/pgtk-dnd.el` (and other GUI-only integration)

Guardrail
- Do **not** delete core display infrastructure that TTY still uses (e.g., `src/xdisp.c` is not “X11”; it is core redisplay).

Acceptance criteria
- `./configure` (or its `mise` wrapper) can produce a build with no GUI backends.
- The resulting `src/emacs` runs in a terminal and can run batch tests (`make -C test check`).

### 0a.3 Delete high-churn historical metadata (definite + optional)

Definite (safe, not needed for building/running)
- Component NEWS files in `etc/`: `etc/*-NEWS` (e.g. `EGLOT-NEWS`, `ERC-NEWS`, `CALC-NEWS`, `NXML-NEWS`, `ORG-NEWS`, `MH-E-NEWS`)
- `etc/HISTORY`

Optional (policy choice; safe for build, but may be useful for archaeology)
- `etc/AUTHORS`
- Some of `admin/notes/*` (developer-process docs)
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
- `test:check` (full default suite: `make -C test check`)
- `test:check-all` (optional: `make -C test check-all`)
- `test:file` (runs a specific `test/<path>.el` target via `make -C test <path>.log`)
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
  - `make -C test check` (default selector)
  - `make -C test check-all`, `check-expensive`
  - `make -C test <filename>.log` or `make -C test <dirname>`-scoped checks

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
- `test/lisp/emacs-lisp/eval-tests.el`
- `test/lisp/emacs-lisp/macroexp-tests.el`
- `test/lisp/emacs-lisp/bytecomp-tests.el`
- `test/lisp/emacs-lisp/cl-lib-tests.el`
- `test/lisp/emacs-lisp/subr-x-tests.el`
- `test/lisp/emacs-lisp/ert-tests.el`

Deliverable
- A documented command (via `mise run test:smoke`) that runs exactly this set (and any additional files we add later), with clear pass/fail reporting.

### 1.2 Define the “full suite” we claim conformance against

Default full suite
- `make -C test check`

Optional fuller suites (for later)
- `make -C test check-all`
- `make -C test check-expensive`

Acceptance criteria
- We can run smoke tests quickly and deterministically during development.
- We can run the full suite before/after major milestones and interpret failures (skip vs regression vs known upstream flake).


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
- M4: Expand smoke suite; pass full `make -C test check` with a documented exception list (ideally empty)

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
