# clemacs test contract

This directory is the contract for the SBCL-hosted clemacs bring-up.

It intentionally does **not** reuse the upstream Emacs `test/contract/*`
machinery, because those targets exercise the C-hosted Emacs test harness.

Contract levels:

- `smoke`: fast and deterministic on macOS; should be run constantly.
- `check`: slower gate; may grow over time.
- `elisp-core`: inventory-driven ELisp-core bring-up gate (smoke plus inventory usage report).
