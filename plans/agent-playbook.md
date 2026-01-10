# Agent playbook (clemacs bring-up)

This playbook is the operational guide for SBCL-hosted clemacs bring-up.
It is intentionally practical: run commands, read artifacts, update contracts,
repeat. Keep this doc small and high-signal.

## One command onboarding (copy/paste)

```sh
mise run clemacs:loop:elisp-core && mise run clemacs:report:progress
```

`clemacs:loop:elisp-core` runs the elisp-core gate and, on failure, generates
the first-failure startup-check debug report automatically.

## Repo-local agent skills (use these)

Repo-local skills live under `.codex/skills/` in this repo. Use them as the default workflow:

- `clemacs-port-loop`: when raising startup checkpoints / adding startup files (gate → first-failure → fix → breadcrumbs → repeat).
- `clemacs-loader-debug`: when a loader failure needs interpretation (inventory mapping, checkpoint bisection, loader backtraces).
- `clemacs-ert-bringup`: when expanding `clemacs/contract/ert-upstream.tests` (must-pass/known-fail monotonic protocol).

## Canonical port loop (tight iteration)

1) Run the constant gate:
   - `mise run clemacs:loop:elisp-core`

2) If it fails, extract the *first* actionable failure (do not eyeball the full log):
   - `mise run clemacs:report:first-failure -- --mode startup-check`
   - Read: `build/clemacs/reports/first-failure.startup-check.md`

3) Apply the decision tree below (missing primitive vs checkpoint vs skip vs ported rewrite).

4) When you change semantics / loader behavior, leave breadcrumbs (see checklist).

5) Re-run the same gate until green, then optionally:
   - `mise run clemacs:test:contract -- --level check` (upstream ERT bring-up must-pass list)
   - `timeout -k 1s 2s mise run clemacs:tty:run` (quick TTY smoke; run in a real TTY, avoid output redirection)
   - `CLEMACS_GRID_PATCH_DUMP=build/clemacs/tmp/grid-patch.jsonl timeout -k 1s 2s mise run clemacs:tty:run` (capture renderer-neutral patch stream; JSONL)

6) Write a progress snapshot:
   - `mise run clemacs:report:progress`

Commit helper (avoids shell quoting issues): `mise run git:commit -- 'scope: subject' <<'MSG' ... MSG`

## Decision tree (what to do next)

### A0) Non-loader failure modes (no `elisp-load-error`)

If `build/clemacs/reports/first-failure.startup-check.md` says "No `elisp-load-error` found", treat
it as a signal that SBCL died or a non-ELisp condition escaped the loader path.

Do this first:

1) Run: `mise run clemacs:report:first-failure-startup-check-debug`
2) Open:
   - log: `build/clemacs/tmp/first-failure.startup-check.log`
   - report: `build/clemacs/reports/first-failure.startup-check.md`
   - debug backtrace (when present): `build/clemacs/tmp/load-debug.startup-check.out`

Common patterns:

- `SB-KERNEL::CONTROL-STACK-EXHAUSTED` during macroexpansion (often `macroexp--all-forms`)
  - Treat it as "macroexpand-all got replaced by upstream and became non-stack-safe".
  - Fix by restoring clemacs' stack-safe `macroexpand-all` shim after `lisp/emacs-lisp/macroexp.el` loads (see `clemacs/elisp.lisp` `%maybe-install-post-load-shims`).

- CL type errors / wrong arity wrapped by `condition-case`
  - Re-run with `CLEMACS_DEBUG_CONDITION_CASE=1` to print the host backtrace at the catch boundary.

- `:READ-ERROR` “Package X does not exist” / “Symbol ... not found in the X package” while loading ELisp
  - Usually indicates an upstream ELisp symbol containing `:` (e.g. `GUI:bottom`) which the current reader treats as CL package syntax.
  - Pragmatic bring-up fix: define a stub CL package (and export the referenced symbols), or add the offending file to `clemacs/contract/lisp.allowed-skip.files` with a dated rationale.

- `SB-EXT:SYMBOL-PACKAGE-LOCKED-ERROR` when adding an ELisp compat definition that collides with CL (e.g. `string-trim`)
  - Add the symbol to `clemacs/package.lisp` `defpackage #:elisp` `:shadow`, and qualify host uses as `cl:...` (e.g. `cl:string-trim`) where needed.
- SBCL's `cl:dolist` expansion may insert `SB-EXT:TRULY-THE (member ...)` for literal lists, which breaks when the elements are themselves lists; prefer `ELISP::DOLIST` (shadowed in `clemacs/package.lisp`) for ELisp code and compat helpers.

- CL string ops vs ELisp strings (common pitfall)
  - `symbol-name` returns an ELisp string (often unibyte); wrap with `elisp::%elisp-string->cl-string` before calling CL functions like `string-downcase`.
  - For ad-hoc reference checks without shell-escaping ELisp, use:
    `mise run clemacs:ref-emacs:eval <<'EL' ... EL`
  - For ad-hoc SBCL-side probes without rediscovering qlot paths or fighting `--eval` quoting, use:
    `mise run clemacs:sbcl:eval <<'LISP' ... LISP`

### A) Loader fails while loading startup manifests

1) Run: `mise run clemacs:report:first-failure -- --mode startup-check --debug`
2) Open: `build/clemacs/reports/first-failure.startup-check.md`
3) Use the fields:
   - **Path**: the file whose checkpoint needs adjustment (or porting).
   - **Form index**: the exact failing top-level form.
   - **Recommended checkpoint (max-forms)**: safe value to set for that file in
     `clemacs/contract/startup.*.files` while implementing missing pieces.
   - **Inventory**: if present, points to the C-defined primitive symbol and its
     source location in `inventory/c-elisp.tsv`.

- If the report says "No `elisp-load-error` found", scan the Tail for `ELisp load error in ...` anyway; if present, treat it as a bug in `clemacs:report:scan-load-log`.
- If SBCL dies with `SB-KERNEL::CONTROL-STACK-EXHAUSTED` during macroexpansion (often `macroexp--all-forms`), prefer restoring the clemacs stack-safe `macroexpand-all` shim after `lisp/emacs-lisp/macroexp.el` loads (see `clemacs/elisp.lisp` `%maybe-install-post-load-shims`).
- If the debug backtrace shows an ELisp error message as a truncated byte vector (`#(85 110 101 ...)`), catch `elisp::elisp-load-error` and print `(elisp::%elisp-string->cl-string (car (elisp::elisp-signal-data (elisp::elisp-load-error-cause e))))` to recover the full string.

Then choose one:

- **Raising startup checkpoints (default strategy)**
  - Default to bigger cap jumps to maintain pace (rule of thumb: `loaddefs.el` +1000; most other files +300–800), then run `mise run clemacs:loop:elisp-core`.
  - If it fails, do not “creep” in tiny increments: bisect immediately when the failing point is unclear or too far into the file:
    - `mise run clemacs:bisect:file -- --file <lisp/.../foo.el> --manifest clemacs/contract/startup.check.files`
  - Set the manifest checkpoint to the reported “max passing max-forms”, fix only the top offender from `build/clemacs/reports/first-failure.startup-check.md`, then repeat with another big jump.

- **Missing primitive / unbound variable**
  - Implement or shim the primitive (prefer `clemacs/elisp-compat.lisp` first).
  - When writing CL-level helpers inside the `ELISP` package (e.g. setf expanders), qualify CL names like `cl:values` to avoid `ELISP::` resolution bugs.
  - Add a microtest if semantics are non-obvious.
  - Keep manifests monotonic: do not delete entries to get green.

- **Non-primitive semantic mismatch**
  - Add/adjust a semantic microtest in `clemacs/contract/semantics.microtests.sexp`.
  - If intentionally diverging from Emacs, set `:emacs nil` and record a dated
    rationale in `plans/clemacs-compat.md` (“Semantic decisions (dated)”).
  - If using `:emacs :match`, tests run a reference Emacs in `-Q --batch` mode
    (not `gxeval`); the binary is taken from `CLEMACS_REFERENCE_EMACS` or falls
    back to `emacs` on `PATH`. For ad-hoc probing without shell-escaping, use
    `mise run clemacs:ref-emacs:eval <<'EL' ... EL`.
  - For interactive probing, use the `emacs` skill via `gxeval -s wip ...`.
  - If a `:emacs :match` microtest errors with `reference Emacs failed`, use the reported `expr:` string to locate the entry in `clemacs/contract/semantics.microtests.sexp` and decide whether to update clemacs semantics or mark the test `:emacs nil` with a dated compat note.
  - If `ELISP-SEMANTICS-MICROTESTS` fails with an unexpected error, re-run `mise run clemacs:test:smoke` and use the reported microtest name + `expr:` to iterate.

- **Checkpoint seems unstable / flaky**
  - Bisect to a stable checkpoint (in manifest context):
    - `mise run clemacs:bisect:file -- --file <lisp/.../foo.el> --manifest clemacs/contract/startup.check.files`
  - Use the reported “max passing max-forms” value as your checkpoint while you fix the underlying issue.

- **Depends on removed features**
  - Prefer adding a dated skip entry (with rationale) to the relevant clemacs
    allowed-skip manifest under `clemacs/contract/`.

### B) Upstream ERT bring-up regression

1) Run: `mise run clemacs:test:contract -- --level check`
2) If a must-pass test now fails:
   - Confirm it is listed in `clemacs/contract/ert-upstream.tests` (must-pass).
   - If the failure is temporary, move it to
     `clemacs/contract/ert-upstream.known-fail.tests` with a dated reason.
   - XPASS is a gate failure: remove from known-fail once fixed.
   - If the failure is due to missing preload wiring (e.g. global bindings), add the minimal file + `max-forms` entry to `clemacs/contract/ert-upstream.load.files` (quickly find the smallest working cap with a `mise run clemacs:sbcl:eval` loop).
   - If the failure is a wrapped SBCL condition (e.g. "invalid number of arguments"), re-run with `CLEMACS_DEBUG_CONDITION_CASE=1` to print the captured CL backtrace at the `condition-case` boundary.
   - If backtraces are shallow due to the per-test thread/timeout wrapper, set `CLEMACS_ERT_TEST_TIMEOUT_SECS=0` while debugging to run in the main thread.
   - To isolate one (or a small ordered sequence of) upstream test name(s) with the same debug knobs, use `mise run clemacs:test:ert-upstream-one -- --debug-condition-case <ert-test-name> [more-tests...]` (optionally add `CLEMACS_ERT_DEBUG=1` for richer failure payloads; dynamic tests like `ert-test-abc`/`ert-test-def` must be preceded by `ert-test-deftest`).
3) Fix, then re-run `check`.

## What artifacts matter (attach these)

When reporting a failure or opening a PR, attach (or paste excerpts from):

- `build/clemacs/reports/first-failure.startup-check.md`
- `build/clemacs/reports/progress.md`
- Any relevant bisect report: `build/clemacs/reports/bisect-*.md`

## No-rediscovery checklist (required)

Before declaring a clemacs port iteration “done”, ensure:

- If semantics changed: add/update `clemacs/contract/semantics.microtests.sexp`.
- If divergence is intentional: add a dated entry to `plans/clemacs-compat.md`.
- If startup meaning changed: update `clemacs/contract/startup.*.files` monotonically.
- If upstream ERT bring-up changed: update `clemacs/contract/ert-upstream.tests` /
  `clemacs/contract/ert-upstream.known-fail.tests` monotonically.
- Re-run the appropriate gate:
  - Constant: `mise run clemacs:test:contract -- --level elisp-core`
  - Broader: `mise run clemacs:test:contract -- --level check`

## Introspection rule (keep improving the system)

If you get stuck or rediscover a technique (e.g., a reliable way to interpret a
failure, a useful debug flag, a missing helper task):

- Add exactly **one** new bullet to this playbook **or** add exactly **one** new
  helper task/subcommand. Keep it minimal and high-signal.
- When writing multi-line `git commit -m` messages in zsh, use `$'...'` quoting so newlines are real newlines (not literal `\\n`), otherwise the repo hooks may flag line/word-length issues.
- If SBCL reports “unmatched close parenthesis” in a large `clemacs/elisp-compat/*.lisp`, isolate the suspect defun chunk and compare `(` vs `)` counts (quick Python one-liner) to locate the extra `)`.
- If `with-current-buffer`/`save-current-buffer` behaves strangely, check for macro variable capture: compatibility macros must use `gensym`d locals (avoid plain names like `buf`), since dynamic binding can shadow user vars and silently break `set-buffer` targets.
- If `startup-check` fails in `lisp/emacs-lisp/seq.el` with a `cl-defgeneric` error like “already names an ordinary function”, check for early clemacs stubs (e.g. `seq-filter`) and ensure `cl-defgeneric` can drop placeholder fdefinitions before defining the generic.
- When adding top-level initializers inside the `ELISP` package, qualify CL operators/predicates (`cl:>`, `cl:=`, `cl:<=`, etc.) and avoid calling ELisp helpers at load time unless they are already defined (package `:shadow` makes unqualified operators resolve to `ELISP::...`).
- If a contract run starts printing a minibuffer prompt, check for missing early returns in `completing-read`/`read-from-minibuffer` noninteractive paths; prompts can consume task output and hang gates.
- Avoid binding local functions/macros named after `CL` symbols inside the `ELISP` package (SBCL package locks): e.g. don’t `labels` a helper named `bit`; pick `mode-bit`/`%bit` instead.
- When upgrading `load`/`require`, keep `get-load-suffixes` to `.el` only (there are checked-in `.elc` files, but clemacs can’t load bytecode).
- If `startup-check` fails with `:READ-ERROR` (often “end of file”), use `mise run clemacs:ref-emacs:eval` to print the failing top-level form by index and identify the unsupported reader syntax (e.g. `?\\^?`).
- If shipped key bindings don’t take (e.g. `C-x` isn’t a prefix), verify `\\C-` string escapes are being interpreted by checking `(lookup-key (current-global-map) (vector 24) t)` after loading `lisp/subr.el`.
- When debugging ELisp macros via `mise run clemacs:sbcl:eval`, remember the script runs in the `ELISP` package: use `cl:format` (not `format`), and build tricky reader forms (e.g. backquote pcase patterns) with `read-from-string` to match clemacs' ELisp reader representation.
- When writing `handler-case` probes under `mise run clemacs:sbcl:eval` in the `ELISP` package, qualify condition types (e.g. use `(cl:error (e) ...)` or `(cl:condition (c) ...)`), since unqualified `error` resolves to `ELISP::ERROR` (not a CL condition type).
- If a startup raise “hangs”, wrap the suspect `(elisp:load-elisp-file ...)` in `sb-ext:with-timeout` and use `handler-bind` on `sb-ext:timeout` to print a useful backtrace at the signal point (a `handler-case` timeout handler runs after unwinding, so the stack is usually gone).
- To avoid noisy backtraces from expected ELisp signals, set `CLEMACS_DEBUG_CONDITION_CASE=cl` to print backtraces only for wrapped host (CL) errors caught by `condition-case`.
- When shelling out from compat code via `uiop:run-program`, don’t pass stdin as a raw string: a string is treated as a pathname; use `(make-string-input-stream ...)` (or a temp file) for region input.
- When implementing `process-attributes` via `ps`, note that macOS `ps` rejects `euid`/`egid` keywords; use `uid`/`gid` (and still return `euid`/`egid` keys in the alist).
- If `minibuffer-selected-window` starts returning non-nil at top level after minibuffer changes, ensure `read-from-minibuffer` clears `*clemacs-minibuffer-active-p*` in `unwind-protect` cleanup (avoid early `return-from`; verify via `mise run clemacs:sbcl:eval`).
