# clemacs tester quickstart (macOS)

clemacs is an experimental, SBCL-hosted Emacs Lisp runtime.  It is **TTY-only**
and intentionally does **not** support GUI backends, dynamic modules, or native
compilation.

## Try it

From a fresh clone:

1. `mise trust` (if prompted)
2. `mise run clemacs:verify`
3. Run the editor:
   - `mise run clemacs:emacs:run -- path/to/file`
   - or just `mise run clemacs:emacs:run` (defaults to `--startup-level tty-editor`)

Useful flags:

- `--startup-level tty-editor` (interactive bring-up slice; this is what testers want)
- `--startup-level editor-core` (deeper load; more likely to hit missing pieces)
- `--no-elisp` (run the TTY loop without loading shipped ELisp; for substrate/TTY triage)

## What to expect

Supported (today):

- TTY editor loop with basic key/command routing
- Visit/edit/save a file (`C-x C-f`, `C-x C-s`)
- `M-x` for a small subset of commands (e.g. `save-buffers-kill-terminal`)

Known missing/incomplete:

- GUI features (removed in this fork)
- Full init-file compatibility (Emacs-shaped `-Q` / `-q` is not complete yet)
- Many shipped ELisp packages and workflows are still being brought up

## Reporting bugs

When something fails, please include:

1. A first-failure report:
   - `mise run clemacs:report:first-failure-startup-check-debug`
2. An issue bundle tarball:
   - `mise run clemacs:report:issue-bundle -- --repro 'mise run clemacs:emacs:run -- path/to/file'`

Then attach `build/clemacs/reports/issue-bundle-latest.tar.gz` to your bug report.
