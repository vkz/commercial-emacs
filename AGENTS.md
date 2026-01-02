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
  - Other `opsys` values may still exist upstream, but are out of scope here.
- ELisp **native compilation (libgccjit / .eln)** is intentionally disabled.
  - `native-comp-available-p` always returns nil.
  - `lisp/emacs-lisp/comp*.el` are stubs that error if used.
- Emacs dynamic modules support is **removed** in this fork.
- Future direction is an SBCL-hosted ELisp engine; until then we keep
  building/running Emacs normally as a TTY editor and use tests to keep parity.

## Golden acceptance criteria (while trimming / assimilating)

After any trimming/refactor iteration:

- `mise run build` produces working `emacs` and `emacsclient`.
- `mise run run` starts Emacs in a terminal and behaves like upstream
  (modulo explicitly removed features/ports).
- `mise run test:smoke` passes (fast conformance signal).
- The build is out-of-tree and repeatable with incremental rebuilds.

## Agent expectations (how to collaborate)

While working in this repo, agents should actively look for friction and
failures in build, tests, and infra. In the final summary for each task, call
out any issues encountered and propose at least one concrete fix path:

- remove or change assumptions / redefine the problem
- implement tools/scripts/mise tasks to automate the fix
- add or improve AGENTS instructions to prevent repeats
- add or adjust tests to avoid false negatives

If a tool/task will materially shorten the current work *and* improve future
iterations, implement it immediately (prefer a `mise` file task).

## Workflows (use mise)

All project tasks should be run via `mise` (prefer `mise run ...`).

### Canonical build flow (macOS TTY)

- `mise run bootstrap`
  - Runs `./autogen.sh` if needed.
- `mise run configure:tty`
  - Configures an out-of-tree build in `build/macos-tty` by default.
  - The canonical TTY configure disables GUI backends and tree-sitter.
- `mise run build`
  - Builds the core editor (`make -C build/... src`).
  - Note: this intentionally does **not** build manuals by default.
- `mise run run`
  - Runs the built Emacs in TTY mode (see `.mise/tasks/run`).
- `mise run test:smoke`
  - Runs a small ERT-focused set of test targets under `build/.../test`.
- `mise run test:check` / `mise run test:check-all`
  - Runs the upstream harness in `build/.../test` (does not build manuals).

### Running a single test file

- `mise run test:file -- <relative-test-path>`
  - Example: `mise run test:file -- lisp/emacs-lisp/ert-tests`

### Trim verification helpers

- `mise run trim:check` (fast guardrails)
- `mise run verify -- --level fast` (build + run + smoke)
- `mise run verify -- --level check` (adds `make check`)

### Tooling helpers

- `mise run doctor` (and `mise run doctor -- --check-build`)
- `mise run clean` / `mise run clean -- --distclean`
- `mise run clobber` (dry-run) / `mise run clobber -- --yes`

### Manuals (opt-in)

Manual builds are intentionally opt-in and kept out of the core build/test
loops:

- `mise run docs:info`
- `mise run docs:html`
- `mise run docs:pdf`
- `mise run docs:dir` (regenerates `info/dir`, dirties git; opt-in)

Doc editing policy (when we touch texinfo)
- Do not point users at upstream Emacs docs for removed features.
- If a feature/platform is removed here, remove its texinfo node and update
  menus/cross-refs accordingly (do not keep dead chapters around).

## Gotchas (important)

### Out-of-tree builds require a "runtime symlink tree"

This repo still expects some arch-independent runtime files to exist by
relative paths in the build tree.  The `mise run build` task creates symlinks
from the source tree into the build dir for:

- `etc/`, `lisp/`, `leim/`, `admin/` (notably `admin/charsets/` used at build time).

Do not replace this with `make` defaults without checking bootstrap/pdump.

### Top-level `make check` is not the preferred test entrypoint

Running `make -C build/... check` can pull in extra build work (including docs)
depending on makefile wiring. Prefer `mise run test:check`, which runs
`make -C build/.../test check` directly.

### Manual builds can dirty the source tree if invoked incorrectly

Top-level `make info` regenerates `info/dir` under the source tree. Prefer
`mise run docs:info`, which builds `*-info` targets without updating `info/dir`.

### Native compilation is disabled (and should stay disabled)

Avoid reintroducing `.eln` build rules or libgccjit probing.  Prefer explicit
stubs that fail loudly if something tries to use native compilation.

## Commit discipline

- Keep commit messages ASCII-only, subject line imperative, no trailing period.
- Wrap body at ~72 columns; avoid very long unbroken strings (repo hooks check).

## Change hygiene (how to trim safely)

- Prefer deleting whole directories that are clearly out of scope (e.g.
  `nextstep/`, `lwlib/`, `oldXMenu/`).
- After deleting, immediately:
  - remove or gate build-system references (`configure.ac`, `Makefile.in`,
    `src/Makefile.in`, doc makefiles).
  - run `mise run bootstrap -- --force`, then `mise run configure:tty -- --force`.
  - run `mise run verify -- --level check --force`.
- Be careful with ambiguous names:
  - `doc/emacs/windows.texi` is the Emacs "windows" chapter (not MS Windows).

### Bash + `set -u` arrays

Avoid expanding empty arrays under `set -u` (e.g. `"${arr[@]}"`), since Bash
will treat that as an unbound variable. Prefer simple `if` branches for
optional flags (see `.mise/tasks/test/*`).

## Where plans live

- Roadmap plan: `plan.md` (and never delete plan files).
- Developer notes / iteration notes: `plans/*.md`.

</INSTRUCTIONS>
