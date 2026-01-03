# clemacs/ported/

This directory holds mechanically ported copies of upstream ELisp sources.

Load behavior
- The clemacs manifest loader prefers `clemacs/ported/<path>` when it exists,
  otherwise it loads `<path>` from the source tree.

Workflow
- Add a relative path to `clemacs/contract/ported.files`.
- Run `mise run clemacs:port:regen`.
- Commit the generated file(s) under `clemacs/ported/`.

Policy
- Prefer loader shims first (`clemacs/elisp-compat.lisp` etc).
- Use ports only for intentional, documented divergences (lexical-binding
  mismatches, CL keyword policy, etc.).
