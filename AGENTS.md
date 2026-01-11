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
- GUI backends are **removed** in this fork:
  - `nextstep/`, `lwlib/`, `oldXMenu/`
  - GUI-backend sources under `src/` (NS/X11/PGTK)
- GUI-only Elisp integration is **removed** in this fork:
  - `lisp/term/common-win.el`, `lisp/term/x-win.el`, `lisp/term/ns-win.el`,
    `lisp/term/pgtk-win.el`
  - `lisp/x-dnd.el`, `lisp/pgtk-dnd.el` (and the now-irrelevant
    `test/lisp/x-dnd-tests.el`)
- Future direction is an SBCL-hosted ELisp engine; until then we keep
  building/running Emacs normally as a TTY editor and use tests to keep parity.

## Guiding documents (read these first)

Start here for current intent and constraints, in this order:

- `AGENTS.md`: repo-wide invariants, workflows, and gotchas.
- `plan.md`: the current, actionable plan and milestones.
- `plans/clemacs.md`: Option B ("clemacs") architecture and branch-specific
  decisions (B1 handle-based substrate, CL-first Elisp dialect stance).
- `plans/agent-playbook.md`: operational bring-up runbook (commands + decision tree).

Related/background (useful when debating architecture, but not the day-to-day plan)
- `plans/emacl.md`: Option A ("emacl") alternative (C-hosted Emacs, embed SBCL).
- `plans/cl.md`: earlier design discussion and rationale snapshots.

You must update `plan.md` clearly marking every finished task as DONE.

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

Commit your work before the final report. If meaningfully useful split
into multiple commits.

Finish the final summary by proposing next high-leverage steps to tackle.

Introspection rule (required)
- If you get stuck or rediscover a technique that helps (a reliable debug flag,
  a missing helper task, a clearer failure interpretation): add exactly **one**
  new bullet to `plans/agent-playbook.md` **or** add exactly **one** new helper
  task/subcommand. Keep it minimal and high-signal.

## Breadcrumb discipline (required for clemacs)

Interpreter-first bring-up is intentionally temporary: the long-term goal is to
compile ELisp to CL (or a CL-ish IR) and let SBCL compile it. That means we
must not “lose” the semantic discoveries we make while bootstrapping.

When you change ELisp semantics, compatibility shims, or loader behavior:

- Add a focused microtest to `clemacs/contract/semantics.microtests.sexp`.
  - Prefer `:emacs :match` tests when we aim to be Emacs-faithful.
  - If a test is intentionally not Emacs-faithful, set `:emacs nil` and add a
    dated rationale to `plans/clemacs-compat.md` (“Semantic decisions”).
- If the discovery constrains the eventual ELisp→CL compiler/codegen, update
  `plans/clemacs-compat.md` (“Compiler/codegen notes”) in the same patch.
- If the change affects what “startup” means in clemacs, update the relevant
  manifest(s) under `clemacs/contract/startup.*.files` (and keep growth
  monotonic: add new entries or advance checkpoints; don’t delete to “get green”).
- If the change affects upstream ERT bring-up status, update:
  - `clemacs/contract/ert-upstream.tests` (must-pass list; monotonic growth)
  - `clemacs/contract/ert-upstream.known-fail.tests` (dated reasons; XPASS is a gate failure)
- Keep contract manifests monotonic (prefer adding new entries; don’t delete to
  “get green”).

These breadcrumbs must be updated in the same patch as the code change; don’t
leave the repo in a state where documentation/tests are knowingly stale.

## Workflows (use mise)

All project tasks should be run via `mise` (prefer `mise run ...`).
If you see `mise WARN ... not trusted`, run `mise trust` in the repo root once.

### Codex CLI / shell working directory

When running commands via the Codex CLI tool API, prefer setting the tool call's
working directory to the repo root (instead of prefixing commands with
`cd ... &&`). This keeps logs readable and avoids copy/paste noise while still
being robust across independent shell invocations.

### clemacs bring-up (SBCL-hosted, experimental)

clemacs is the experimental SBCL-hosted runtime (Option B) being brought up
alongside the baseline C-hosted Emacs build.

- Toolchain bootstrap (host CL + SBCL):
  - `mise run clemacs:bootstrap`
- Dependency management (project-local, pinned, reproducible):
  - Source of truth: `clemacs/qlfile` + `clemacs/qlfile.lock` (commit both).
  - Install deps out-of-tree: `mise run clemacs:deps:install`
  - Refresh lockfile (writes to source tree): `mise run clemacs:deps:lock`
  - Implementation detail: qlot is cloned into `build/clemacs/tools/qlot`, and
    deps are installed under `build/clemacs/deps/.qlot` with cache under
    `build/clemacs/qlot-cache` (avoid global `~/.cache/qlot`).
    - clemacs tasks also set `HOME` + XDG dirs under `build/clemacs/` to avoid
      accidentally writing global state (e.g. `~/.cache/common-lisp`).
  - Notes:
    - `clemacs/qlfile` should list only our direct deps; pinning the Quicklisp
      dist in `clemacs/qlfile.lock` pins the full dependency closure.
    - `clemacs:deps:install` symlinks `clemacs/clemacs.asd` into the deps dir
      so qlot can install transitive deps (otherwise it installs only dists).
    - On macOS, qlot can fail uninstalling old deps because its local dist uses
      cache symlinks; `clemacs:deps:install` wipes `build/clemacs/deps/.qlot`
      when the stamp changes to keep this reproducible.
- Substrate dylib:
  - `mise run clemacs:substrate:build`
- Optional: faster startup via SBCL saved core:
  - `mise run clemacs:core:build` (writes `build/clemacs/clemacs.core`)
  - `mise run clemacs:run` / `mise run clemacs:test:smoke` uses it automatically when present
- Ad-hoc SBCL eval (qlot/core aware; heredoc-friendly):
  - `mise run clemacs:sbcl:eval` (see `plans/agent-playbook.md` for examples; avoid running `sbcl`/`qlot` directly)
- Interactive TTY loop (manual testing; run inside tmux if possible):
  - `mise run clemacs:tty:run -- <optional-file>`
- Non-interactive TTY gate (PTY-driven):
  - `mise run clemacs:test:tty`
- One-command gate:
  - `mise run clemacs:verify`
- clemacs contract gate (successor to Emacs contract for clemacs):
  - `mise run clemacs:test:contract -- --level smoke`
  - `mise run clemacs:test:contract -- --level elisp-core` (smoke + inventory usage report)
  - `mise run clemacs:test:contract -- --level check` (includes `clemacs:test:ert`)
  - `mise run clemacs:test:ert` (ERT-style smoke, ELISP package)
  - `mise run clemacs:test:ert-upstream` (upstream ERT bring-up gate; must-pass list in `clemacs/contract/ert-upstream.tests`)
  - Report: `mise run clemacs:report:ert-delta` (writes `build/clemacs/reports/ert-delta.md`)
  - Report: `mise run clemacs:report:startup-delta` (writes `build/clemacs/reports/startup-delta.md`)
  - Report: `mise run clemacs:report:progress` (writes `build/clemacs/reports/progress.md`)
  - Compatibility report: `plans/clemacs-compat.md`

### clemacs bring-up: iteration accelerators

Canonical bring-up loop, debugging flags, and \"first failure\" interpretation live in
`plans/agent-playbook.md` (keep this file focused on invariants).

Short version:
- Gate: `mise run clemacs:test:contract -- --level elisp-core`
- If it fails: `mise run clemacs:report:first-failure -- --mode startup-check --debug`
- If `startup-check` is slow, bisect cheaply without editing manifests:
  `mise run clemacs:report:first-failure -- --mode startup-check --limit <n> --debug`
- Fastest semantics loop (microtests): `mise run clemacs:test:micro -- --name <substr>` (or set `CLEMACS_MICROTEST_NAME=<substr>`; add `--no-emacs` to skip ref-Emacs comparisons).

### Repo-local Codex skills

See `plans/agent-playbook.md` for when to use which.

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

### Test contract (source of truth)

- Contract data lives under `test/contract/`.
- Prefer running the contract gate when changing ELisp-core or trimming:
  - `mise run test:contract -- --level check`

### Trim verification helpers

- `mise run trim:check` (fast guardrails)
- `mise run verify -- --level fast` (build + run + smoke)
- `mise run verify -- --level check` (adds `make check`)

### C-defined ELisp inventory (pre-SBCL port checklist)

- Regenerate: `mise run inventory:regen`
- Validate: `mise run inventory:check`

### Tooling helpers

- `mise run doctor` (and `mise run doctor -- --check-build`)
- `mise run clean` / `mise run clean -- --distclean`
- `mise run clobber` (dry-run) / `mise run clobber -- --yes`

### mise trust warnings

If `mise` prints "Config files ... are not trusted", run `mise trust` once in
this repo to suppress the warnings (this is a per-user setting).

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

### Reference Emacs for baseline checks

When you need to verify behavior against a known-good Emacs (not this fork):

- Prefer the heredoc-friendly task (avoids shell escaping):
  - `mise run clemacs:ref-emacs:eval <<'EL'`
    `(princ (prin1-to-string (progn ...)))`
    `EL`
- An Emacs 31.0.50 server is available as `wip` for interactive/probing evals:
  - `gxeval -s wip -e '(setq gx-elisp-result ...)'` (prefer `--json` + `jq`).

### `src/xwidget.h` must stay (stub header)

Even though `src/xwidget.c` is deleted, `src/xwidget.h` is still required:
it provides inline stubs when `HAVE_XWIDGETS` is off, and core code expects
those definitions to exist in TTY builds.

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
- Wrap body at ~72 columns.
- Lines must be shorter than 78 chars. Words shorter than 140 chars.

## Change hygiene (how to trim safely)

- Prefer deleting whole directories that are clearly out of scope (e.g.
  `nextstep/`, `lwlib/`, `oldXMenu/`).
- After deleting, immediately:
  - remove or gate build-system references (`configure.ac`, `Makefile.in`,
    `src/Makefile.in`, doc makefiles).
  - run `mise run bootstrap -- --force`, then `mise run configure:tty -- --force`.
  - run `mise run verify -- --level check --force`.
- If removing GUI backend sources under `src/`, keep `src/xwidget.h` (stub header)
  even if `src/xwidget.c` is deleted.
- Be careful with ambiguous names:
  - `doc/emacs/windows.texi` is the Emacs "windows" chapter (not MS Windows).

### Bash + `set -u` arrays

Avoid expanding empty arrays under `set -u` (e.g. `"${arr[@]}"`), since Bash
will treat that as an unbound variable. Prefer simple `if` branches for
optional flags (see `.mise/tasks/test/*`).

On macOS, assume the default `/bin/bash` is Bash 3.2: avoid `mapfile`/`readarray`.

## Where plans live

- Roadmap plan: `plan.md` (and never delete plan files).
- Developer notes / iteration notes: `plans/*.md`.

</INSTRUCTIONS>
