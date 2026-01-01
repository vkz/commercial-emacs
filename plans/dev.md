# Dev Notes (Step 0/1 iteration)

This file records issues, discoveries, and proposed tooling improvements from
the first large trimming + build/test iteration (steps 0 and 1 in `plan.md`).

## Summary of what worked

- Out-of-tree **TTY** build on macOS works via `mise` tasks.
- A fast smoke suite exists and is practical for repeated runs:
  - `mise run test:smoke` (and/or `make -C build/.../test -B ...`).
- Large-scale repo trimming is feasible as long as build-system references are
  updated immediately and verified using the tasks.

## Problems encountered (and lessons)

### 0) Commit-message hooks are strict

Symptom:

- `git commit` warned about long lines / very long words in commit messages and
  pointed to `CONTRIBUTE`.

Lesson:

- Keep commit messages short and wrapped (body ~72 columns). Avoid very long
  unbroken strings.

### 1) Manual/documentation builds broke after removing platform chapters

Symptom:

- `make -C doc/emacs info` produced many texinfo errors about missing nodes
  (MS-DOS/Windows/Haiku references and menus).

Root cause:

- Platform chapters were removed, but upstream manuals contain cross-references
  and menus that still refer to those nodes.

What we did:

- Changed `mise run build` to build only the core editor target (`make ... src`)
  and not manuals.

Proposed improvement:

- Add explicit tasks for manuals and keep them opt-in:
  - `mise run docs:info` / `docs:pdf` which run the doc targets and fail fast.
- Add a follow-up trimming task to either:
  - comprehensively remove/update texinfo refs and menus, or
  - re-add platform chapters as documentation-only (if we want manuals intact).

Agentic note:

- Avoid broad `make` targets (e.g. default `all`) during trimming; prefer
  `src` and targeted tests until docs are reconciled.

### 2) Native compilation removal caused bootstrap/pdump failures in subtle ways

Symptom:

- Build failed during pdump / bootstrap due to void variables:
  - `no-native-compile`
  - `no-byte-compile`

Root cause:

- `admin/relative-lisp-files.el` uses `hack-local-variables` and expects those
  variables to exist when scanning file-local directives.
- Upstream defines these via native-comp codepaths/autoloads; after stripping,
  they became undefined.

What we did:

- Provided minimal definitions in the `comp.el` stub:
  - `no-native-compile` and `no-byte-compile` (and marked them safe locals).

Proposed improvements:

- Add a focused task `mise run doctor` that performs:
  - `rg` checks for removed features reappearing (e.g. `.eln`, libgccjit).
  - a tiny `--batch` check that loads core bootstrap helpers and asserts
    expected invariants (e.g. `(native-comp-available-p)` is nil).

### 3) Configure/task drift created avoidable warnings

Symptom:

- `configure` warned about an unrecognized option we were still passing from a
  task (a removed `--without-native-compilation` flag).

Lesson:

- When we hard-disable a feature in `configure.ac`, the tasks must be updated
  immediately to avoid noisy output and confusion.

Proposed improvements:

- Add a `mise run configure:tty -- --show-args` habit in review checklists.
- Consider emitting the configure args into a stable file:
  - `build/<name>/configure.args` for easier diffs in future changes.

### 4) Rebuild signal quality: smoke tests can appear "up to date"

Symptom:

- `mise run test:smoke` reported targets "up to date" and returned quickly,
  even when we wanted a true rerun after internal changes.

Lesson:

- For confidence during trimming, we sometimes need a forced rebuild.

Proposed improvement:

- Add `--force` flag to `.mise/tasks/test/smoke` that passes `-B` to make.
  (We used `make -B` manually once to confirm.)

### 5) Generated headers should not live in the source tree

Lesson:

- This repo is a fork-of-a-fork; out-of-tree expectations are fragile.
  Generating config-dependent headers in the source tree leads to confusion.

Proposed improvements:

- Keep tightening out-of-tree assumptions:
  - If a path under the build dir is expected, ensure the task creates it.
  - Prefer build-dir generated files over source-dir mutation.

## Tooling proposals to improve future agent performance

1) Add `mise run doctor` (new task)
   - Verify prerequisites: `autoconf`, `automake`, `texinfo` (makeinfo), etc.
   - Verify supported host OS and that `configure` will error out on others.
   - Verify native-comp is disabled:
     - `./build/.../src/emacs -Q --batch --eval '(kill-emacs (if (native-comp-available-p) 1 0))'`

2) Add `mise run clean` (new task)
   - Remove `build/<name>` (configurable) and regenerate symlink tree.
   - Should be explicit and safe (confirm / dry-run).

3) Add `mise run docs:info` (new task)
   - Opt-in doc build to surface broken texi references when desired.
   - Keep default `build` task doc-free.

4) Add `mise run test:smoke -- --force`
   - Forces rebuilding test logs by passing `-B` to `make`.

5) Add `mise run trim:check` (new task)
   - Grep-based guardrails to prevent reintroducing removed ports/features:
     - `nt/`, `w32`, `msdos`, `haiku` sources
     - libgccjit probes, `.eln` references, native-comp configure flags

## Verification checklist for each trimming change

- `mise run bootstrap -- --force` (after touching `configure.ac` / m4)
- `mise run configure:tty -- --force`
- `mise run build`
- `mise run run` (smoke: `--version` and a quick batch eval)
- `mise run test:smoke` (use forced mode when changing core load/bootstrap)
