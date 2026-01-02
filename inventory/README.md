# C-defined ELisp inventory

This directory is a reproducible, machine-checkable inventory of ELisp surface
area defined in C in this repository (as built in TTY-only mode).

Why
- The SBCL-hosted ELisp engine rewrite needs a concrete checklist of every C
  primitive, special form, variable, and bytecode opcode.
- Keeping this as data reduces “hallucinated” semantics and makes regressions
  obvious during future refactors.

Artifacts
- `inventory/c-elisp.jsonl`: authoritative static inventory extracted from `src/`
- `inventory/c-elisp.tsv`: same data in a grep/spreadsheet-friendly format
- `inventory/runtime-subrs.json`: runtime view of all `subr` functions
- `inventory/runtime-check.json`: runtime checks for static variables/symbols
- `inventory/exceptions.json`: small, explicit exception lists (should be empty or tiny)

Regeneration
- `mise run inventory:regen`
- `mise run inventory:check` (fails if `inventory/` is out of date or mismatched)
