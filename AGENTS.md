<INSTRUCTIONS>
# clmacs AGENTS.md (project-local)

These instructions are for agentic work in this repository.  They capture
constraints discovered during the Step 0/1 trimming + build/test work.

## Project direction (high-level)

- Primary target is a **TTY-only** Emacs build.
- Current development is **macOS-only on this machine**; other platforms are
  added later for CI/testing.
- Supported platforms for this fork are **macOS (darwin)**, **GNU/Linux
  (gnu-linux)**, and **FreeBSD (freebsd)** only.
  - `configure.ac` hard-errors for other `opsys` values.
- ELisp **native compilation (libgccjit / .eln)** is intentionally disabled.
  - `native-comp-available-p` always returns nil.
  - `lisp/emacs-lisp/comp*.el` are stubs that error if used.
- Future direction is an SBCL-hosted ELisp engine; until then we keep
  building/running Emacs normally as a TTY editor and use tests to keep parity.

## Golden acceptance criteria (while trimming / assimilating)

After any trimming/refactor iteration:

- `mise run build` produces working `emacs` and `emacsclient`.
- `mise run run` starts Emacs in a terminal and behaves like upstream
  (modulo explicitly removed features/ports).
- `mise run test:smoke` passes (fast conformance signal).
- The build is out-of-tree and repeatable with incremental rebuilds.

## Workflows (use mise)

All project tasks should be run via `mise` (prefer `mise run ...`).

### Canonical build flow (macOS TTY)

- `mise run bootstrap`
  - Runs `./autogen.sh` if needed.
- `mise run configure:tty`
  - Configures an out-of-tree build in `build/macos-tty` by default.
- `mise run build`
  - Builds the core editor (`make -C build/... src`).
  - Note: this intentionally does **not** build manuals by default.
- `mise run run`
  - Runs the built Emacs in TTY mode (see `.mise/tasks/run`).
- `mise run test:smoke`
  - Runs a small ERT-focused set of test targets under `build/.../test`.
- `mise run test:check` / `mise run test:check-all`
  - Upstream-style test entrypoints; these may fail during trimming and should
    be treated as longer-term convergence targets.

### Running a single test file

- `mise run test:file -- --path <relative-test-path>`
  - Example: `mise run test:file -- --path lisp/emacs-lisp/ert-tests.log`

## Gotchas (important)

### Out-of-tree builds require a "runtime symlink tree"

This repo still expects some arch-independent runtime files to exist by
relative paths in the build tree.  The `mise run build` task creates symlinks
from the source tree into the build dir for:

- `etc/`, `lisp/`, `leim/`, `admin/` and subdirs used by bootstrap.

Do not replace this with `make` defaults without checking bootstrap/pdump.

### Manuals currently fail to build after platform trimming

We removed MS-DOS/Haiku/Windows-port manuals and related nodes.  Upstream docs
still contain cross-references to those nodes, so `make -C doc/... info` can
fail.

Policy:

- Default build tasks should not build manuals.
- If/when we want manuals again, we must either:
  - repair texi references/menus consistently, or
  - restore removed platform chapters as documentation-only.

### Native compilation is disabled (and should stay disabled)

Avoid reintroducing `.eln` build rules or libgccjit probing.  Prefer explicit
stubs that fail loudly if something tries to use native compilation.

## Commit discipline

- Keep commit messages ASCII-only, subject line imperative, no trailing period.
- Wrap body at ~72 columns; avoid very long unbroken strings (repo hooks check).

## Change hygiene (how to trim safely)

- Prefer deleting whole directories that are clearly out of scope (e.g. `nt/`).
- After deleting, immediately:
  - remove or gate build-system references (`configure.ac`, `Makefile.in`,
    `src/Makefile.in`, doc makefiles).
  - run `mise run bootstrap -- --force`, then `mise run configure:tty -- --force`.
  - run `mise run build` and `mise run test:smoke`.
- Be careful with ambiguous names:
  - `doc/emacs/windows.texi` is the Emacs "windows" chapter (not MS Windows).

## Where plans live

- Roadmap plan: `plan.md` (and never delete plan files).
- Developer notes / iteration notes: `plans/*.md`.

</INSTRUCTIONS>
