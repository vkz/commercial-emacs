# Agent playbook (clemacs bring-up)

This playbook is the operational guide for SBCL-hosted clemacs bring-up.
It is intentionally practical: run commands, read artifacts, update contracts,
repeat. Keep this doc small and high-signal.

## One command onboarding (copy/paste)

```sh
mise run clemacs:test:contract -- --level elisp-core && mise run clemacs:report:progress
```

If it fails, run:

```sh
mise run clemacs:report:first-failure -- --mode startup-check --debug
```

## Repo-local agent skills (use these)

Repo-local skills live under `.codex/skills/` in this repo. Use them as the default workflow:

- `clemacs-port-loop`: when raising startup checkpoints / adding startup files (gate → first-failure → fix → breadcrumbs → repeat).
- `clemacs-loader-debug`: when a loader failure needs interpretation (inventory mapping, checkpoint bisection, loader backtraces).
- `clemacs-ert-bringup`: when expanding `clemacs/contract/ert-upstream.tests` (must-pass/known-fail monotonic protocol).

## Canonical port loop (tight iteration)

1) Run the constant gate:
   - `mise run clemacs:test:contract -- --level elisp-core`

2) If it fails, extract the *first* actionable failure (do not eyeball the full log):
   - `mise run clemacs:report:first-failure -- --mode startup-check`
   - Read: `build/clemacs/reports/first-failure.md`

3) Apply the decision tree below (missing primitive vs checkpoint vs skip vs ported rewrite).

4) When you change semantics / loader behavior, leave breadcrumbs (see checklist).

5) Re-run the same gate until green, then optionally:
   - `mise run clemacs:test:contract -- --level check` (upstream ERT bring-up must-pass list)

6) Write a progress snapshot:
   - `mise run clemacs:report:progress`

## Decision tree (what to do next)

### A) Loader fails while loading startup manifests

1) Run: `mise run clemacs:report:first-failure -- --mode startup-check --debug`
2) Open: `build/clemacs/reports/first-failure.md`
3) Use the fields:
   - **Path**: the file whose checkpoint needs adjustment (or porting).
   - **Form index**: the exact failing top-level form.
   - **Recommended checkpoint (max-forms)**: safe value to set for that file in
     `clemacs/contract/startup.*.files` while implementing missing pieces.
   - **Inventory**: if present, points to the C-defined primitive symbol and its
     source location in `inventory/c-elisp.tsv`.

- If the report says "No `elisp-load-error` found", scan the Tail for `ELisp load error in ...` anyway; if present, treat it as a bug in `clemacs:report:scan-load-log`.

Then choose one:

- **Missing primitive / unbound variable**
  - Implement or shim the primitive (prefer `clemacs/elisp-compat.lisp` first).
  - Add a microtest if semantics are non-obvious.
  - Keep manifests monotonic: do not delete entries to get green.

- **Non-primitive semantic mismatch**
  - Add/adjust a semantic microtest in `clemacs/contract/semantics.microtests.sexp`.
  - If intentionally diverging from Emacs, set `:emacs nil` and record a dated
    rationale in `plans/clemacs-compat.md` (“Semantic decisions (dated)”).

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
3) Fix, then re-run `check`.

## What artifacts matter (attach these)

When reporting a failure or opening a PR, attach (or paste excerpts from):

- `build/clemacs/reports/first-failure.md`
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
